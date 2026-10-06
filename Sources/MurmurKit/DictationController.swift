import AppKit
import ApplicationServices
import Audio
import Cleanup
import Context
import Core
import Foundation
import Hotkey
import Insertion
import Pipeline
import SpeechEngines
import Store
import os

/// Timings and reasons only, never transcript text (spec rule 2).
let log = Logger(subsystem: "com.swaritsheel.Murmur", category: "dictation")

public enum UISound: String, Sendable, CaseIterable {
    case start, stop, done, error
}

public protocol SoundPlaying: Sendable {
    @MainActor func play(_ sound: UISound)
}

/// What the menu-bar icon and menu show.
public struct DictationStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading
        case idle
        case recording(handsFree: Bool)
        case processing
        /// The paste just went out. The Flow Bar shows a brief confirmation.
        case inserted
        case error
    }

    public enum NoticeKind: String, Equatable, Sendable {
        case pasteError, transcriptionError, noTextBox, cancelled, info, micError, flowBarHidden, suggestion, noAudio
    }

    public struct Notice: Equatable, Sendable {
        public var kind: NoticeKind
        public var message: String
    }

    public var phase: Phase
    /// A notice for the menu: an error, a cancelled dictation, a permission problem.
    public var message: String?
    public var lastTranscript: String?
    /// The same notice, typed, for the Flow Bar's buttons (Retry, Undo, Dismiss).
    public var notice: Notice?
    /// The current recording or processing is a Command Mode instruction.
    public var command = false
}

/// Key events in, text out. Owns the recorder, engines, History and insertion, and drives the Core
/// state machine so every transition is checked and signposted. Runs on the main actor so key events
/// are handled in order; the slow work happens on the engine and cleanup actors.
@MainActor
public final class DictationController {
    public var onStatus: ((DictationStatus) -> Void)?
    /// Microphone level in dBFS while recording, read by the Flow Bar and the mic test at display rate.
    public let micLevel = MicLevelSource()
    public private(set) var status = DictationStatus(phase: .loading) {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    let settings: AppSettings
    let store: HistoryStore
    /// A9: in never-store mode every write goes to an in-memory History, so nothing reaches disk but
    /// Paste last still works for the session.
    let memoryStore = try! HistoryStore(url: nil)
    var history: HistoryStore { settings.neverStore ? memoryStore : store }
    let sounds: SoundPlaying?
    let recorder: AudioRecorder
    let gate = EnergySpeechGate()
    let insertion = InsertionTransaction(requireEditable: false)
    let state = DictationStateHolder()

    var recognizer: HotkeyRecognizer
    var tap: KeyEventTap?
    var capsMonitor: CapsLockMonitor?
    var engine: (any SpeechEngine)?
    var engineId: String?
    var cleanupProvider: (any CleanupProvider)?
    var cleanupId: String?
    var loadingTask: Task<Void, Never>?

    struct Session {
        let token = UUID()
        var mode: DictationMode
        let keyDownAt: UInt64
        let startedAt: Date
        let focus: FocusSnapshot
        var recordId: String?
    }

    var session: Session?
    var processing: Task<Void, Never>?
    /// D7: watches the recording for the 20-minute limit and a microphone that stops sending audio.
    var watchdog: Task<Void, Never>?
    public var recordingLimits = RecordingLimits(maxSeconds: ProcessInfo.processInfo.environment["MURMUR_MAX_RECORDING_S"].flatMap(Double.init) ?? 1200)
    /// Why the current recording was stopped automatically, shown once its text is inserted.
    var autoStopReason: String?
    /// Section 7: the cleanup model is unloaded after this long without a dictation, and reloaded as
    /// soon as the next one starts.
    var idleUnloadAfter: Duration = .seconds(ProcessInfo.processInfo.environment["MURMUR_IDLE_UNLOAD_S"].flatMap(Double.init) ?? 600)
    var idleUnload: Task<Void, Never>?
    var cleanupReload: Task<Void, Never>?
    public private(set) var cleanupUnloaded = false
    var engineReload: Task<Void, Never>?
    public private(set) var engineUnloaded = false

    /// S2: the field Murmur last pasted into, what it pasted, and the field's text right after.
    var lastInsertion: (element: AXUIElement, text: String, value: String)?
    var correctionCheck: Task<Void, Never>?
    /// The dictionary suggestion on the Flow Bar, and the ones dismissed this session.
    public private(set) var pendingSuggestion: CorrectionDetector.Suggestion?
    var dismissedSuggestions: Set<String> = []
    /// The dictionary and snippets (S1, S3), reloaded when they change.
    var rules = RulesCleaner()
    var vocabulary: [String] = []
    var aliases: [String: [String]] = [:]
    /// Why the last start request did not start a recording (diagnostics for the focus test).
    public private(set) var lastBeginRefusal: String?
    /// The last cancelled or failed dictation's audio, for Undo and Retry on the Flow Bar.
    var lastCancelled: (session: Session, samples: [Float], recordId: String?)?
    var lastFailed: (session: Session, samples: [Float], recordId: String)?
    /// Audio of the dictation being processed, so a cancel during processing can still be undone.
    var processingSamples: [Float]?

    public init(settings: AppSettings = .shared, store: HistoryStore, sounds: SoundPlaying?) {
        self.settings = settings
        self.store = store
        self.sounds = sounds
        recorder = AudioRecorder(onLevel: { [micLevel] level in micLevel.write(level) })
        recognizer = HotkeyRecognizer(configuration: Self.shortcutConfiguration(settings))
        recorder.setDevice(uid: settings.microphoneUID)
    }

    /// The configured shortcuts (D8), or the defaults for the keyboard layout.
    public static func shortcutConfiguration(_ settings: AppSettings) -> HotkeyConfiguration {
        let apple = settings.keyboardLayout != "other"
        var config = apple ? HotkeyConfiguration.appleKeyboard : .otherKeyboard
        if let data = settings.shortcuts, let saved = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) { config = saved }
        // Command Mode's shortcut only listens while Command Mode is on (M1).
        config.command = settings.commandMode ? (config.command ?? HotkeyConfiguration.defaultCommand(appleKeyboard: apple)) : nil
        return config
    }

