import AppKit
import AVFoundation
import Combine
import MurmurKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The Hub's pages (spec section 6): Home (History), Dictionary, Snippets, Style, and Settings split into
/// General, System, Experimental, and Data and Privacy.
public enum HubPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, dictionary, snippets, style, general, system, experimental, privacy
    public var id: String { rawValue }

    public var title: String {
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

    public static let main: [HubPage] = [.home, .dictionary, .snippets, .style]
    public static let settings: [HubPage] = [.general, .system, .experimental, .privacy]
}

/// Shared state for the Hub and onboarding: the controller, History, and the live mic level.
@MainActor
@Observable
public final class HubModel {
    let controller: DictationController
    let store: HistoryStore
    let settings = AppSettings.shared
    public var page: HubPage = .home
    var backStack: [HubPage] = []
    var forwardStack: [HubPage] = []
    /// The controller's latest status, for the sidebar's status card.
    public var status: DictationStatus?
    /// Text size setting (Hub only, §3.3).
    public var textScale: Double = TypeTokens.scaleDefault
    /// The search field above History, opened from the panel's top bar.
    var searchOpen = false
    /// The bell popover and the Help & setup sheet.
    var bellOpen = false
    var helpOpen = false
    /// System alerts for the bell: missing permissions and the last error.
    var alerts: [HubAlert] = []
    /// Re-runs onboarding (set by the app).
    public var onRunOnboarding: (() -> Void)?

    public init(controller: DictationController, store: HistoryStore) {
        self.controller = controller
        self.store = store
        status = controller.status
        textScale = settings.textSize == "large" ? TypeTokens.scaleLarge : TypeTokens.scaleDefault
        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] note in
            let key = note.object as? String
            MainActor.assumeIsolated {
                guard let self, key == "textSize" else { return }
                self.textScale = self.settings.textSize == "large" ? TypeTokens.scaleLarge : TypeTokens.scaleDefault
            }
        }
        refreshAlerts()
    }

    /// Rebuilds the bell's alerts (on appear and whenever the Hub becomes key; no polling).
    func refreshAlerts() {
        let p = PermissionSnapshot.current()
        var out: [HubAlert] = []
        if !p.microphone { out.append(HubAlert(id: "mic", title: "Microphone access is off", detail: "Murmur can't hear you until it's on.", pane: "Privacy_Microphone")) }
        if !p.accessibility { out.append(HubAlert(id: "ax", title: "Accessibility is off", detail: "Murmur can't type into other apps.", pane: "Privacy_Accessibility")) }
        if !p.inputMonitoring { out.append(HubAlert(id: "im", title: "Input Monitoring is off", detail: "Murmur can't see the shortcut key.", pane: "Privacy_ListenEvent")) }
        if status?.phase == .error, let message = status?.message {
            out.append(HubAlert(id: "error", title: "Last dictation needs attention", detail: message, pane: nil))
        }
        if out != alerts { alerts = out }
    }

    /// The push-to-talk key as the status card and copy show it ("fn", "⌃ Ctrl").
    var hotkeyLabel: String {
        let shortcut = DictationController.shortcutConfiguration(settings).pushToTalk
        guard case .modifiers(let mods) = shortcut, mods.count == 1, let key = mods.first else { return shortcut.displayName }
        return switch key {
        case .fn: "fn"
        case .control: "\(key.symbol) Ctrl"
        case .option: "\(key.symbol) Option"
        case .command: "\(key.symbol) Cmd"
        case .shift: "\(key.symbol) Shift"
        }
    }

    public func go(_ page: HubPage) {
        guard page != self.page else { return }
        backStack.append(self.page)
        forwardStack.removeAll()
        self.page = page
    }

    public func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(page)
        page = previous
    }

    public func forward() {
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

    var settingsSelected: Bool { HubPage.settings.contains(page) }

    /// The microphone level, 0…1, read at display rate during the mic test.
    var micLevel: Double {
        guard let dbfs = controller.micLevel.read() else { return 0 }
        return min(1, max(0, (Double(dbfs) + 60) / 50))
    }
}

