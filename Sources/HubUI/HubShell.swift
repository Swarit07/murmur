import AppKit
import MurmurKit
import SwiftUI
import UI

/// A system alert for the bell popover: a missing permission or the last error.
struct HubAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    /// The System Settings privacy pane that fixes it, if any.
    let pane: String?
}

/// The Hub (UI_REDESIGN.md v2 §3.4, §5.3): an ivory window with the sidebar on the left and a raised
/// paper panel inset 8 pt from the top, right and bottom. No split view, no stock list; the traffic
/// lights sit in the sidebar's top zone under a transparent title bar.
public struct HubView: View {
    @Bindable var model: HubModel

    public init(model: HubModel) {
        self.model = model
    }

    public var body: some View {
        ThemeProvider(textScale: model.textScale) {
            HubShell(model: model)
        }
    }
}

struct HubShell: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let motion = theme.motion
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        HStack(spacing: 0) {
            HubSidebar(model: model)
                .frame(width: HubGeometry.sidebarWidth)
            ZStack(alignment: .topTrailing) {
                shape.fill(c.bgPanel.color)
                HubPageView(model: model)
                    // Content starts inside the panel's 1 pt edge, as the board's bordered box does.
                    .padding(Stroke.hairline)
                    .id(model.page)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: motion.offset(MotionTokens.pageRise))).animation(motion.easeOut(MotionTokens.pageSwitch)),
                        removal: .opacity.animation(motion.easeOut(MotionTokens.pageSwitch / 2))))
                if model.bellOpen {
                    BellPopover(model: model)
                        .padding(.top, HubGeometry.topBarHeight)
                        .padding(.trailing, Spacing.s12)
                        .transition(.opacity.animation(motion.easeOut(MotionTokens.hover)))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(c.edgePanel.color, lineWidth: Stroke.hairline))
            .padding([.top, .trailing, .bottom], HubGeometry.panelInset)
        }
        .background(c.bgWindow.color)
        .overlay {
            if model.helpOpen {
                ZStack {
                    c.scrim.color.ignoresSafeArea().onTapGesture { model.helpOpen = false }
                    HelpSheet(model: model)
                }
                .transition(.opacity.animation(motion.easeOut(MotionTokens.hover)))
            } else if let document = model.document {
                ZStack {
                    c.scrim.color.ignoresSafeArea().onTapGesture { model.document = nil }
                    DocumentDialog(model: model, document: document)
                }
                .transition(.opacity.animation(motion.easeOut(MotionTokens.hover)))
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: HubGeometry.minimumWindow.width, minHeight: HubGeometry.minimumWindow.height)
        .background {
            // Option+Up / Option+Down move through the sidebar; Cmd+[ / Cmd+] go back and forward.
            Group {
                Button("") { model.step(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
                Button("") { model.step(1) }.keyboardShortcut(.downArrow, modifiers: .option)
                Button("") { model.back() }.keyboardShortcut("[", modifiers: .command)
                Button("") { model.forward() }.keyboardShortcut("]", modifiers: .command)
                Button("") { model.bellOpen = false; model.helpOpen = false; model.document = nil }.keyboardShortcut(.cancelAction)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .animation(motion.easeOut(MotionTokens.pageSwitch), value: model.page)
        .onAppear { model.refreshAlerts() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in model.refreshAlerts() }
    }
}

/// The sidebar (§3.4): the traffic lights' zone, the brand mark, the four pages, then Settings, Help &
/// setup and the status card at the bottom.
struct HubSidebar: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HubGeometry.sidebarItemGap) {
            Color.clear.frame(height: HubGeometry.trafficLightsZone)
            BrandMark(height: HubGeometry.brandMarkHeight)
                .padding(.leading, HubGeometry.brandMarkLeft)
                .padding(.vertical, HubGeometry.brandMarkInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WindowDragArea())
            MSidebarItem("Home", icon: .home, selected: model.page == .home) { model.go(.home) }
            MSidebarItem("Dictionary", icon: .dictionary, selected: model.page == .dictionary) { model.go(.dictionary) }
            MSidebarItem("Snippets", icon: .snippet, selected: model.page == .snippets) { model.go(.snippets) }
            MSidebarItem("Style", icon: .style, selected: model.page == .style) { model.go(.style) }
            Spacer(minLength: Spacing.s12)
            MSidebarItem("Settings", icon: .settings, selected: model.settingsSelected) {
                if !model.settingsSelected { model.go(.general) }
            }
            MSidebarItem("Help & setup", icon: .help, selected: model.helpOpen) { model.helpOpen = true }
            HubStatusCard(model: model).padding(.top, Spacing.s8)
        }
        .padding(.top, HubGeometry.sidebarPaddingTop)
        .padding(.horizontal, HubGeometry.sidebarPaddingSide)
        .padding(.bottom, HubGeometry.sidebarPaddingSide)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) { WindowDragArea().frame(height: HubGeometry.sidebarPaddingTop + HubGeometry.trafficLightsZone) }
    }
}

/// The status card: ready / listening / working / loading, the shortcut and the microphone.
struct HubStatusCard: View {
    let model: HubModel