    public var shortcutConfiguration: HotkeyConfiguration { recognizer.configuration }

    public func setShortcuts(_ configuration: HotkeyConfiguration?) {
        settings.shortcuts = configuration.flatMap { try? JSONEncoder().encode($0) }
    }

    /// While the user records a new shortcut, key events must not start dictations.
    public var shortcutsPaused = false

    // MARK: Lifecycle

    /// Loads the models and starts listening for the shortcut. Safe to call again after permissions change.
    public func start() {
        reloadVocabulary()
        NotificationCenter.default.addObserver(forName: HistoryStore.vocabularyDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadVocabulary() }
        }
        reloadModels()
        startKeyTap()
        purgeOldAudio()
        recorder.prepare()
        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] note in
            let key = note.object as? String
            MainActor.assumeIsolated { self?.settingsChanged(key) }
        }
    }

    public func startKeyTap() {
        guard tap == nil || tap?.isRunning == false else { return }
        let tap = KeyEventTap { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        do {
            try tap.start()
            self.tap = tap
            if status.message == Self.inputMonitoringMessage { status.message = nil }
        } catch {
            self.tap = nil
            status.message = Self.inputMonitoringMessage
        }
        updateCapsLockMonitor()
    }

    /// Caps Lock needs the keyboard HID; only listen when it is one of the shortcuts.
    func updateCapsLockMonitor() {
        let config = recognizer.configuration
        if config.pushToTalk == .capsLock || config.handsFree == .capsLock {
            guard capsMonitor == nil else { return }
            let monitor = CapsLockMonitor { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
            }
            if monitor.start() { capsMonitor = monitor }
        } else {
            capsMonitor?.stop()
            capsMonitor = nil
        }
    }

    static let inputMonitoringMessage = "Murmur needs Input Monitoring to hear the shortcut. Open Check Permissions."

    public var isListening: Bool { tap?.isRunning ?? false }

    /// Builds the rules stage, the engine bias and the cleanup vocabulary from the dictionary and snippets.
    /// A plain word maps to itself, which fixes its capitalization ("kubernetes" -> "Kubernetes").
    func reloadVocabulary() {
        let entries = (try? store.dictionary()) ?? []
        let snippets = (try? store.snippets()) ?? []
        var mappings: [DictionaryEntry] = []
        var aliases: [String: [String]] = [:]
        for entry in entries {
            let heard = entry.heardAs.isEmpty ? [entry.replacement] : entry.heardAs
            for h in heard { mappings.append(DictionaryEntry(term: h, replacement: entry.replacement)) }
            if !entry.heardAs.contains(entry.replacement) { mappings.append(DictionaryEntry(term: entry.replacement, replacement: entry.replacement)) }
            let others = heard.filter { $0.caseInsensitiveCompare(entry.replacement) != .orderedSame }
            if !others.isEmpty { aliases[entry.replacement] = others }
        }
        rules = RulesCleaner(dictionary: mappings, snippets: snippets.map { Snippet(cue: $0.cue, expansion: $0.expansion) })
        vocabulary = Array(Set(entries.map(\.replacement))).sorted()
        self.aliases = aliases
        log.notice("vocabulary: \(entries.count) dictionary entries, \(snippets.count) snippets")
        prewarmCleanup()
    }

    /// Builds the cleanup model's cached instructions for the current dictionary and settings.
    func prewarmCleanup() {
        guard let provider = cleanupProvider else { return }
        let request = currentCleanupRequest
        let transforms = settings.transformsEnabled, command = settings.commandMode
        Task {
            if transforms { await CleanupRunner(rules: rules, provider: provider).prewarm(request) }
            // Command Mode's instructions and examples, so the first command is as fast as the rest.
            if command { await provider.prewarm(CommandPrompt.messages(instruction: "OK", selection: nil)) }
        }
    }

    var currentCleanupRequest: CleanupRequest {
        CleanupRequest(
            level: CleanupLevel(rawValue: settings.cleanupLevel) ?? .light, vocabulary: vocabulary,
            smartFormatting: settings.smartFormatting)
    }

    func settingsChanged(_ key: String?) {
        switch key {
        case "engine", "cleanupProvider": reloadModels()
        case "keyboardLayout", "shortcuts", "commandMode":
            recognizer = HotkeyRecognizer(configuration: Self.shortcutConfiguration(settings))
            updateCapsLockMonitor()
            if key == "commandMode" { prewarmCleanup() }
        case "microphoneUID": recorder.setDevice(uid: settings.microphoneUID)
        case "cleanupLevel", "smartFormatting", "transformsEnabled": prewarmCleanup()
        default: break
        }
    }

    /// Loads whatever Settings asks for. The old engine keeps working until the new one is ready, so a
    /// switch applies to the next dictation without a restart (T1).
    public func reloadModels() {
        let wantEngine = settings.engine, wantCleanup = settings.cleanupProvider
        guard wantEngine != engineId || wantCleanup != cleanupId else { return }
        loadingTask?.cancel()
        if engine == nil { status.phase = .loading }
        let groqKey: @Sendable () -> String? = { Keychain.get("groq") ?? ProcessInfo.processInfo.environment["GROQ_API_KEY"] }
        let openRouterKey: @Sendable () -> String? = { Keychain.get("openrouter") ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] }
        loadingTask = Task { [weak self] in
            var problems: [String] = []
            if wantEngine != self?.engineId {
                do {
                    let e = try EngineCatalog.make(wantEngine, groqKey: groqKey)
                    try await e.load()
                    self?.engine = e
                    self?.engineId = wantEngine
                } catch {
                    problems.append("Speech engine \(wantEngine) failed to load: \(error)")
                }
            }
            if wantCleanup != self?.cleanupId {
                do {
                    let p = try CleanupCatalog.make(wantCleanup, groqKey: groqKey, openRouterKey: openRouterKey)
                    try await p?.load()
                    self?.cleanupProvider = p
                    self?.cleanupId = wantCleanup
                    self?.cleanupUnloaded = false
                } catch {
                    // Rules-only cleanup still works, so dictation keeps going.
                    self?.cleanupProvider = nil
                    self?.cleanupId = wantCleanup
                    problems.append("Cleanup model \(wantCleanup) failed to load, using rules only: \(error)")
                }
            }
            guard let self else { return }
            self.prewarmCleanup()
            self.scheduleIdleUnload()
            if self.status.phase == .loading { self.status.phase = self.engine == nil ? .error : .idle }
            if !problems.isEmpty { self.status.message = problems.joined(separator: "\n") }
        }
    }

    // MARK: Keys

    func handle(_ event: KeyEvent) {
        if shortcutsPaused || micTestRunning { return }
        for action in recognizer.handle(event) {
            perform(action)
        }
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .startHold: begin(.hold)
        case .startHandsFree: begin(.handsFree)
        case .convertToHandsFree:
            if session != nil, recorder.isRunning {
                session?.mode = .handsFree
                status.phase = .recording(handsFree: true)
            }
        case .stopHold, .stopHandsFree, .stopCommand: finish()
        case .discard: discard()
        case .cancel: cancel()
        case .startCommand: begin(.command)
        case .convertToCommand:
            if session != nil, recorder.isRunning {
                session?.mode = .command
                status.command = true
            }
        }
    }

    /// Hands-free start from the menu or a click (the Flow Bar arrives in Milestone 2).
    public func toggleHandsFree() {
        if session != nil, recorder.isRunning { finish() } else { begin(.handsFree) }
    }

    func begin(_ mode: DictationMode) {
        let keyDownAt = Clock.now()
        guard engine != nil else {
            status.message = "Models are still loading."
            recognizer.reset()
            lastBeginRefusal = "models still loading"
            log.notice("begin refused: models still loading")
            return
        }
        // One dictation at a time; a press while busy is ignored (D5). A notice from an earlier error
        // does not block a new dictation.
        if case .error = state.state { state.send(.dismiss) }
        if state.state == .cancelled { state.send(.dismiss) }
        guard state.send(.start(mode)) != nil else {
            recognizer.reset()
            lastBeginRefusal = "busy (\(state.state.name))"
            log.notice("begin refused: busy in \(self.state.state.name, privacy: .public)")
            return
        }
        let focus = FocusContext.snapshot()
        do {
            try recorder.start()
        } catch {
            state.send(.cancel)
            state.send(.dismiss)
            recognizer.reset()
            lastBeginRefusal = "microphone: \(error)"
            log.error("microphone start failed: \(String(describing: error), privacy: .public)")
            recorder.forceRebuild()
            fail("The microphone is unavailable (\(recorder.deviceName)). Check it is connected, then Retry.", kind: .micError)
            return
        }
        lastBeginRefusal = nil
        idleUnload?.cancel()
        reloadIfUnloaded()
        log.debug("recording started (\(mode.rawValue, privacy: .public)) in \(Format.ms(Clock.ms(since: keyDownAt)), privacy: .public)")
        let newSession = Session(mode: mode, keyDownAt: keyDownAt, startedAt: Date(), focus: focus)
        session = newSession
        autoStopReason = nil
        watch(newSession.token)
        status = DictationStatus(phase: .recording(handsFree: mode == .handsFree), message: nil, lastTranscript: status.lastTranscript, notice: nil, command: mode == .command)
        Signposts.transition(from: "key-down", to: "recording (\(Format.ms(Clock.ms(since: keyDownAt))))")
        if settings.soundsEnabled { sounds?.play(.start) }
    }

    /// D7: once a second while recording, warn a minute before the limit, stop at the limit, and stop
    /// when no audio has arrived for a few seconds. Stopping transcribes and inserts what was heard.
    func watch(_ token: UUID) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            var warned = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let session = self.session, session.token == token, self.recorder.isRunning else { return }
                let elapsed = Clock.ms(since: session.keyDownAt) / 1000
                let sinceAudio = Clock.ms(since: max(self.recorder.lastAudioAt ?? 0, session.keyDownAt)) / 1000
                switch self.recordingLimits.check(elapsed: elapsed, sinceAudio: sinceAudio, warned: warned) {
                case .none:
                    break
                case .warn:
                    warned = true
                    self.status.message = "One minute left: this dictation stops at 20 minutes."
                    if self.settings.soundsEnabled { self.sounds?.play(.error) }
                    log.notice("recording: one minute left")
                case .stopAtLimit:
                    self.autoStopReason = "Stopped at the 20-minute limit. Everything you said was transcribed."
                    log.notice("recording: stopped at the limit")
                    self.recognizer.reset()
                    self.finish()
                    return
                case .stopNoAudio:
                    self.autoStopReason = "The microphone stopped sending audio, so Murmur stopped and transcribed what it heard."
                    log.notice("recording: no audio for \(Format.ms(sinceAudio * 1000), privacy: .public), stopping")
                    self.recognizer.reset()
                    self.recorder.forceRebuild()
                    self.finish()
                    return
                }
            }
        }
    }

    func discard() {
        guard session != nil, recorder.isRunning else { return }
        _ = recorder.stop()
        session = nil
        state.send(.discard)
        status.phase = .idle
    }

    func finish() {
        guard let session, recorder.isRunning else { return }
        let releasedAt = Clock.now()
        let samples = recorder.stop()
        let flushMs = Clock.ms(since: releasedAt)
        let firstAudioMs = recorder.firstAudioMs
        if settings.soundsEnabled { sounds?.play(.stop) }
        status.phase = .processing
        processingSamples = samples
        processing = Task { [weak self] in
            await self?.process(session, samples: samples, releasedAt: releasedAt, flushMs: flushMs, firstAudioMs: firstAudioMs)
        }
    }

    // MARK: Pipeline

    func isCurrent(_ token: UUID) -> Bool { session?.token == token && !Task.isCancelled }

    func process(_ started: Session, samples: [Float], releasedAt: UInt64, flushMs: Double, firstAudioMs: Double?) async {
        let token = started.token
        var timings = StageTimings()
        timings.captureFlushMs = flushMs
        let audioMs = Double(samples.count) / AudioFormat.sampleRate * 1000

        guard await gate.hasSpeech(samples), isCurrent(token) else {
            if isCurrent(token) {
                endSession(.discard)
                noAudio(after: audioMs)
            }
            return
        }
        guard state.send(.stop) != nil, let engine else { return }

        // Save the audio and the History row before transcribing, so nothing is lost if anything below fails.
        let id = UUID().uuidString
        var audioPath: String?
        if settings.keepAudio && !settings.neverStore {
            let url = MurmurPaths.audio.appendingPathComponent("\(id).wav")
            audioPath = url.path
            Task.detached(priority: .utility) { try? WAV.write(samples, to: url) }
        }
        let record = DictationRecord(
            id: id, startedAt: started.startedAt, durationMs: audioMs, appBundleId: started.focus.bundleId,
            appName: started.focus.appName, mode: started.mode.rawValue, engine: engine.id,
            cleanup: cleanupProvider?.id ?? "rules", status: .recorded, audioPath: audioPath
        )
        _ = try? history.insert(record)
        session?.recordId = id

        // Transcribe.
        let raw: String
        do {
            let t0 = Clock.now()
            // An engine unloaded while idle reloads during the recording; wait for it if it is not done.
            await engineReload?.value
            raw = try await engine.transcribe(samples, options: TranscribeOptions(
                language: settings.engineLanguage, vocabulary: vocabulary, aliases: aliases))
            timings.transcribeMs = Clock.ms(since: t0)
        } catch {
            guard isCurrent(token) else { return }
            _ = try? history.update(id: id) { $0.status = .transcriptionFailed; $0.errorCode = String(describing: error) }
            state.send(.transcriptionFailed)
            lastFailed = (started, samples, id)
            endSession(.dismiss)
            fail("Transcription failed. The audio is saved in History.", kind: .transcriptionError)
            return
        }
        guard isCurrent(token) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The raw transcript reaches disk before cleanup starts (T2).
        _ = try? history.update(id: id) { $0.rawText = trimmed; $0.status = .transcribed; $0.timings = timings }
        guard !trimmed.isEmpty else {
            _ = try? history.update(id: id) { $0.status = .cancelled; $0.errorCode = "empty" }
            endSession(.discard)
            noAudio(after: audioMs)
            return
        }
        state.send(.transcribed(trimmed))

        // C11: "… press enter" at the end presses Return after the paste, when that is turned on.
        let (spoken, pressEnterAfter) = started.mode == .command ? (trimmed, false) : PressEnter.split(trimmed, enabled: settings.pressEnter)
        if pressEnterAfter, spoken.isEmpty {
            _ = try? history.update(id: id) { $0.cleanText = ""; $0.status = .inserted; $0.errorCode = "press enter" }
            state.send(.cleaned(""))
            state.send(.inserted)
            session = nil
            processing = nil
            KeyPresser.pressReturn()
            status.phase = .inserted
            return
        }

        let finalText: String
        var replacesSelection = false
        if started.mode == .command {
            // Command Mode (M2): the transcript is an instruction for the selection, or for a draft.
            guard let provider = cleanupProvider else {
                _ = try? history.update(id: id) { $0.status = .transcriptionFailed; $0.errorCode = "no model" }
                state.send(.cancel)
                endSession(.dismiss)
                fail("Command Mode needs a local or cloud model. Choose one in Settings › General › Models.")
                return
            }
            // A command needs the model: if it was unloaded while idle, wait for the reload.
            await cleanupReload?.value
            let selection = await SelectionReader.selectedText(in: started.focus.element, bundleId: started.focus.bundleId)
            guard isCurrent(token) else { return }
            let outcome = await CommandRunner(provider: provider).run(instruction: trimmed, selection: selection)
            timings.llmMs = outcome.ms
            log.notice("command: \(outcome.text == nil ? (outcome.timedOut ? "timeout" : "error") : "ok", privacy: .public) after \(Format.ms(outcome.ms), privacy: .public), \(selection?.isEmpty == false ? "selection" : "draft", privacy: .public)")
            guard isCurrent(token) else { return }
            guard let text = outcome.text else {
                _ = try? history.update(id: id) { $0.status = .transcriptionFailed; $0.errorCode = outcome.timedOut ? "command timeout" : "command failed" }
                state.send(.cancel)
                endSession(.dismiss)
                fail(outcome.timedOut ? "The command took too long. Try a shorter instruction." : "The command failed. Your instruction is in History.")
                return
            }
            finalText = text
            replacesSelection = selection?.isEmpty == false
        } else {
            // Clean up: rules, model with the time limit, guard; rule-cleaned text as the fallback.
            // C1: the Transforms switch turns every AI edit off; the rules stage still runs.
            let provider = settings.transformsEnabled ? cleanupProvider : nil
            // After an idle unload the model reloads from key-down (~1.3 s), usually before key-up. A
            // dictation shorter than that would otherwise get only the rules: wait for the reload, up to
            // a limit, so it still gets the model's cleanup.
            if provider != nil, let reload = cleanupReload {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await reload.value }
                    group.addTask { try? await Task.sleep(for: Self.cleanupReloadWait) }
                    await group.next()
                    group.cancelAll()
                }
                guard isCurrent(token) else { return }
            }
            let request = currentCleanupRequest
            let outcome = await CleanupRunner(rules: rules, provider: provider).run(spoken, request: request)
            timings.rulesMs = outcome.rulesMs
            timings.llmMs = outcome.llmMs
            log.notice("cleanup: \(outcome.fallback?.rawValue ?? (provider == nil ? "rules" : "model"), privacy: .public) after \(Format.ms(outcome.llmMs ?? 0), privacy: .public)\(outcome.flags.isEmpty ? "" : " flags " + outcome.flags.map(\.kind).joined(separator: ","), privacy: .public)")
            guard isCurrent(token) else { return }
            // S4: the style of the category the target app belongs to. None pastes the raw words.
            finalText = request.level == .none ? outcome.text : style(for: started.focus).apply(to: outcome.text)
        }
        _ = try? history.update(id: id) { $0.cleanText = finalText; $0.timings = timings }
        guard state.send(.cleaned(finalText)) != nil else { return }

        // Insert through the focus guard and the clipboard transaction. A command's rewrite replaces the
        // selection as it is, so one Cmd+Z brings the selection back.
        let current = FocusContext.snapshot()
        let text = replacesSelection ? finalText : SmartSpacing.adjust(finalText, before: SmartSpacing.characterBeforeCursor(of: current.element))
        let insertStart = Clock.now()
        let pasted = PasteClock()
        let typeInstead = current.bundleId.map(settings.typingApps.contains) ?? false
        let result = await insertion.insert(text, expected: started.focus, current: current, typeInstead: typeInstead) { pasted.mark() }
        if let at = pasted.value {
            timings.insertMs = Clock.ms(from: insertStart, to: at)
            timings.totalMs = Clock.ms(from: releasedAt, to: at)
        }
        status.lastTranscript = finalText

        switch result {
        case .inserted:
            if pressEnterAfter {
                try? await Task.sleep(for: .milliseconds(120))
                KeyPresser.pressReturn()
            }
            _ = try? history.update(id: id) { $0.status = .inserted; $0.timings = timings }
            state.send(.inserted)
            session = nil
            processing = nil
            if let reason = autoStopReason {
                autoStopReason = nil
                status.message = reason
                status.notice = DictationStatus.Notice(kind: .info, message: reason)
            }
            status.phase = .inserted
            if started.mode != .command { rememberInsertion(text, in: current.element) }
            scheduleIdleUnload()
            if settings.soundsEnabled { sounds?.play(.done) }
            if firstAudioMs != nil { Signposts.transition(from: "released", to: "inserted \(timings.summary)") }
        case .failed(let failure):
            let kind: DictationErrorKind = failure == .noTextBox ? .noTextBox : .pasteFailed
            _ = try? history.update(id: id) {
                $0.status = kind == .noTextBox ? .noTextBox : .pasteFailed
                $0.errorCode = failure.rawValue
                $0.timings = timings
            }
            state.send(.insertionFailed(kind, text: finalText))
            endSession(.dismiss)
            fail(Self.message(for: failure, app: started.focus.appName), kind: kind == .noTextBox ? .noTextBox : .pasteError)
        }
    }

    // MARK: Idle unload (section 7)

    /// After 10 minutes without a dictation, frees both models (about 2.3 GB); the next key press
    /// reloads them while the user speaks.
    func scheduleIdleUnload() {
        idleUnload?.cancel()
        guard settings.unloadWhenIdle else { return }
        let delay = idleUnloadAfter
        idleUnload = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.unloadModelsNow()
        }
    }

    /// Unloads the speech engine and the cleanup model unless a dictation or mic test is running.
    public func unloadModelsNow() async {
        guard session == nil, !micTestRunning, engineReload == nil, cleanupReload == nil else { return }
        if !engineUnloaded, let engine, engine.isLocal {
            engineUnloaded = true
            await engine.unload()
        }
        if !cleanupUnloaded, let provider = cleanupProvider {
            cleanupUnloaded = true
            await provider.unload()
        }
        log.notice("models unloaded while idle")
    }

    /// Starts reloading whatever was unloaded. The engine is awaited before transcribing; cleanup that
    /// runs before its model is back falls back to the rules (the runner treats "not loaded" as a
    /// provider error), and Command Mode waits for it.
    func reloadIfUnloaded() {
        if engineUnloaded, engineReload == nil, let engine {
            engineReload = Task { @MainActor [weak self] in
                let start = Clock.now()
                try? await engine.load()
                guard let self else { return }
                self.engineUnloaded = false
                self.engineReload = nil
                log.notice("speech engine reloaded in \(Format.ms(Clock.ms(since: start)), privacy: .public)")
            }
        }
        if cleanupUnloaded, cleanupReload == nil, let provider = cleanupProvider {
            // The reload counts as done once the prompt this dictation will use is warm, so the dictation
            // (which waits for it, up to `cleanupReloadWait`) is not queued behind any warm-up. Command
            // Mode's prompt is left to warm on its first use: a command waits for the model anyway.
            let request = currentCleanupRequest
            let transforms = settings.transformsEnabled
            let rules = self.rules
            cleanupReload = Task { @MainActor [weak self] in
                let start = Clock.now()
                try? await provider.load()
                if transforms { await CleanupRunner(rules: rules, provider: provider).prewarm(request) }
                guard let self else { return }
                self.cleanupUnloaded = false
                self.cleanupReload = nil
                log.notice("cleanup model reloaded and warm in \(Format.ms(Clock.ms(since: start)), privacy: .public)")
            }
        }
    }

    // MARK: Dictionary suggestions (S2)

    /// Keeps what was pasted and the field's text right after, then checks for corrections 15 and 45 s
    /// later. Only the field Murmur pasted into is read, and nothing leaves this Mac.
    func rememberInsertion(_ text: String, in element: AXUIElement?) {
        checkCorrections()
        correctionCheck?.cancel()
        guard let element else { lastInsertion = nil; return }
        Task { @MainActor [weak self] in
            // Let the paste land before reading the field.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, let value = FocusContext.value(of: element) else { return }
            self.lastInsertion = (element, text, value)
            self.correctionCheck = Task { @MainActor [weak self] in
                for delay in [15.0, 30.0] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self, self.lastInsertion != nil else { return }
                    self.checkCorrections()
                }
            }
        }
    }

    /// Compares the field with its text after the last paste; a corrected word that looks like a name
    /// or a term becomes a suggestion on the Flow Bar (one per dictation).
    public func checkCorrections() {
        guard let last = lastInsertion, session == nil, pendingSuggestion == nil,
              let now = FocusContext.value(of: last.element), now != last.value else { return }
        let known = Set(((try? store.dictionary()) ?? []).map { $0.replacement.lowercased() })
        guard let suggestion = CorrectionDetector.suggestions(before: last.value, after: now, inserted: last.text)
            .first(where: { !known.contains($0.spelling.lowercased()) && !dismissedSuggestions.contains($0.key) }) else { return }
        lastInsertion = nil
        correctionCheck?.cancel()
        pendingSuggestion = suggestion
        status.message = "Add “\(suggestion.spelling)” to your dictionary?"
        status.notice = DictationStatus.Notice(kind: .suggestion, message: "Add “\(suggestion.spelling)” to your dictionary?")
        log.notice("dictionary suggestion shown")
    }

    /// Add on the suggestion: the spelling goes in the dictionary, heard as what Murmur wrote.
    public func acceptSuggestion() {
        guard let suggestion = pendingSuggestion else { return }
        pendingSuggestion = nil
        try? store.save(DictionaryRecord(term: suggestion.heard, replacement: suggestion.spelling, source: .suggested))
        clearMessage()
    }

    public func dismissSuggestion() {
        if let suggestion = pendingSuggestion { dismissedSuggestions.insert(suggestion.key) }
        pendingSuggestion = nil
        clearMessage()
    }

    /// S4: the style chosen for the category of the app (or web page) that had focus.
    func style(for focus: FocusSnapshot) -> WritingStyle {
        let category = AppCategory.of(bundleId: focus.bundleId, url: FocusContext.webAddress(of: focus.element))
        return WritingStyle(rawValue: settings.styles[category.rawValue] ?? "") ?? .formal
    }

    static func message(for failure: InsertionFailure, app: String?) -> String {
        switch failure {
        case .focusChanged: "Focus moved away from \(app ?? "the app") while you spoke, so nothing was pasted. The text is on the clipboard."
        case .secureField: "That looks like a password field, so nothing was pasted. The text is on the clipboard."
        case .noTextBox: "No text box had focus. Click one and press ⌃⌘V to paste the last transcript."
        case .pasteNotSent: "Couldn't send the paste keystroke (check Accessibility). The text is on the clipboard."
        }
    }

    func endSession(_ event: DictationEvent) {
        state.send(event)
        session = nil
        processing = nil
        scheduleIdleUnload()
        if status.phase != .error { status.phase = .idle }
    }

    func fail(_ message: String, kind: DictationStatus.NoticeKind = .info) {
        status.phase = .error
        status.message = message
        status.notice = DictationStatus.Notice(kind: kind, message: message)
        if settings.soundsEnabled { sounds?.play(.error) }
    }

    /// Esc: stop recording or processing and insert nothing; the History entry stays (D3). The audio is
    /// kept in memory so Undo on the Flow Bar can still insert it.
    func cancel() {
        guard let current = session else { return }
        var samples: [Float] = []
        var recordId: String?
        if recorder.isRunning {
            samples = recorder.stop()
            let id = UUID().uuidString
            recordId = id
            var audioPath: String?
            if settings.keepAudio, !settings.neverStore, !samples.isEmpty {
                let url = MurmurPaths.audio.appendingPathComponent("\(id).wav")
                audioPath = url.path
                let copy = samples
                Task.detached(priority: .utility) { try? WAV.write(copy, to: url) }
            }
            _ = try? history.insert(DictationRecord(
                id: id, startedAt: current.startedAt, durationMs: Double(samples.count) / 16, appBundleId: current.focus.bundleId,
                appName: current.focus.appName, mode: current.mode.rawValue, engine: engineId ?? "-", cleanup: cleanupId,
                status: .cancelled, errorCode: "user", audioPath: audioPath
            ))
        } else {
            // Processing: keep the audio for Undo even if Esc came before the History row was written.
            if let id = current.recordId {
                recordId = id
                _ = try? history.update(id: id) { $0.status = .cancelled; $0.errorCode = "user" }
            }
            samples = processingSamples ?? []
        }
        lastCancelled = samples.isEmpty ? nil : (current, samples, recordId)
        processing?.cancel()
        processing = nil
        session = nil
        state.send(.cancel)
        state.send(.dismiss)
        recognizer.reset()
        status.phase = .idle
        status.message = "Cancelled. Nothing was inserted; the dictation is in History."
        status.notice = DictationStatus.Notice(kind: .cancelled, message: "Cancelled")
    }

    /// Undo on the cancelled notice: insert the cancelled dictation after all.
    public func undoCancel() {
        guard let cancelled = lastCancelled else { return }
        lastCancelled = nil
        if let id = cancelled.recordId { _ = try? history.update(id: id) { $0.status = .cancelled; $0.errorCode = "undone" } }
        reprocess(cancelled.samples, like: cancelled.session)
    }

    /// Retry on the transcription-error notice.
    public func retryFailed() {
        guard let failed = lastFailed else { return }
        lastFailed = nil
        _ = try? history.update(id: failed.recordId) { $0.errorCode = "retried" }
        reprocess(failed.samples, like: failed.session)
    }

    /// Runs saved audio through the pipeline again, into the field that had focus originally.
    func reprocess(_ samples: [Float], like original: Session) {
        if case .error = state.state { state.send(.dismiss) }
        guard state.state == .idle, state.send(.start(original.mode)) != nil else { return }
        let session = Session(mode: original.mode, keyDownAt: Clock.now(), startedAt: Date(), focus: original.focus)
        self.session = session
        reloadIfUnloaded()
        status.notice = nil
        status.message = nil
        status.command = original.mode == .command
        status.phase = .processing
        processingSamples = samples
        processing = Task { [weak self] in
            await self?.process(session, samples: samples, releasedAt: Clock.now(), flushMs: 0, firstAudioMs: nil)
        }
    }

    /// Self-test: runs `samples` through the whole pipeline as a hold-to-talk dictation into whatever has
    /// focus now. False if a dictation is already running or the models are not loaded.
    public func dictateForTest(_ samples: [Float]) -> Bool {
        guard engine != nil, session == nil else { return false }
        reprocess(samples, like: Session(mode: .hold, keyDownAt: Clock.now(), startedAt: Date(), focus: FocusContext.snapshot()))
        return session != nil
    }

    /// Self-test: runs `samples` as a Command Mode instruction against whatever has focus now.
    public func commandForTest(_ samples: [Float]) -> Bool {
        guard engine != nil, session == nil else { return false }
        reprocess(samples, like: Session(mode: .command, keyDownAt: Clock.now(), startedAt: Date(), focus: FocusContext.snapshot()))
        return session != nil
    }

    /// True while a dictation is recording or being processed.
    public var isBusy: Bool { session != nil }

    /// Drops whatever is recording without a trace (the automated focus test uses this).
    public func discardCurrent() {
        discard()
        recognizer.reset()
    }

    public var isRecording: Bool { recorder.isRunning }

    // MARK: Retry and Recover from History (A4)

    /// Re-runs a saved dictation from its audio: transcribe, clean up, and update the row. Nothing is
    /// pasted; the row's text can then be copied. Used for failed and interrupted rows.
    public func retry(recordId: String) async -> Bool {
        guard let engine, let record = try? store.record(id: recordId), let path = record.audioPath,
              let samples = try? WAV.read(URL(fileURLWithPath: path)), !samples.isEmpty else { return false }
        do {
            reloadIfUnloaded()
            await engineReload?.value
            let raw = try await engine.transcribe(samples, options: TranscribeOptions(
                language: settings.engineLanguage, vocabulary: vocabulary, aliases: aliases)).trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try? store.update(id: recordId) { $0.rawText = raw; $0.status = .transcribed; $0.errorCode = "retried" }
            guard !raw.isEmpty else { return false }
            let provider = settings.transformsEnabled ? cleanupProvider : nil
            let outcome = await CleanupRunner(rules: rules, provider: provider).run(raw, request: currentCleanupRequest)
            _ = try? store.update(id: recordId) { $0.cleanText = outcome.text; $0.status = .inserted; $0.errorCode = "recovered" }
            return true
        } catch {
            _ = try? store.update(id: recordId) { $0.errorCode = String(describing: error) }
            return false
        }
    }

    /// D9 retry: rebuild the audio engine and check the microphone starts.
    public func retryMicrophone() {
        recorder.forceRebuild()
        if startMicTest() {
            stopMicTest()
            clearMessage()
            log.notice("microphone recovered")
        } else {
            fail("The microphone is still unavailable (\(recorder.deviceName)). Pick another in Settings › General, or Retry.", kind: .micError)
        }
    }

    // MARK: Microphone test (onboarding, Settings)

    public private(set) var micTestRunning = false

    /// Starts the microphone for the level meter only. Shortcuts are ignored meanwhile (D5).
    public func startMicTest() -> Bool {
        guard !micTestRunning, state.state == .idle else { return micTestRunning }
        do {
            try recorder.start()
            micTestRunning = true
            return true
        } catch {
            status.message = "Microphone unavailable: \(error)"
            return false
        }
    }

    public func stopMicTest() {
        guard micTestRunning else { return }
        _ = recorder.stop()
        micTestRunning = false
    }

    public func selectMicrophone(uid: String?) {
        let wasTesting = micTestRunning
        if wasTesting { stopMicTest() }
        settings.microphoneUID = uid
        recorder.setDevice(uid: uid)
        if wasTesting { _ = startMicTest() }
    }

    /// The Flow Bar's stop button.
    public func stopHandsFree() {
        recognizer.reset()
        finish()
    }

    /// The Flow Bar's X button and Esc.
    public func cancelCurrent() {
        cancel()
    }

    /// An informational notice on the Flow Bar and in the menu (permissions lost, and so on).
    /// The longest a dictation waits for the cleanup model to finish reloading after an idle unload.
    static let cleanupReloadWait: Duration = .seconds(3)

    /// Recordings at least this long that hold no speech show the no-audio card.
    static let noAudioMinimumMs: Double = 1000

    /// A real recording with no speech in it (the speech gate found none, or it transcribed to nothing)
    /// gets the "We couldn't hear you" card with Switch microphone and Test mic; a short tap stays quiet.
    /// Nothing is inserted either way.
    func noAudio(after audioMs: Double) {
        guard audioMs >= Self.noAudioMinimumMs else { return }
        notice("We couldn't hear you. No speech from \(recorder.deviceName).", kind: .noAudio)
    }

    public func notice(_ message: String, kind: DictationStatus.NoticeKind = .info) {
        status.message = message
        status.notice = DictationStatus.Notice(kind: kind, message: message)
        log.notice("notice shown")
    }

    public func clearMessage() {
        status.message = nil
        status.notice = nil
        if status.phase == .error { status.phase = engine == nil ? .loading : .idle }
    }

    // MARK: Paste and copy last transcript (I7)

    /// ⌃⌘V: paste the newest transcript into the focused field. Cancels a dictation still processing.
    public func pasteLast() {
        if processing != nil { cancel() }
        guard let text = (try? history.lastWithText())?.bestText ?? status.lastTranscript else {
            status.message = "Nothing to paste yet."
            return
        }
        let focus = FocusContext.snapshot()
        let spaced = SmartSpacing.adjust(text, before: SmartSpacing.characterBeforeCursor(of: focus.element))
        Task {
            let typeInstead = focus.bundleId.map(settings.typingApps.contains) ?? false
            let result = await insertion.insert(spaced, expected: focus, current: FocusContext.snapshot(), typeInstead: typeInstead)
            if case .failed(let failure) = result { fail(Self.message(for: failure, app: focus.appName)) }
        }
    }

    /// ⌃⌘C: put the newest transcript on the clipboard as plain text.
    public func copyLast() {
        guard let text = (try? history.lastWithText())?.bestText ?? status.lastTranscript else {
            status.message = "Nothing to copy yet."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Housekeeping

    /// Audio is kept for Retry and Recover for 14 days (A4), then deleted.
    func purgeOldAudio() {
        let dir = MurmurPaths.audio
        Task.detached(priority: .background) {
            let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if date < cutoff { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    public var microphoneName: String { recorder.deviceName }
    public var engineDescription: String { engineId ?? "loading…" }
    public var cleanupDescription: String { cleanupProvider?.id ?? (cleanupId == nil ? "loading…" : "rules only") }
}

/// Records when the paste keystroke went out, from the insertion callback.
final class PasteClock: @unchecked Sendable {
    private let lock = NSLock()
    private var at: UInt64?
    func mark() { lock.withLock { at = Clock.now() } }
    var value: UInt64? { lock.withLock { at } }
}