struct GeneralPage: View {
    let model: HubModel
    @State private var engine = AppSettings.shared.engine
    @State private var cleanup = AppSettings.shared.cleanupProvider

    /// Recommended first, then local, then cloud, then no AI.
    static let cleanupOrder = ["mlx:qwen3.5-4b", "mlx:smollm3-3b", "mlx:qwen3-4b-2507", "mlx:qwen3.5-2b", "apple-foundation", "groq", "openrouter", "rules"]

    var body: some View {
        Form {
            Section("Shortcuts") { ShortcutSettings(model: model) }
            Section("Microphone") { MicrophoneSettings(model: model) }
            Section {
                Picker("Speech engine", selection: $engine) {
                    ForEach(EngineCatalog.ids.filter { ModelNames.engines[$0] != nil }, id: \.self) { Text(ModelNames.engines[$0] ?? $0).tag($0) }
                }
                .onChange(of: engine) { model.settings.engine = engine }
                Picker("Cleanup model", selection: $cleanup) {
                    ForEach(Self.cleanupOrder.filter { ModelNames.cleanup[$0] != nil }, id: \.self) { Text(ModelNames.cleanup[$0] ?? $0).tag($0) }
                }
                .onChange(of: cleanup) { model.settings.cleanupProvider = cleanup }
            } header: {
                Text("Models")
            } footer: {
                Footnote("The speech engine turns your voice into words; the cleanup model tidies them. Both run on this Mac unless you pick a cloud option.")
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
    @State private var smartFormatting = AppSettings.shared.smartFormatting
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var sounds = AppSettings.shared.soundsEnabled
    @State private var debug = AppSettings.shared.debugMenu
    @State private var unloadWhenIdle = AppSettings.shared.unloadWhenIdle
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Flow Bar") {
                Toggle(isOn: $showFlowBar) {
                    Text("Show the Flow Bar at all times")
                    Text("Off: it appears only while you dictate or when something needs your attention.")
                }
                .onChange(of: showFlowBar) { model.settings.showFlowBar = showFlowBar }
                Toggle(isOn: $sounds) {
                    Text("Sounds")
                    Text("A soft sound when dictation starts, stops and finishes.")
                }
                .onChange(of: sounds) { model.settings.soundsEnabled = sounds }
            }
            Section("Formatting") {
                Toggle(isOn: $smartFormatting) {
                    Text("Smart Formatting")
                    Text("Turns spoken lists of three or more items into numbered lists, and long dictations into paragraphs. Needs AI edits.")
                }
                .onChange(of: smartFormatting) { model.settings.smartFormatting = smartFormatting }
            }
            Section("App") {
                Toggle("Launch Murmur at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Toggle(isOn: $showInDock) {
                    Text("Show in Dock")
                    Text("Murmur always stays in the menu bar.")
                }
                .onChange(of: showInDock) { model.settings.showInDock = showInDock }
            }
            Section {
                TypingApps(settings: model.settings)
            } header: {
                Text("Typing instead of pasting")
            } footer: {
                Footnote("For apps where pasting does not work, like some games and remote tools. Murmur types the text instead and never touches the clipboard. Typing is slower, and undoing it may take more than one ⌘Z.")
            }
            Section("Advanced") {
                Toggle(isOn: $unloadWhenIdle) {
                    Text("Free memory when idle")
                    Text("After 10 minutes without dictation, Murmur unloads its models (about 2 GB) and reloads them as you start speaking. Off by default for now: each reload currently leaves about 400 MB behind.")
                }
                .onChange(of: unloadWhenIdle) { model.settings.unloadWhenIdle = unloadWhenIdle }
                Toggle(isOn: $debug) {
                    Text("Debug menu")
                    Text("Adds tools for testing the Flow Bar, sounds and focus to the menu bar menu.")
                }
                .onChange(of: debug) { model.settings.debugMenu = debug }
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
    let model: HubModel
    @State private var commandMode = AppSettings.shared.commandMode
    @State private var pressEnter = AppSettings.shared.pressEnter
    @State private var confirmPressEnter = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $commandMode) {
                    Text("Command Mode")
                    Text("Hold \(HotkeyConfiguration.defaultCommand(appleKeyboard: model.settings.keyboardLayout != "other").displayName) (in either order) and speak an instruction, like “make this friendlier” or “translate to Spanish”. With text selected, Murmur rewrites it in place, and one ⌘Z brings it back. With nothing selected, it writes a draft at the cursor.")
                }
                .onChange(of: commandMode) { model.settings.commandMode = commandMode }
                Toggle(isOn: Binding(get: { pressEnter }, set: { on in
                    if on { confirmPressEnter = true } else { pressEnter = false; model.settings.pressEnter = false }
                })) {
                    Text("Press Enter after “press enter”")
                    Text("End a dictation with “press enter” and Murmur presses Return after pasting.")
                }
            } footer: {
                Footnote("Command Mode uses the cleanup model chosen in Settings › General › Models, on this Mac unless you picked a cloud model. You can change its shortcut in General › Shortcuts.")
            }
        }
        .formStyle(.grouped)
        .alert("Turn on Press Enter?", isPresented: $confirmPressEnter) {
            Button("Turn On") { pressEnter = true; model.settings.pressEnter = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("When a dictation ends with “press enter”, Murmur presses Return right after pasting. In chat apps that sends the message at once.")
        }
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
                Toggle(isOn: $keepAudio) {
                    Text("Keep audio for 14 days")
                    Text("Lets you replay a dictation and retry it if something went wrong.")
                }
                .onChange(of: keepAudio) { model.settings.keepAudio = keepAudio }
                .disabled(neverStore)
                Toggle(isOn: $neverStore) {
                    Text("Never store anything")
                    Text("No History, no audio, nothing written to disk. Paste last still works until Murmur quits.")
                }
                .onChange(of: neverStore) { model.settings.neverStore = neverStore }
                HStack {
                    Spacer()
                    Button("Delete all History and audio…", role: .destructive) { confirmDelete = true }
                }
            }
            Section {
                CloudKeys()
            } header: {
                Text("Cloud (optional)")
            } footer: {
                Footnote("Audio and text stay on this Mac unless you choose a Groq or OpenRouter option. Murmur has no analytics, and its logs hold timings, never your words.")
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

/// I9: the apps that get typed text instead of a paste.
struct TypingApps: View {
    let settings: AppSettings
    @State private var apps: [String] = AppSettings.shared.typingApps

    var body: some View {
        ForEach(apps, id: \.self) { id in
            HStack(spacing: 8) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                } else {
                    Text(id).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove") { apps.removeAll { $0 == id }; settings.typingApps = apps }
            }
        }
        Button("Add App…", action: pick)
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
        }
        settings.typingApps = apps
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
            Text(label)
            Spacer()
            SecureField(saved.wrappedValue ? "Saved in Keychain" : "Paste key", text: text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 240)
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
            if !snapshot.inputMonitoring {
                HStack {
                    Footnote("After you turn on Input Monitoring, macOS may need Murmur to restart.")
                    Spacer()
                    Button("Restart Murmur") { Self.relaunch() }
                }
            }
        }
        .onReceive(timer) { _ in snapshot = .current() }
    }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
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

public struct PermissionSnapshot: Equatable, Sendable {
    public var microphone: Bool
    public var accessibility: Bool
    public var inputMonitoring: Bool

    public var allGranted: Bool { microphone && accessibility && inputMonitoring }

    public static func current() -> PermissionSnapshot {
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
        if let command = config.command {
            ShortcutRow(title: "Command Mode", shortcut: command, model: model) { new in
                config.command = new
                model.controller.setShortcuts(config)
            }
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
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !testing)) { _ in
                LevelMeter(level: testing ? model.micLevel : 0)
            }
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
