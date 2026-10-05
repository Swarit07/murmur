import ArgumentParser
import Audio
import Cleanup
import Context
import Core
import Foundation
import Hotkey
import Insertion
import Pipeline
import SpeechEngines

@main
struct MurmurCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "murmur-cli",
        abstract: "Murmur Milestone 0 spike: record, transcribe, clean up and paste from the terminal.",
        subcommands: [Doctor.self, Record.self, Transcribe.self, Clean.self, Dictate.self],
        defaultSubcommand: Doctor.self
    )
}

// MARK: - doctor

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check permissions, keys and settings, and say what is missing.")

    func run() async throws {
        let mic = MicrophonePermission.status
        let micText: String = switch mic {
        case .authorized: "granted"
        case .notDetermined: "not asked yet (the first `record` will ask)"
        case .denied: "DENIED. System Settings > Privacy & Security > Microphone"
        case .restricted: "restricted"
        @unknown default: "unknown"
        }
        print("Responsible app      \(ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "unknown") (permissions are granted to the terminal app that runs this tool)")
        print("Microphone           \(micText)")
        print("Default input        \(AudioRecorder().deviceName)")
        print("Accessibility        \(Permissions.accessibility ? "granted" : "MISSING. Needed to paste. System Settings > Privacy & Security > Accessibility")")
        print("Input Monitoring     \(Permissions.inputMonitoring ? "granted" : "MISSING. Needed for the hold key in `dictate`. System Settings > Privacy & Security > Input Monitoring")")
        print("Secure input         \(Permissions.secureEventInput ? "ON. Another app holds Secure Keyboard Entry; shortcuts and paste are blocked" : "off")")
        let fn = Permissions.fnUsageType
        let fnText: String = switch fn {
        case 0: "Do Nothing (good for Fn push-to-talk)"
        case 1: "Change Input Source (conflicts with Fn push-to-talk)"
        case 2: "Show Emoji & Symbols (conflicts with Fn push-to-talk)"
        case 3: "Start Dictation (conflicts with Fn push-to-talk)"
        default: "system default (may open emoji or dictation; set Keyboard > Press Globe key to: Do Nothing to use --key fn)"
        }
        print("Globe key            \(fnText)")
        print("GROQ_API_KEY         \(ProcessInfo.processInfo.environment["GROQ_API_KEY"]?.isEmpty == false ? "set" : "not set (cloud engine and hosted cleanup are skipped)")")
        print("MLX in this build    \(CleanupCatalog.mlxAvailable ? "yes" : "no (built with MURMUR_NO_MLX=1)")")
        print("Engines              \(EngineCatalog.ids.joined(separator: ", "))")
        print("Cleanup providers    \(CleanupCatalog.ids.joined(separator: ", "))")
    }
}

// MARK: - record

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Record a 16 kHz mono WAV. Press Enter to start and Enter to stop.")

    @Option(name: .shortAndLong, help: "Output file.")
    var out: String = "recording.wav"

    @Option(help: "Stop automatically after this many seconds instead of waiting for Enter.")
    var seconds: Double?

    @Option(help: "Input device: part of its name (see the Microphone menu in the app), or 'default'.")
    var device: String?

    func run() async throws {
        guard await MicrophonePermission.ensure() else {
            throw ValidationError("Microphone access is denied. Allow your terminal app in System Settings > Privacy & Security > Microphone, then run this again.")
        }
        let recorder = AudioRecorder()
        if let device, device != "default" {
            guard let match = AudioDevices.inputs().first(where: { $0.name.localizedCaseInsensitiveContains(device) }) else {
                throw ValidationError("No input device matches \(device). Inputs: \(AudioDevices.inputs().map(\.name).joined(separator: ", "))")
            }
            recorder.setDevice(uid: match.uid)
        }
        recorder.prepare()
        print("Input: \(recorder.deviceName)")
        if seconds == nil {
            print("Press Enter to start recording.")
            await Terminal.waitForEnter()
        }
        try recorder.start()
        if let seconds {
            print("● Recording for \(seconds) s…")
            try await Task.sleep(for: .seconds(seconds))
        } else {
            print("● Recording. Press Enter to stop.")
            await Terminal.waitForEnter()
        }
        let samples = recorder.stop()
        let url = URL(fileURLWithPath: out)
        try WAV.write(samples, to: url)
        let duration = Double(samples.count) / AudioFormat.sampleRate
        print(String(format: "Saved %@ · %.2f s · peak %.1f dBFS · first audio after %@", url.path, duration,
                     20 * log10(max(Levels.peak(samples), 1e-6)), recorder.firstAudioMs.map(Format.ms) ?? "?"))
    }
}

