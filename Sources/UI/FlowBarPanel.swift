import AppKit
import ApplicationServices
import SwiftUI

/// A borderless, non-activating panel that floats just above the Dock on every Space, including
/// full-screen ones. It can never become key or main, so clicking it never takes focus from the field
/// you are dictating into (A2).
final class FlowBarPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A hosting view that takes the first click even though its panel is never key, so a click on the bar
/// starts hands-free on the first press (D2) instead of being swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Places the panel, keeps it on the right screen, passes clicks through everywhere except the bar,
/// lets the bar be dragged, and hides it for an hour on request.
@MainActor
public final class FlowBarController {
    public let model: FlowBarModel
    let panel = FlowBarPanel()
    private var mouseMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var hideTimer: Timer?
    private var screen: NSScreen?
    private var dragStart: (mouse: NSPoint, offset: CGSize)?

    static let offsetKey = "murmur.flowBarOffset"
    var offset: CGSize {
        get {
            let d = UserDefaults.standard.dictionary(forKey: Self.offsetKey)
            return CGSize(width: d?["x"] as? Double ?? 0, height: d?["y"] as? Double ?? 0)
        }
        set { UserDefaults.standard.set(["x": newValue.width, "y": newValue.height], forKey: Self.offsetKey) }
    }

    public init(model: FlowBarModel) {
        self.model = model
        let host = FirstMouseHostingView(rootView: FlowBarView(model: model).gesture(dragGesture))
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        layout()
        panel.orderFrontRegardless()
        observe()
        trackChanges()
    }

    // MARK: Placement

    /// The panel never resizes (resizing a window jitters); it is as large as the largest state, and
    /// the content animates inside it (§5.1).
    var canvasSize: CGSize { Self.canvas }

    /// The panel's fixed size (also used by the snapshot tool): the widest card, and the pill with the
    /// tallest card above it.
    public static var canvas: CGSize {
        let t = LiveTokens.shared.value
        let margin = FlowGeometry.canvasMargin
        let width = max(t.noticeWidth, FlowGeometry.toastMaxWidth, t.handsFreeWidth)
        let above = max(FlowGeometry.alertMaxHeight, t.noticeHeight, t.tooltipHeight)
        return CGSize(width: (width + margin * 2).rounded(.up), height: (t.activeHeight + t.tooltipGap + above + margin * 2).rounded(.up))
    }

    /// Bottom-center point the bar sits on: just above the Dock in the visible frame of the screen
    /// holding the focused window, plus any offset the user dragged it to.
    func anchor(on screen: NSScreen) -> NSPoint {
        let t = LiveTokens.shared.value
        let visible = screen.visibleFrame
        let full = screen.frame
        // A visible frame that reaches the bottom edge means no Dock at the bottom: a full-screen app,
        // an auto-hidden Dock, or a Dock on the side.
        let noBottomDock = visible.minY <= full.minY + 1
        let lift = noBottomDock ? t.fullScreenLift : 0
        let sideOffset = visible.minX > full.minX + 1 ? t.dockSideOffset : (visible.maxX < full.maxX - 1 ? -t.dockSideOffset : 0)
        return NSPoint(x: visible.midX + sideOffset + offset.width, y: visible.minY + t.bottomMargin + lift + offset.height)
    }

