import AppKit
import AVFoundation
import Combine
import MurmurKit
import ServiceManagement
import SwiftUI

/// The Hub's pages (spec section 6): Home (History), Dictionary, Snippets, Style, and Settings split into
/// General, System, Experimental, and Data and Privacy.
enum HubPage: String, CaseIterable, Identifiable, Hashable {
    case home, dictionary, snippets, style, general, system, experimental, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .style: "Style"
        case .general: "General"
        case .system: "System"
        case .experimental: "Experimental"
        case .privacy: "Data and Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .home: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "textformat"
        case .general: "gearshape"
        case .system: "macwindow"
        case .experimental: "flask"
        case .privacy: "lock.shield"
        }
    }

    static let main: [HubPage] = [.home, .dictionary, .snippets, .style]
    static let settings: [HubPage] = [.general, .system, .experimental, .privacy]
}

/// Shared state for the Hub and onboarding: the controller, History, and the live mic level.
@MainActor
@Observable
final class HubModel {
    let controller: DictationController
    let store: HistoryStore
    let settings = AppSettings.shared
    var page: HubPage = .home
    var backStack: [HubPage] = []
    var forwardStack: [HubPage] = []
    /// Latest microphone level, 0…1, for the level meters.
    var micLevel: Double = 0

    init(controller: DictationController, store: HistoryStore) {
        self.controller = controller
        self.store = store
    }

    func go(_ page: HubPage) {
        guard page != self.page else { return }
        backStack.append(self.page)
        forwardStack.removeAll()
        self.page = page
    }

    func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(page)
        page = previous
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(page)
        page = next
    }

    /// Option+Up and Option+Down move through the sidebar (spec keyboard use).
    func step(_ delta: Int) {
        let all = HubPage.main + HubPage.settings
        guard let i = all.firstIndex(of: page) else { return }
        go(all[(i + delta + all.count) % all.count])
    }

    func push(level dbfs: Float) {
        micLevel = min(1, max(0, (Double(dbfs) + 60) / 50))
    }
}

struct HubView: View {
    @Bindable var model: HubModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.page }, set: { if let p = $0 { model.go(p) } })) {
                ForEach(HubPage.main) { page in Label(page.title, systemImage: page.symbol).tag(page) }
                Section("Settings") {
                    ForEach(HubPage.settings) { page in Label(page.title, systemImage: page.symbol).tag(page) }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch model.page {
                case .home: HomePage(model: model)
                case .dictionary: DictionaryView(store: model.store)
                case .snippets: SnippetsView(store: model.store)
                case .style: StylePage(model: model)
                case .general: GeneralPage(model: model)
                case .system: SystemPage(model: model)
                case .experimental: ExperimentalPage()
                case .privacy: PrivacyPage(model: model)
                }
            }
            .navigationTitle(model.page.title)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: model.page)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.back() } label: { Image(systemName: "chevron.left") }
                    .disabled(model.backStack.isEmpty).keyboardShortcut("[", modifiers: .command).help("Back (⌘[)")
                Button { model.forward() } label: { Image(systemName: "chevron.right") }
                    .disabled(model.forwardStack.isEmpty).keyboardShortcut("]", modifiers: .command).help("Forward (⌘])")
            }
        }
        .background {
            // Option+Up / Option+Down between pages.
            Button("") { model.step(-1) }.keyboardShortcut(.upArrow, modifiers: .option).opacity(0).frame(width: 0, height: 0)
            Button("") { model.step(1) }.keyboardShortcut(.downArrow, modifiers: .option).opacity(0).frame(width: 0, height: 0)
        }
    }
}

// MARK: - Home (History, A4)

