import AppKit
import AVFoundation
import MurmurKit
import ServiceManagement
import SwiftUI
import UI

/// A confirmation over the Settings page (custom, not a system alert: §2.6).
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let action: () -> Void
}

/// Settings (UI_REDESIGN.md v2 §5.3): General, System, Experimental, Data & privacy. Every SPEC setting
/// keeps working; only the controls changed (all §4 components, no stock ones).
struct SettingsPage: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme
    @State private var confirm: ConfirmRequest?

    var body: some View {
        HubPageScroll {
            SerifTitle("Settings")
            MSegmented("Settings section", selection: Binding(get: { model.page }, set: { model.go($0) }),
                       items: [(.general, "General"), (.system, "System"), (.experimental, "Experimental"), (.privacy, "Data & privacy")])
            switch model.page {
            case .system: SystemSettings(model: model)
            case .experimental: ExperimentalSettings(model: model, confirm: $confirm)
            case .privacy: PrivacySettings(model: model, confirm: $confirm)
            default: GeneralSettings(model: model)
            }
        }
        .overlay {
            if let request = confirm {
                ZStack {
                    theme.colors.scrim.color.onTapGesture { confirm = nil }
                    MDialog(request.title) {
                        Text(request.message).textStyle(TypeTokens.body).foregroundStyle(theme.colors.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Spacing.s12) {
                            Spacer()
                            MButton("Cancel", kind: .outline, size: .small) { confirm = nil }
                            MButton(request.confirmTitle, kind: .ink, size: .small) {
                                request.action()
                                confirm = nil
                            }
                        }
                    }
                }
                .transition(.opacity.animation(theme.motion.easeOut(MotionTokens.hover)))
            }
        }
    }
}

