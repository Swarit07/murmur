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
    public var hotkeyLabel: String {
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

/// Restarts Murmur (Input Monitoring can need it after it's turned on).
enum AppRelaunch {
    static func now() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
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