// MARK: - transcribe

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Transcribe WAV files with one engine and report load time, memory and latency.")

    @Argument(help: "Audio files.")
    var files: [String]

    @Option(name: .shortAndLong, help: "Engine: \(EngineCatalog.ids.joined(separator: ", ")).")
    var engine: String = "parakeet-v3"

    @Option(help: "Comma-separated dictionary terms to bias the engine.")
    var vocab: String?

    @Option(help: "Language code, e.g. en. Default: automatic.")
    var language: String?

    @Option(help: "Transcribe each file this many times and report p50/p95.")
    var `repeat`: Int = 1

    func run() async throws {
        let engine = try EngineCatalog.make(engine)
        let before = ProcessMemory.snapshot()
        let loadStart = Clock.now()
        print("Loading \(engine.id)… (first run downloads the model)")
        try await engine.load()
        let loadMs = Clock.ms(since: loadStart)
        let after = ProcessMemory.snapshot()
        print("Loaded in \(Format.ms(loadMs)) · footprint \(after.map { Format.mb($0.footprint) } ?? "?") (was \(before.map { Format.mb($0.footprint) } ?? "?"))")
        let options = TranscribeOptions(language: language, vocabulary: vocab.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? [])
        var times: [Double] = []
        for file in files {
            let samples = try WAV.read(URL(fileURLWithPath: file))
            var text = ""
            for _ in 0..<max(1, `repeat`) {
                let start = Clock.now()
                text = try await engine.transcribe(samples, options: options)
                times.append(Clock.ms(since: start))
            }
            let audioMs = Double(samples.count) / AudioFormat.sampleRate * 1000
            print("\n\(file) · \(Format.ms(audioMs)) audio · \(Format.ms(times.last ?? 0))")
            print(text)
        }
        if times.count > 1 {
            print("\np50 \(Format.ms(Stats.percentile(times, 50)!)) · p95 \(Format.ms(Stats.percentile(times, 95)!)) over \(times.count) runs")
        }
        if let peak = ProcessMemory.snapshot()?.peakFootprint { print("Peak footprint \(Format.mb(peak))") }
    }
}

// MARK: - clean

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the cleanup stage on a line of text and show what each step did.")

    @Argument(help: "Transcript text.")
    var text: String

    @Option(name: .shortAndLong, help: "Cleanup provider: \(CleanupCatalog.ids.joined(separator: ", ")).")
    var cleanup: String = "rules"

    @Option(help: "none, light or medium.")
    var level: String = "light"

    @Option(help: "Time limit in milliseconds.")
    var limit: Int = 800

    func run() async throws {
        let provider = try CleanupCatalog.make(cleanup)
        if let provider {
            let start = Clock.now()
            print("Loading \(provider.id)…")
            try await provider.load()
            print("Loaded in \(Format.ms(Clock.ms(since: start)))")
        }
        let runner = CleanupRunner(provider: provider, timeLimit: .milliseconds(limit))
        let out = await runner.run(text, request: CleanupRequest(level: CleanupLevel(rawValue: level) ?? .light))
        print("rules  (\(Format.ms(out.rulesMs))): \(out.rulesText)")
        if let model = out.modelText { print("model  (\(out.llmMs.map(Format.ms) ?? "-")): \(model)") }
        if let fallback = out.fallback { print("fallback: \(fallback.rawValue)\(out.error.map { " (\($0))" } ?? "")") }
        for flag in out.flags { print("  guard: \(flag)") }
        print("final: \(out.text)")
    }
}

// MARK: - dictate

