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