    public func layout() {
        let screen = self.screen ?? Self.screenOfFocusedWindow() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let a = anchor(on: screen)
        let size = canvasSize
        let frame = NSRect(x: (a.x - size.width / 2).rounded(), y: (a.y - FlowGeometry.canvasMargin).rounded(), width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        updateMouseHandling()
    }

    /// Re-picks the screen (call when a dictation starts, so the bar follows the window you dictate into).
    public func followFocusedScreen() {
        screen = Self.screenOfFocusedWindow()
        layout()
    }

    static func screenOfFocusedWindow() -> NSScreen? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var app: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success, let app else { return nil }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return nil }
        var position: CFTypeRef?, size: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &size)
        var p = CGPoint.zero, s = CGSize.zero
        if let position { AXValueGetValue(position as! AXValue, .cgPoint, &p) }
        if let size { AXValueGetValue(size as! AXValue, .cgSize, &s) }
        // AX uses top-left origin on the primary screen; NSScreen uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let center = NSPoint(x: p.x + s.width / 2, y: primaryHeight - (p.y + s.height / 2))
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    // MARK: Mouse

    /// The pill's mouse target in screen coordinates (the hover pill's area while idle).
    var pillRect: NSRect {
        let target = model.pillTarget
        let frame = panel.frame
        return NSRect(x: frame.midX - target.width / 2, y: frame.minY + FlowGeometry.canvasMargin - FlowGeometry.hoverTargetSlop,
                      width: target.width, height: target.height)
    }

    /// Where the tooltip or card starts: the pill's drawn top plus the gap (no gap without a pill).
    private var aboveY: CGFloat {
        let t = LiveTokens.shared.value
        let pill = model.pillSize.height
        return panel.frame.minY + FlowGeometry.canvasMargin + (pill > 0 ? pill + t.tooltipGap : 0)
    }

    /// The alert's or toast's rectangle, while one shows.
    var cardRect: NSRect {
        guard model.notice != nil else { return .zero }
        let size = model.cardSize
        return NSRect(x: panel.frame.midX - size.width / 2, y: aboveY, width: size.width, height: size.height)
    }

    var tooltipRect: NSRect {
        let size = model.tooltipSize
        guard size != .zero else { return .zero }
        return NSRect(x: panel.frame.midX - size.width / 2, y: aboveY, width: size.width, height: size.height)
    }

    /// Only the pill, the tooltip and the card take mouse events; the rest of the canvas passes clicks
    /// through. Also drives the pill's hover and pauses a toast's countdown under the pointer.
    func updateMouseHandling() {
        let mouse = NSEvent.mouseLocation
        let overPill = model.pill != .none && pillRect.contains(mouse)
        let overCard = cardRect.contains(mouse)
        let overTip = tooltipRect.contains(mouse)
        model.setHovering(overPill || (overTip && model.pill == .hover))
        if model.notice != nil, model.countdownPaused != overCard { model.countdownPaused = overCard }
        let inside = overPill || overCard || overTip
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    private func observe() {
        let move: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: move, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseHandling() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: move, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouseHandling() }
            return event
        }) { mouseMonitors.append(local) }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screen = nil
                self?.layout()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layout()
                self?.panel.orderFrontRegardless()
            }
        })
    }

    /// Re-layout whenever the displayed state or the tokens change.
    private func trackChanges() {
        withObservationTracking {
            _ = model.displayed
            _ = model.cardSize
            _ = LiveTokens.shared.value
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layout()
                self?.trackChanges()
            }
        }
    }

    // MARK: Drag

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let mouse = NSEvent.mouseLocation
                    if self.dragStart == nil { self.dragStart = (mouse, self.offset) }
                    guard let start = self.dragStart else { return }
                    self.offset = CGSize(width: start.offset.width + mouse.x - start.mouse.x, height: start.offset.height + mouse.y - start.mouse.y)
                    self.layout()
                }
            }
            .onEnded { [weak self] _ in
                MainActor.assumeIsolated { self?.dragStart = nil }
            }
    }

    public func resetPosition() {
        offset = .zero
        screen = nil
        layout()
    }

    // MARK: Hide for an hour (A6)

    public func hide(for interval: TimeInterval) {
        model.hiddenUntil = Date().addingTimeInterval(interval)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.unhide() }
        }
    }

    public func unhide() {
        hideTimer?.invalidate()
        model.hiddenUntil = nil
    }

    /// The panel, for design snapshots.
    public var panelForSnapshots: NSWindow { panel }

    /// The pill's center in screen coordinates, for the automated focus test.
    public var barCenter: NSPoint { NSPoint(x: pillRect.midX, y: pillRect.midY) }

    /// Re-evaluates click-through now (the test moves the pointer, then clicks without waiting for the
    /// mouse-moved monitor).
    public func refreshMouseHandling() { updateMouseHandling() }
}