struct HomePage: View {
    let model: HubModel
    @State private var records: [DictationRecord] = []
    @State private var search = ""
    @State private var selection: DictationRecord.ID?
    @State private var player: AVAudioPlayer?
    @State private var busy: Set<String> = []
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search History", text: $search).textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            List(selection: $selection) {
                ForEach(records) { r in
                    HistoryRow(record: r, playing: false, busy: busy.contains(r.id),
                               play: { play(r) }, copy: { copy(r.bestText) }, retry: canRetry(r) ? { retry(r) } : nil)
                        .tag(r.id)
                        .contextMenu { rowMenu(r) }
                }
            }
            .focused($listFocused)
            .onKeyPress(.return) { copy(selected?.bestText); return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "jk")) { press in
                move(press.characters == "j" ? 1 : -1)
                return .handled
            }
            Divider()
            Text("\(records.count) dictations · ↑↓ or j k to move · Return copies").font(.caption).foregroundStyle(.secondary).padding(6)
        }
        .onChange(of: search) { reload() }
        .onAppear { reload(); listFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    var selected: DictationRecord? { records.first { $0.id == selection } }

    func reload() { records = (try? model.store.recent(limit: 1000, search: search)) ?? [] }

    func move(_ delta: Int) {
        guard !records.isEmpty else { return }
        let i = records.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : records.count)
        selection = records[max(0, min(records.count - 1, i + delta))].id
    }

    func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func audioURL(_ r: DictationRecord) -> URL? {
        guard let path = r.audioPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Retry or Recover needs audio under 14 days old; failed rows must also be 5 s or longer (A4).
    func canRetry(_ r: DictationRecord) -> Bool {
        guard audioURL(r) != nil, Date().timeIntervalSince(r.startedAt) < 14 * 86_400 else { return false }
        switch r.status {
        case .recorded, .transcribed: return true
        case .transcriptionFailed, .pasteFailed, .noTextBox, .cancelled: return r.durationMs >= 5_000
        case .inserted: return false
        }
    }

    func play(_ r: DictationRecord) {
        guard let url = audioURL(r) else { return }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func retry(_ r: DictationRecord) {
        busy.insert(r.id)
        Task {
            _ = await model.controller.retry(recordId: r.id)
            busy.remove(r.id)
        }
    }

    @ViewBuilder func rowMenu(_ r: DictationRecord) -> some View {
        Button("Copy") { copy(r.bestText) }
        if audioURL(r) != nil { Button("Play audio") { play(r) } }
        if canRetry(r) { Button(r.status == .recorded || r.status == .transcribed ? "Recover" : "Retry") { retry(r) } }
        if r.cleanText != nil, r.rawText != nil, r.cleanText != r.rawText {
            Divider()
            Button(r.useRaw ? "Redo AI edit (use cleaned text)" : "Undo AI edit (use original words)") {
                _ = try? model.store.update(id: r.id) { $0.useRaw.toggle() }
            }
            Button("Copy original words") { copy(r.rawText) }
        }
    }
}

struct HistoryRow: View {
    let record: DictationRecord
    let playing: Bool
    let busy: Bool
    let play: () -> Void
    let copy: () -> Void
    let retry: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.startedAt, format: .dateTime.hour().minute()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text(record.appName ?? "").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.bestText ?? statusLabel).foregroundStyle(record.bestText == nil ? .secondary : .primary).lineLimit(3)
                if record.status != .inserted || record.useRaw {
                    Text(record.useRaw ? "Original words (AI edit undone)" : statusLabel).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if hovering {
                if record.audioPath != nil { Button(action: play) { Image(systemName: "play.fill") }.buttonStyle(.borderless).help("Play audio") }
                Button(action: copy) { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy")
                if let retry { Button(action: retry) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Retry") }
            }
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
    }

    var statusLabel: String {
        switch record.status {
        case .recorded: "Interrupted before transcription"
        case .transcribed: "Not cleaned up (interrupted)"
        case .inserted: "Inserted"
        case .cancelled: "Cancelled"
        case .transcriptionFailed: "Transcription failed"
        case .pasteFailed: "Not pasted: the text was on the clipboard"
        case .noTextBox: "No text box"
        }
    }
}

// MARK: - Style

struct StylePage: View {
    let model: HubModel
    @State private var level = AppSettings.shared.cleanupLevel
    @State private var category = "personal"
    @State private var styles = AppSettings.shared.styles
    @State private var smartFormatting = AppSettings.shared.smartFormatting

    static let categories = [("personal", "Personal messages"), ("work", "Work messages"), ("email", "Email"), ("other", "Other")]
    static let styleOptions: [(id: String, name: String, example: String, categories: Set<String>)] = [
        ("formal", "Formal.", "Hey, are you free for lunch tomorrow? Let's do 12 if that works.", ["personal", "work", "email", "other"]),
        ("casual", "Casual", "Hey are you free for lunch tomorrow? Let's do 12 if that works", ["personal", "work", "email", "other"]),
        ("veryCasual", "very casual", "hey are you free for lunch tomorrow? let's do 12 if that works", ["personal"]),
        ("excited", "Excited!", "Hey, are you free for lunch tomorrow? Let's do 12 if that works!", ["work", "email", "other"]),
    ]

    var body: some View {
        Form {
            Section("Style by app") {
                Picker("Category", selection: $category) {
                    ForEach(Self.categories, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                HStack(alignment: .top) {
                    ForEach(Self.styleOptions.filter { $0.categories.contains(category) }, id: \.id) { option in
                        Card(title: option.name, example: option.example, selected: (styles[category] ?? "formal") == option.id) {
                            styles[category] = option.id
                            model.settings.styles = styles
                        }
                    }
                }
                Text("Murmur picks the category from the app you dictate into; web apps by their address. AI assistants and terminals count as Other. English only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Auto Cleanup") {
                HStack(alignment: .top) {
                    Card(title: "None", example: "um so I think we should uh move the launch to Friday", selected: level == "none") { setLevel("none") }
                    Card(title: "Light", example: "I think we should move the launch to Friday.", selected: level == "light") { setLevel("light") }
                    Card(title: "Medium", example: "Let's move the launch to Friday.", selected: level == "medium") { setLevel("medium") }
                }
                Toggle("Smart Formatting (numbered lists, paragraphs)", isOn: $smartFormatting)
                    .onChange(of: smartFormatting) { model.settings.smartFormatting = smartFormatting }
            }
        }
        .formStyle(.grouped)
    }

    func setLevel(_ value: String) {
        level = value
        model.settings.cleanupLevel = value
    }
}

struct Card: View {
    let title: String
    let example: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(example).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Settings pages

struct GeneralPage: View {
    let model: HubModel
    @State private var engine = AppSettings.shared.engine
    @State private var cleanup = AppSettings.shared.cleanupProvider

    var body: some View {
        Form {
            Section("Shortcuts") { ShortcutSettings(model: model) }
            Section("Microphone") { MicrophoneSettings(model: model) }
            Section("Models") {
                Picker("Speech engine", selection: $engine) {
                    ForEach(EngineCatalog.ids.filter { SettingsView.engineNames[$0] != nil }, id: \.self) { Text(SettingsView.engineNames[$0] ?? $0).tag($0) }
                }
                .onChange(of: engine) { model.settings.engine = engine }
                Picker("Cleanup model", selection: $cleanup) {
                    ForEach(SettingsView.cleanupNames.keys.sorted(), id: \.self) { Text(SettingsView.cleanupNames[$0] ?? $0).tag($0) }
                }
                .onChange(of: cleanup) { model.settings.cleanupProvider = cleanup }
            }
            Section("Languages") { LanguagePicker(settings: model.settings) }
            Section("Permissions") { PermissionsSummary() }
        }
        .formStyle(.grouped)
    }
}

struct SystemPage: View {
    let model: HubModel
    @State private var showFlowBar = AppSettings.shared.showFlowBar
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var sounds = AppSettings.shared.soundsEnabled
    @State private var debug = AppSettings.shared.debugMenu
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show Flow Bar at all times", isOn: $showFlowBar).onChange(of: showFlowBar) { model.settings.showFlowBar = showFlowBar }
                Toggle("Launch Murmur at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Toggle("Show in Dock", isOn: $showInDock).onChange(of: showInDock) { model.settings.showInDock = showInDock }
                Toggle("Sounds", isOn: $sounds).onChange(of: sounds) { model.settings.soundsEnabled = sounds }
                Toggle("Debug menu", isOn: $debug).onChange(of: debug) { model.settings.debugMenu = debug }
            }
        }
        .formStyle(.grouped)
    }

    /// A7: register the app as a login item through ServiceManagement.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve Murmur in System Settings › General › Login Items." : nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct ExperimentalPage: View {
    var body: some View {
        Form {
            Section {
                Toggle("Command Mode", isOn: .constant(false)).disabled(true)
                Text("Hold Fn+Control and speak an instruction to rewrite the selection or draft at the cursor. Not available in this build yet.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Press Enter after “press enter”", isOn: .constant(false)).disabled(true)
                Text("Ending a dictation with “press enter” presses Return after the paste. Not available in this build yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct PrivacyPage: View {
    let model: HubModel
    @State private var keepAudio = AppSettings.shared.keepAudio
    @State private var neverStore = AppSettings.shared.neverStore
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("History") {
                Toggle("Keep audio for 14 days (for Play and Retry)", isOn: $keepAudio).onChange(of: keepAudio) { model.settings.keepAudio = keepAudio }
                Toggle("Never store anything", isOn: $neverStore).onChange(of: neverStore) { model.settings.neverStore = neverStore }
                Text("On: no History, no audio, nothing written to disk. Paste last still works until Murmur quits.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Delete all History and audio…", role: .destructive) { confirmDelete = true }
            }
            Section("Cloud (optional)") { CloudKeys() }
            Section {
                Text("Audio and text stay on this Mac unless you choose a Groq or OpenRouter option. Murmur has no analytics, and its logs hold timings, never your words.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all History and audio?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) {
                try? model.store.deleteAll()
                try? FileManager.default.removeItem(at: MurmurPaths.audio)
            }
        } message: { Text("This cannot be undone. Your dictionary and snippets stay.") }
    }
}

/// Groq and OpenRouter keys, stored in the Keychain.
struct CloudKeys: View {
    @State private var groq = ""
    @State private var groqSaved = Keychain.get("groq") != nil
    @State private var openRouter = ""
    @State private var openRouterSaved = Keychain.get("openrouter") != nil

    var body: some View {
        keyRow("Groq API key", text: $groq, saved: $groqSaved, account: "groq")
        keyRow("OpenRouter API key", text: $openRouter, saved: $openRouterSaved, account: "openrouter")
    }

    func keyRow(_ label: String, text: Binding<String>, saved: Binding<Bool>, account: String) -> some View {
        HStack {
            SecureField(saved.wrappedValue ? "\(label) saved in Keychain" : label, text: text)
            Button("Save") {
                Keychain.set(text.wrappedValue, for: account)
                saved.wrappedValue = !text.wrappedValue.isEmpty
                text.wrappedValue = ""
            }
            .disabled(text.wrappedValue.isEmpty)
            if saved.wrappedValue { Button("Remove") { Keychain.set(nil, for: account); saved.wrappedValue = false } }
        }
    }
}

/// Permission status with Grant buttons that open the right System Settings pane (A3).
struct PermissionsSummary: View {
    @State private var snapshot = PermissionSnapshot.current()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Microphone", snapshot.microphone, pane: "Privacy_Microphone") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
            row("Accessibility", snapshot.accessibility, pane: "Privacy_Accessibility") { Permissions.promptAccessibility() }
            row("Input Monitoring", snapshot.inputMonitoring, pane: "Privacy_ListenEvent") { Permissions.requestInputMonitoring() }
        }
        .onReceive(timer) { _ in snapshot = .current() }
    }

    func row(_ name: String, _ ok: Bool, pane: String, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? .green : .orange)
            Text(name)
            Spacer()
            if !ok {
                Button("Grant") {
                    request()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }
}

struct PermissionSnapshot: Equatable {
    var microphone: Bool
    var accessibility: Bool
    var inputMonitoring: Bool

    var allGranted: Bool { microphone && accessibility && inputMonitoring }

    static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: Permissions.accessibility,
            inputMonitoring: Permissions.inputMonitoring)
    }
}

// MARK: - Shortcuts (D8)

struct ShortcutSettings: View {
    let model: HubModel
    @State private var config: HotkeyConfiguration = DictationController.shortcutConfiguration(.shared)

    var body: some View {
        ShortcutRow(title: "Push to talk", shortcut: config.pushToTalk, model: model) { new in
            config.pushToTalk = new
            model.controller.setShortcuts(config)
        }
        ShortcutRow(title: "Hands-free", shortcut: config.handsFree, model: model) { new in
            config.handsFree = new
            model.controller.setShortcuts(config)
        }
        HStack {
            Text("Double-tap push-to-talk also starts hands-free. Esc cancels.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Reset to defaults") {
                model.controller.setShortcuts(nil)
                config = DictationController.shortcutConfiguration(model.settings)
            }
        }
        if config.pushToTalk == .modifiers([.fn]) || config.handsFree == .key(keyCode: 49, modifiers: [.fn]), Permissions.fnUsageType != 0 {
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.blue)
                Text("The Globe key may also open emoji or dictation. Set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing.").font(.caption)
                Button("Open") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
            }
        }
        if Permissions.secureEventInput {
            Label("Another app has Secure Keyboard Entry on, which blocks shortcuts until it is turned off.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

/// Records a new shortcut: modifiers alone save when released, a key combination when its key is
/// released, a mouse button when pressed (D8).
struct ShortcutRow: View {
    let title: String
    let shortcut: Shortcut
    let model: HubModel
    let save: (Shortcut) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var peak: Set<ModifierKey> = []
    @State private var pendingKey: (Int, Set<ModifierKey>)?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "Press the new shortcut…" : shortcut.displayName) { recording ? stop() : start() }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
            if recording { Button("Cancel") { stop() } }
        }
        .onDisappear { stop() }
    }

    func start() {
        recording = true
        peak = []
        pendingKey = nil
        model.controller.shortcutsPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp, .otherMouseDown]) { event in
            handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        model.controller.shortcutsPaused = false
    }

    func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        var set: Set<ModifierKey> = []
        if flags.contains(.function) { set.insert(.fn) }
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.command) { set.insert(.command) }
        if flags.contains(.shift) { set.insert(.shift) }
        return set
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .otherMouseDown:
            finish(.mouse(button: event.buttonNumber))
        case .flagsChanged:
            if event.keyCode == 57 { finish(.capsLock); return }
            let held = modifiers(event.modifierFlags)
            if held.count > peak.count { peak = held }
            if held.isEmpty && !peak.isEmpty && pendingKey == nil { finish(.modifiers(peak)) }
        case .keyDown:
            if event.keyCode == 53 && modifiers(event.modifierFlags).isEmpty { stop(); return }
            pendingKey = (Int(event.keyCode), modifiers(event.modifierFlags))
        case .keyUp:
            if let pendingKey, pendingKey.0 == Int(event.keyCode) { finish(.key(keyCode: pendingKey.0, modifiers: pendingKey.1)) }
        default:
            break
        }
    }

    func finish(_ new: Shortcut) {
        stop()
        save(new)
    }
}

// MARK: - Microphone (D9)

struct MicrophoneSettings: View {
    let model: HubModel
    @State private var devices = AudioDevices.inputs()
    @State private var selected = AppSettings.shared.microphoneUID ?? ""
    @State private var testing = false

    var body: some View {
        Picker("Input", selection: $selected) {
            Text("System default").tag("")
            ForEach(devices) { Text($0.name + ($0.isDefault ? " (default)" : "")).tag($0.uid) }
        }
        .onChange(of: selected) { model.controller.selectMicrophone(uid: selected.isEmpty ? nil : selected) }
        HStack {
            Button(testing ? "Stop test" : "Test microphone") { toggleTest() }
            LevelMeter(level: testing ? model.micLevel : 0)
        }
        .onDisappear { if testing { toggleTest() } }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)) { _ in devices = AudioDevices.inputs() }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)) { _ in devices = AudioDevices.inputs() }
    }

    func toggleTest() {
        if testing { model.controller.stopMicTest(); testing = false } else { testing = model.controller.startMicTest() }
    }
}

struct LevelMeter: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Double(i) / 16 < level ? (i > 12 ? Color.orange : Color.green) : Color.secondary.opacity(0.2))
                    .frame(width: 6, height: 14)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