struct Dictate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Hold a key anywhere to dictate into the focused app. Release to transcribe, clean up and paste.",
        discussion: "Needs Microphone, Accessibility and Input Monitoring for your terminal app. Esc cancels. Ctrl+C quits."
    )

    @Option(name: .shortAndLong, help: "Engine: \(EngineCatalog.ids.joined(separator: ", ")).")
    var engine: String = "parakeet-v3"

    @Option(name: .shortAndLong, help: "Cleanup provider: \(CleanupCatalog.ids.joined(separator: ", ")).")
    var cleanup: String = "rules"

    @Option(help: "none, light or medium.")
    var level: String = "light"

    @Option(help: "Hold key: \(HoldKeyMonitor.Key.allCases.map(\.rawValue).joined(separator: ", ")).")
    var key: String = HoldKeyMonitor.Key.rightOption.rawValue

    @Option(help: "Comma-separated dictionary terms.")
    var vocab: String?

    @Flag(help: "Do not print transcript text, only timings.")
    var quiet = false

    func run() async throws {
        guard let holdKey = HoldKeyMonitor.Key(rawValue: key) else { throw ValidationError("Unknown key \(key).") }
        guard await MicrophonePermission.ensure() else {
            throw ValidationError("Microphone access is denied. Allow your terminal app in System Settings > Privacy & Security > Microphone.")
        }
        if !Permissions.accessibility {
            Permissions.promptAccessibility()
            throw ValidationError("Accessibility is not granted. Add your terminal app in System Settings > Privacy & Security > Accessibility, then quit and reopen the terminal.")
        }
        if !Permissions.inputMonitoring {
            Permissions.requestInputMonitoring()
            throw ValidationError("Input Monitoring is not granted. Add your terminal app in System Settings > Privacy & Security > Input Monitoring, then quit and reopen the terminal.")
        }

        let engine = try EngineCatalog.make(engine)
        print("Loading \(engine.id)…")
        var start = Clock.now()
        try await engine.load()
        print("  ready in \(Format.ms(Clock.ms(since: start)))")
        let provider = try CleanupCatalog.make(cleanup)
        if let provider {
            print("Loading \(provider.id)…")
            start = Clock.now()
            try await provider.load()
            print("  ready in \(Format.ms(Clock.ms(since: start)))")
        }
        let vocabulary = vocab.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
        let pipeline = DictationPipeline(
            engine: engine,
            cleanup: CleanupRunner(rules: RulesCleaner(dictionary: []), provider: provider),
            request: CleanupRequest(level: CleanupLevel(rawValue: level) ?? .light, vocabulary: vocabulary),
            transcribeOptions: TranscribeOptions(vocabulary: vocabulary)
        )
        let recorder = AudioRecorder()
        recorder.prepare()

        let (events, continuation) = AsyncStream<HoldKeyMonitor.Event>.makeStream()
        let monitor = HoldKeyMonitor(key: holdKey) { continuation.yield($0) }
        try monitor.start()
        defer { monitor.stop() }
        print("\nReady. Hold \(holdKey.label) in any text field, speak, release. Esc cancels. Ctrl+C quits.")
        print("Timings are appended to \(TimingLog.url.path) (no transcript text).\n")

        var expectedFocus: FocusSnapshot?
        let cleanupId = provider?.id ?? "rules"
        for await event in events {
            switch event {
            case .down:
                guard pipeline.begin() else {
                    print("· busy, key press ignored")
                    continue
                }
                expectedFocus = FocusContext.snapshot()
                do {
                    try recorder.start()
                    print("● recording → \(expectedFocus?.description ?? "?")")
                } catch {
                    pipeline.cancel()
                    print("✗ microphone: \(error)")
                }
            case .up(let releasedAt):
                guard recorder.isRunning else { continue }
                let samples = recorder.stop()
                let flush = Clock.ms(since: releasedAt)
                let firstAudio = recorder.firstAudioMs
                let focus = expectedFocus
                let quiet = quiet
                Task {
                    let result = await pipeline.finish(samples: samples, releasedAt: releasedAt, captureFlushMs: flush, expectedFocus: focus)
                    Self.report(result, audioMs: Double(samples.count) / 16, firstAudioMs: firstAudio, quiet: quiet)
                    TimingLog.append(TimingLog.Entry(
                        date: Date(), engine: engine.id, cleanup: cleanupId, status: result.status.rawValue,
                        audioMs: Double(samples.count) / 16, firstAudioMs: firstAudio,
                        fallback: result.cleanup?.fallback?.rawValue, timings: result.timings, app: focus?.bundleId
                    ))
                }
            case .escape:
                if recorder.isRunning {
                    _ = recorder.stop()
                    pipeline.cancel()
                    print("✗ cancelled; nothing inserted")
                } else if pipeline.state.state.isBusy {
                    pipeline.cancel()
                    print("✗ cancelled; nothing inserted")
                }
            }
        }
    }

    static func report(_ r: DictationResult, audioMs: Double, firstAudioMs: Double?, quiet: Bool) {
        var line = ""
        switch r.status {
        case .inserted: line = "✓ inserted"
        case .dropped: line = "· dropped (too short or no speech)"
        case .cancelled: line = "✗ cancelled"
        case .transcriptionFailed: line = "✗ transcription failed: \(r.error ?? "")"
        case .insertionFailed: line = "✗ not pasted (\(r.error ?? "")); the text is on the clipboard"
        }
        print(line)
        if !quiet, let raw = r.raw { print("  raw:   \(raw)") }
        if !quiet, let final = r.final, final != r.raw { print("  final: \(final)") }
        if let fallback = r.cleanup?.fallback { print("  cleanup fell back to rules: \(fallback.rawValue) \(r.cleanup?.flags.map(\.description).joined(separator: "; ") ?? "")") }
        print("  \(Format.ms(audioMs)) audio · first audio \(firstAudioMs.map(Format.ms) ?? "?") · \(r.timings.summary)\n")
    }
}

enum Terminal {
    /// Waits for Enter without blocking the cooperative thread pool.
    static func waitForEnter() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                _ = readLine()
                c.resume()
            }
        }
    }
}