/// Two columns of settings groups.
struct SettingsColumns<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .top, spacing: HubGeometry.settingsColumnGap) {
            VStack(alignment: .leading, spacing: HubGeometry.settingsGroupGap) { left }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: HubGeometry.settingsGroupGap) { right }.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme
    @State private var config: HotkeyConfiguration = DictationController.shortcutConfiguration(.shared)
    @State private var engine = AppSettings.shared.engine
    @State private var cleanup = AppSettings.shared.cleanupProvider
    @State private var level = AppSettings.shared.cleanupLevel
    @State private var appearance = AppSettings.shared.appearance
    @State private var textSize = AppSettings.shared.textSize
    @State private var sounds = AppSettings.shared.soundsEnabled
    @State private var showFlowBar = AppSettings.shared.showFlowBar
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var languagesOpen = false

    /// Recommended first, then local, then cloud, then no AI.
    static let cleanupOrder = ["mlx:qwen3.5-4b", "mlx:smollm3-3b", "mlx:qwen3-4b-2507", "mlx:qwen3.5-2b", "apple-foundation", "groq", "openrouter", "rules"]

    var body: some View {
        let s = model.settings
        SettingsColumns {
            MSettingsGroup("Dictation", footer: "Double-tap push-to-talk also starts hands-free. Esc cancels.") {
                ShortcutRecorderRow(title: "Push-to-talk", detail: "Hold to speak, release to type.", shortcut: config.pushToTalk, model: model) { new in
                    config.pushToTalk = new
                    model.controller.setShortcuts(config)
                }
                ShortcutRecorderRow(title: "Hands-free", detail: "Tap to start, tap again to stop.", shortcut: config.handsFree, model: model) { new in
                    config.handsFree = new
                    model.controller.setShortcuts(config)
                }
                if let command = config.command {
                    ShortcutRecorderRow(title: "Command Mode", detail: "Speak an instruction instead of text.", shortcut: command, model: model) { new in
                        config.command = new
                        model.controller.setShortcuts(config)
                    }
                }
                MicrophoneRows(model: model)
                MSettingsRow("Languages", detail: "Switches on its own, even mid-sentence.") {
                    MNavigateSelect("Languages", value: LanguageNames.summary(s.languages)) { languagesOpen = true }
                }
                MSettingsRow("Shortcuts", detail: "Back to fn to hold and fn Space for hands-free.") {
                    MButton("Reset to defaults", kind: .outline, size: .small) {
                        model.controller.setShortcuts(nil)
                        config = DictationController.shortcutConfiguration(model.settings)
                    }
                }
                if config.pushToTalk == .modifiers([.fn]) || config.handsFree == .key(keyCode: 49, modifiers: [.fn]), Permissions.fnUsageType != 0 {
                    MSettingsRow("The Globe key may open emoji or dictation", detail: "Set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing.") {
                        MButton("Open", kind: .outline, size: .small) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                if Permissions.secureEventInput {
                    MSettingsRow("Shortcuts are blocked", detail: "Another app has Secure Keyboard Entry on. Shortcuts work again once it is turned off.") { EmptyView() }
                }
            }
            MSettingsGroup("Appearance") {
                MSettingsRow("Theme", detail: "The Flow Bar stays ink either way.") {
                    MSegmented("Theme", selection: $appearance, items: [("system", "System"), ("light", "Light"), ("dark", "Dark")], size: .small)
                }
                MSettingsRow("Text size", detail: "Applies to the Hub only.") {
                    MSegmented("Text size", selection: $textSize, items: [("default", "Default"), ("large", "Large")], size: .small)
                }
            }
        } right: {
            MSettingsGroup("Output") {
                MSettingsRow("Auto cleanup", detail: "See examples on the Style page.") {
                    MSegmented("Auto cleanup", selection: $level, items: [("none", "None"), ("light", "Light"), ("medium", "Medium")], size: .small)
                }
                MSettingsRow("Speech engine", detail: "Turns your voice into words.") {
                    MSelect("Speech engine", selection: $engine,
                            options: EngineCatalog.ids.filter { ModelNames.engines[$0] != nil }.map { ($0, ModelNames.engines[$0] ?? $0) }, mono: true)
                }
                MSettingsRow("Cleanup model", detail: "Tidies the words. On this Mac unless you pick a cloud model.") {
                    MSelect("Cleanup model", selection: $cleanup,
                            options: Self.cleanupOrder.filter { ModelNames.cleanup[$0] != nil }.map { ($0, ModelNames.cleanup[$0] ?? $0) })
                }
                MToggleRow("Sounds", detail: "Start, stop and error cues.", isOn: $sounds)
                MToggleRow("Show Flow Bar", detail: "Rests above the Dock when idle.", isOn: $showFlowBar)
                MToggleRow("Launch at login", detail: loginError ?? "Ready before you need it.", isOn: $launchAtLogin)
            }
            MInfoCard("Nothing leaves this Mac", detail: "Audio and transcripts stay on-device. Retention lives under Data & privacy.")
        }
        .onChange(of: engine) { s.engine = engine }
        .onChange(of: cleanup) { s.cleanupProvider = cleanup }
        .onChange(of: level) { s.cleanupLevel = level }
        .onChange(of: appearance) { s.appearance = appearance }
        .onChange(of: textSize) { s.textSize = textSize }
        .onChange(of: sounds) { s.soundsEnabled = sounds }
        .onChange(of: showFlowBar) { s.showFlowBar = showFlowBar }
        .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
        .overlay {
            if languagesOpen {
                ZStack {
                    theme.colors.scrim.color.onTapGesture { languagesOpen = false }
                    LanguagesSheet(settings: s) { languagesOpen = false }
                }
            }
        }
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

/// Records a new shortcut (D8): modifiers alone save when released, a key combination when its key is
/// released, a mouse button when pressed. Esc cancels.
struct ShortcutRecorderRow: View {
    let title: String
    let detail: String
    let shortcut: Shortcut
    let model: HubModel
    let save: (Shortcut) -> Void
    @Environment(\.theme) private var theme
    @State private var recording = false
    @State private var monitor: Any?
    @State private var peak: Set<ModifierKey> = []
    @State private var pendingKey: (Int, Set<ModifierKey>)?

    var body: some View {
        MSettingsRow(title, detail: detail) {
            HStack(spacing: HubGeometry.settingsControlGap) {
                if recording {
                    Text("Press the new shortcut…").textStyle(TypeTokens.hint).foregroundStyle(theme.colors.textSecondary.color)
                    MButton("Cancel", kind: .link, size: .small) { stop() }
                } else {
                    MShortcut(Self.keys(shortcut), onWindow: true)
                    MButton("Change", kind: .outline, size: .small) { start() }
                }
            }
        }
        .onDisappear { stop() }
    }

    /// The key caps for a shortcut: "fn", "⌃ Ctrl", or "⌥" "Space".
    static func keys(_ shortcut: Shortcut) -> [String] {
        if case .modifiers(let mods) = shortcut, mods.count == 1, let key = mods.first {
            return [key == .fn ? "fn" : "\(key.symbol) " + (key == .control ? "Ctrl" : key == .option ? "Option" : key == .command ? "Cmd" : "Shift")]
        }
        return shortcut.displayName.split(separator: " ").map(String.init)
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

/// The microphone (D9): the input device, and a test with a level meter.
struct MicrophoneRows: View {
    let model: HubModel
    @State private var devices = AudioDevices.inputs()
    @State private var selected = AppSettings.shared.microphoneUID ?? ""
    @State private var testing = false

    var body: some View {
        MSettingsRow("Microphone", detail: "Used for every dictation.") {
            MSelect("Microphone", selection: $selected,
                    options: [("", "System default")] + devices.map { ($0.uid, $0.name + ($0.isDefault ? " (default)" : "")) })
        }
        .onChange(of: selected) { model.controller.selectMicrophone(uid: selected.isEmpty ? nil : selected) }
        MSettingsRow("Microphone test", detail: testing ? "Speak at your normal volume." : "Check that Murmur hears you.") {
            HStack(spacing: Spacing.s10) {
                if testing {
                    TimelineView(.animation(paused: !testing)) { _ in MLevelMeter(level: model.micLevel, compact: true) }
                }
                MButton(testing ? "Stop" : "Test", kind: .outline, size: .small) { toggleTest() }
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

/// T3: language names, and the summary the Languages row shows.
enum LanguageNames {
    static let common: [(String, String)] = [
        ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("it", "Italiano"), ("pt", "Português"),
        ("nl", "Nederlands"), ("pl", "Polski"), ("sv", "Svenska"), ("da", "Dansk"), ("fi", "Suomi"), ("ro", "Română"),
        ("cs", "Čeština"), ("hu", "Magyar"), ("el", "Ελληνικά"), ("uk", "Українська"), ("ru", "Русский"),
    ]

    static func summary(_ codes: [String]) -> String {
        codes.isEmpty ? "Detect automatically" : codes.compactMap { code in common.first { $0.0 == code }?.1 }.joined(separator: ", ")
    }
}

/// T3: automatic detection, or the languages you speak, as chips.
struct LanguagesSheet: View {
    let settings: AppSettings
    let done: () -> Void
    @Environment(\.theme) private var theme
    @State private var chosen: Set<String> = Set(AppSettings.shared.languages)

    var body: some View {
        MDialog("Languages") {
            MSettingsGroup {
                MToggleRow("Detect automatically", detail: "Murmur detects the language of each dictation.",
                           isOn: Binding(get: { chosen.isEmpty }, set: { if $0 { chosen = []; save() } }))
            }
            LanguageChips(chosen: $chosen) { save() }
            Text(chosen.count == 1 ? "Transcribed as \(LanguageNames.summary(Array(chosen))) only." : "Choosing one language helps Murmur avoid stray words from others.")
                .textStyle(TypeTokens.hint).foregroundStyle(theme.colors.textTertiary.color).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                MButton("Done", kind: .ink, size: .small, action: done)
            }
        }
    }

    func save() { settings.languages = chosen.sorted() }
}

/// The language chips (Settings and onboarding): selected chips are ink with a check.
struct LanguageChips: View {
    @Binding var chosen: Set<String>
    let changed: () -> Void

    var body: some View {
        FlowLayout(spacing: Spacing.s8) {
            ForEach(LanguageNames.common, id: \.0) { code, name in
                MChip(name, selected: chosen.contains(code)) {
                    if chosen.contains(code) { chosen.remove(code) } else { chosen.insert(code) }
                    changed()
                }
            }
        }
    }
}

/// Lays chips out in rows, wrapping at the available width.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - System

struct SystemSettings: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme
    @State private var smartFormatting = AppSettings.shared.smartFormatting
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var debug = AppSettings.shared.debugMenu
    @State private var unloadWhenIdle = AppSettings.shared.unloadWhenIdle
    @State private var apps: [String] = AppSettings.shared.typingApps

    var body: some View {
        let s = model.settings
        SettingsColumns {
            MSettingsGroup("Formatting") {
                MToggleRow("Smart Formatting", detail: "Turns spoken lists of three or more items into numbered lists, and long dictations into paragraphs. Needs AI edits.",
                           isOn: $smartFormatting)
            }
            MSettingsGroup("App") {
                MToggleRow("Show in Dock", detail: "Murmur always stays in the menu bar.", isOn: $showInDock)
            }
            MSettingsGroup("Advanced") {
                MToggleRow("Free memory when idle", detail: "After 10 minutes without dictation, Murmur unloads its models (about 2 GB) and reloads them as you start speaking.",
                           isOn: $unloadWhenIdle)
                MToggleRow("Debug menu", detail: "Adds tools for testing the Flow Bar, sounds and focus to the menu bar menu.", isOn: $debug)
            }
        } right: {
            MSettingsGroup("Typing instead of pasting", footer: "For apps where pasting does not work, like some games and remote tools. Murmur types the text instead and never touches the clipboard. Typing is slower, and undoing it may take more than one ⌘Z.") {
                ForEach(apps, id: \.self) { id in
                    MSettingsRow(Self.name(id), detail: id) {
                        MButton("Remove", kind: .outline, size: .small) { apps.removeAll { $0 == id }; s.typingApps = apps }
                    }
                }
                MSettingsRow(apps.isEmpty ? "No apps yet" : "Add another app", detail: "Choose an app in Applications.") {
                    MButton("Add app…", kind: .outline, size: .small, action: pick)
                }
            }
            MSettingsGroup("Permissions") {
                PermissionSettingsRows()
            }
        }
        .onChange(of: smartFormatting) { s.smartFormatting = smartFormatting }
        .onChange(of: showInDock) { s.showInDock = showInDock }
        .onChange(of: debug) { s.debugMenu = debug }
        .onChange(of: unloadWhenIdle) { s.unloadWhenIdle = unloadWhenIdle }
    }

    static func name(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
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
        model.settings.typingApps = apps
    }
}

/// A3: each permission with its state and the button that fixes it; Input Monitoring may need a restart.
struct PermissionSettingsRows: View {
    @State private var snapshot = PermissionSnapshot.current()

    var body: some View {
        row("Microphone", snapshot.microphone, pane: "Privacy_Microphone") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
        row("Accessibility", snapshot.accessibility, pane: "Privacy_Accessibility") { Permissions.promptAccessibility() }
        row("Input Monitoring", snapshot.inputMonitoring, pane: "Privacy_ListenEvent") { Permissions.requestInputMonitoring() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in snapshot = .current() }
        if !snapshot.inputMonitoring {
            MSettingsRow("Restart Murmur", detail: "After you turn on Input Monitoring, macOS may need Murmur to restart.") {
                MButton("Restart", kind: .outline, size: .small) { AppRelaunch.now() }
            }
        }
    }

    func row(_ name: String, _ ok: Bool, pane: String, request: @escaping () -> Void) -> some View {
        MSettingsRow(name, detail: ok ? "On" : "Off") {
            if !ok {
                MButton("Open System Settings", kind: .outline, size: .small) {
                    request()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

// MARK: - Experimental

struct ExperimentalSettings: View {
    @Bindable var model: HubModel
    @Binding var confirm: ConfirmRequest?
    @State private var commandMode = AppSettings.shared.commandMode
    @State private var pressEnter = AppSettings.shared.pressEnter

    var body: some View {
        SettingsColumns {
            MSettingsGroup("Experimental", footer: "Command Mode uses the cleanup model chosen under General › Output, on this Mac unless you picked a cloud model. Change its shortcut under General › Dictation.") {
                MToggleRow("Command Mode", detail: "Hold \(HotkeyConfiguration.defaultCommand(appleKeyboard: model.settings.keyboardLayout != "other").displayName) (in either order) and speak an instruction, like “make this friendlier” or “translate to Spanish”. With text selected, Murmur rewrites it in place, and one ⌘Z brings it back. With nothing selected, it writes a draft at the cursor.",
                           isOn: $commandMode)
                MToggleRow("Press Enter after “press enter”", detail: "End a dictation with “press enter” and Murmur presses Return after pasting.",
                           isOn: Binding(get: { pressEnter }, set: { on in
                               if on {
                                   confirm = ConfirmRequest(title: "Turn on Press Enter?",
                                                            message: "When a dictation ends with “press enter”, Murmur presses Return right after pasting. In chat apps that sends the message at once.",
                                                            confirmTitle: "Turn on") {
                                       pressEnter = true
                                       model.settings.pressEnter = true
                                   }
                               } else {
                                   pressEnter = false
                                   model.settings.pressEnter = false
                               }
                           }))
            }
        } right: {
            EmptyView()
        }
        .onChange(of: commandMode) { model.settings.commandMode = commandMode }
    }
}

// MARK: - Data & privacy

struct PrivacySettings: View {
    @Bindable var model: HubModel
    @Binding var confirm: ConfirmRequest?
    @State private var keepAudio = AppSettings.shared.keepAudio
    @State private var neverStore = AppSettings.shared.neverStore

    var body: some View {
        SettingsColumns {
            MSettingsGroup("History") {
                MToggleRow("Keep audio for 14 days", detail: "Lets you replay a dictation and retry it if something went wrong.", isOn: $keepAudio)
                    .disabled(neverStore)
                MToggleRow("Never store anything", detail: "No History, no audio, nothing written to disk. Paste last still works until Murmur quits.", isOn: $neverStore)
                MSettingsRow("Delete all History and audio", detail: "Your dictionary and snippets stay.") {
                    MButton("Delete…", kind: .outline, size: .small) {
                        confirm = ConfirmRequest(title: "Delete all History and audio?", message: "This cannot be undone. Your dictionary and snippets stay.",
                                                 confirmTitle: "Delete everything") {
                            try? model.store.deleteAll()
                            try? FileManager.default.removeItem(at: MurmurPaths.audio)
                        }
                    }
                }
            }
            MInfoCard("Nothing leaves this Mac", detail: "Audio and text stay on this Mac unless you choose a Groq or OpenRouter option. Murmur has no analytics, and its logs hold timings, never your words.")
        } right: {
            MSettingsGroup("Cloud (optional)", footer: "Keys are stored in your Keychain.") {
                CloudKeyRow(label: "Groq API key", account: "groq")
                CloudKeyRow(label: "OpenRouter API key", account: "openrouter")
            }
        }
        .onChange(of: keepAudio) { model.settings.keepAudio = keepAudio }
        .onChange(of: neverStore) { model.settings.neverStore = neverStore }
    }
}

/// A cloud key, stored in the Keychain; the field never shows a saved key.
struct CloudKeyRow: View {
    let label: String
    let account: String
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        MSettingsRow(label, detail: saved ? "Saved in Keychain" : "Not set") {
            HStack(spacing: HubGeometry.settingsControlGap) {
                MTextField(saved ? "Replace key" : "Paste key", text: $text, secure: true).frame(width: HubGeometry.dictionaryWordField)
                MButton("Save", kind: .outline, size: .small) {
                    Keychain.set(text, for: account)
                    saved = !text.isEmpty
                    text = ""
                }
                .disabled(text.isEmpty)
                if saved { MButton("Remove", kind: .link, size: .small) { Keychain.set(nil, for: account); saved = false } }
            }
        }
        .onAppear { saved = Keychain.get(account) != nil }
    }
}