    var body: some View {
        let phase = model.status?.phase ?? .loading
        let title = switch phase {
        case .loading: "Loading models…"
        case .idle, .inserted: "Ready"
        case .recording: "Listening…"
        case .processing: "Working…"
        case .error: "Needs attention"
        }
        let live: Bool = if case .recording = phase { true } else { false }
        let cloud = AppInfo.cloud(model.controller)
        MStatusCard(title: title, tag: cloud.speech || cloud.cleanup ? "cloud" : "on-device", hotkey: model.hotkeyLabel,
                    microphone: model.controller.microphoneName, live: live)
            .help(model.status?.message ?? title)
    }
}

/// The page in the panel. Home has the 48 pt top bar with search and the bell; every page scrolls.
struct HubPageView: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if model.page == .home {
                HStack(spacing: Spacing.s4) {
                    Spacer()
                    MIconButton(.search, label: "Search History", selected: model.searchOpen) { model.searchOpen.toggle() }
                    MIconButton(.bell, label: "Notifications", selected: model.bellOpen) { model.bellOpen.toggle() }
                        .overlay(alignment: .topTrailing) {
                            if !model.alerts.isEmpty {
                                Circle()
                                    .fill(theme.colors.textPrimary.color)
                                    .frame(width: HubGeometry.bellDot, height: HubGeometry.bellDot)
                                    .overlay(Circle().stroke(theme.colors.bgPanel.color, lineWidth: HubGeometry.bellDotRing))
                                    .offset(x: -HubGeometry.bellDot / 2, y: HubGeometry.bellDot / 2)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityValue(model.alerts.isEmpty ? "No alerts" : "\(model.alerts.count) alerts")
                }
                .padding(.horizontal, Spacing.s12)
                .frame(height: HubGeometry.topBarHeight)
                .background(WindowDragArea())
            }
            switch model.page {
            case .home: HomePage(model: model)
            case .dictionary: DictionaryPage(store: model.store)
            case .snippets: SnippetsPage(store: model.store)
            case .style: StylePage(model: model)
            case .general, .system, .experimental, .privacy: SettingsPage(model: model)
            }
        }
    }
}

/// The bell's popover (§5.3): system alerts, such as a revoked permission, with the fix.
struct BellPopover: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s12) {
            MCaption("Notifications")
            if model.alerts.isEmpty {
                Text("Nothing needs your attention.").textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
            }
            ForEach(model.alerts) { alert in
                HStack(alignment: .top, spacing: Spacing.s10) {
                    IconView(.alert, size: HubGeometry.iconGlyph, color: c.textPrimary.color)
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        Text(alert.title).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                        Text(alert.detail).textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                        if let pane = alert.pane {
                            MButton("Open System Settings", kind: .outline, size: .small) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.s16)
        .frame(width: HubGeometry.popoverWidth, alignment: .leading)
        .background(shape.fill(c.bgPanel.color).floatShadow(theme))
        .overlay(shape.strokeBorder(c.edgeToast.color, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notifications")
    }
}

/// Help & setup (§5.3): shortcuts, permissions, the privacy notes and acknowledgements (LEGAL_DOCS.md
/// L5), run setup again, the version.
struct HelpSheet: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let config = DictationController.shortcutConfiguration(model.settings)
        MDialog("Help & setup") {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                MCaption("Shortcuts")
                HStack(spacing: Spacing.s8) {
                    Text("Push-to-talk").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                    Spacer()
                    MShortcut([model.hotkeyLabel])
                }
                HStack(spacing: Spacing.s8) {
                    Text("Hands-free").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                    Spacer()
                    MShortcut(config.handsFree.displayName.split(separator: " ").map(String.init))
                }
                MCaption("Permissions")
                PermissionRows()
                MCaption("About")
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    HStack(spacing: Spacing.s8) {
                        Text("Privacy").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                        Spacer()
                        MNavigateSelect("Privacy", value: "What stays on this Mac") { model.open(.privacy, fromHelp: true) }
                    }
                    HStack(spacing: Spacing.s8) {
                        Text("Acknowledgements").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                        Spacer()
                        MNavigateSelect("Acknowledgements", value: "Open-source licenses") { model.open(.acknowledgements, fromHelp: true) }
                    }
                }
                HStack(spacing: Spacing.s12) {
                    MButton("Run setup again", kind: .outline, size: .small) {
                        model.helpOpen = false
                        model.onRunOnboarding?()
                    }
                    Spacer()
                    Text("v\(AppInfo.version) · \(AppInfo.requirement)").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
                    MButton("Done", kind: .ink, size: .small) { model.helpOpen = false }
                }
            }
        }
    }
}

/// Permission status rows with a fix button (A3), checked when shown and when the window is key.
struct PermissionRows: View {
    @Environment(\.theme) private var theme
    @State private var snapshot = PermissionSnapshot.current()

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: Spacing.s8) {
            row("Microphone", snapshot.microphone, pane: "Privacy_Microphone", c: c)
            row("Accessibility", snapshot.accessibility, pane: "Privacy_Accessibility", c: c)
            row("Input Monitoring", snapshot.inputMonitoring, pane: "Privacy_ListenEvent", c: c)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in snapshot = .current() }
    }

    func row(_ name: String, _ ok: Bool, pane: String, c: ThemeColors) -> some View {
        HStack(spacing: Spacing.s10) {
            IconView(ok ? .check : .alert, size: HubGeometry.iconGlyph, color: c.textPrimary.color)
            Text(name).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
            Text(ok ? "On" : "Off").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
            Spacer()
            if !ok {
                MButton("Open System Settings", kind: .outline, size: .small) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
