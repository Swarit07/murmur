import Core
import Foundation
import SwiftUI

/// A notice the bar shows above the pill: an alert (with a title and two buttons) or a toast (one line).
public struct FlowBarNotice: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case pasteError, transcriptionError, noTextBox, cancelled, info, micError
        /// The recording had no speech in it (§5.1 "No audio").
        case noAudio
        /// A6: the bar was just hidden for an hour; Undo brings it back.
        case hidden
        /// S2: a word you corrected could go in the dictionary.
        case suggestion
    }

    public enum Action: String, Sendable {
        case retry, undo, openHistory, dismiss, pasteLast, add, selectMicrophone, troubleshoot
    }

    /// Alerts carry a title, a body and two buttons; toasts are one line with at most two actions.
    public enum Style: Sendable { case alert, toast }

    public var kind: Kind
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var style: Style {
        switch kind {
        case .transcriptionError, .micError, .noAudio: .alert
        case .pasteError, .noTextBox, .cancelled, .info, .hidden, .suggestion: .toast
        }
    }

    /// Buttons per kind (spec section 6 state table; §5.1 for no audio).
    public var actions: [Action] {
        switch kind {
        case .pasteError: [.dismiss]
        case .transcriptionError, .micError: [.retry, .dismiss]
        case .noAudio: [.selectMicrophone, .troubleshoot]
        case .noTextBox: [.dismiss]
        case .cancelled: [.undo, .openHistory]
        case .info: [.dismiss]
        case .hidden: [.undo]
        case .suggestion: [.add, .dismiss]
        }
    }

    /// Seconds before it dismisses itself, or nil to stay until dismissed.
    @MainActor public var countdown: Double? {
        let t = LiveTokens.shared.value
        switch kind {
        case .cancelled: return t.cancelledToastDuration
        case .noTextBox, .info, .hidden: return t.noticeDuration
        case .suggestion: return t.noticeDuration * 2
        case .pasteError, .transcriptionError, .micError, .noAudio: return nil
        }
    }
}

public enum FlowBarState: Equatable, Sendable {
    case hidden
    case idle
    case listening(handsFree: Bool)
    case processing
    case inserted
    case notice(FlowBarNotice)

    public var name: String {
        switch self {
        case .hidden: "Hidden"
        case .idle: "Idle"
        case .listening(let handsFree): handsFree ? "Listening, hands-free" : "Listening, hold"
        case .processing: "Processing"
        case .inserted: "Inserted"
        case .notice(let notice): "Notice: \(notice.kind.rawValue)"
        }
    }
}

/// What the pill itself shows; a notice sits above an idle (or hidden) pill.
public enum FlowPill: Equatable, Sendable {
    case none, idle, hover, hold, handsFree, processing, inserted
}

/// What the Flow Bar shows and what it reports back. The app maps the dictation controller's status
/// onto `state`; the debug menu can force any state.
@MainActor
@Observable
public final class FlowBarModel {
    /// Command Mode is listening or working (the bar draws in clay).
    public var command = false

    /// The state from the dictation controller.
    public var state: FlowBarState = .idle {
        didSet { stateChanged(from: oldValue) }
    }

    /// A state forced from the debug menu; wins over `state` until cleared.
    public var forced: FlowBarState? {
        didSet { refreshDisplayed() }
    }

    /// What is on screen: the forced state, or the controller's state with transient states applied.
    public private(set) var displayed: FlowBarState = .idle {
        didSet { if displayed != .idle { hideTooltip() } }
    }

    /// The pointer is over the pill (set by the panel's mouse tracking).
    public private(set) var hovering = false
    /// The tooltip above the hovered idle pill, shown after `tooltipDelay`.
    public private(set) var tooltipVisible = false
    /// The push-to-talk shortcut as the tooltip names it, for example "⌃ Ctrl".
    public var shortcutLabel = "fn"
    public var tooltipText: String { "Click or hold \(shortcutLabel) to start dictating" }
    /// The input device's name, for the no-audio alert.
    public var microphoneName = "built-in"
    /// The microphone level, read once per frame while listening.
    public var levelSource: MicLevelSource?

    /// Countdown progress for notices, 1 → 0.
    public private(set) var countdownRemaining: Double = 1
    public var countdownPaused = false
    /// Show the idle pill when nothing is happening (A5, "Show Flow Bar at all times").
    public var showAtAllTimes = true {
        didSet { refreshDisplayed() }
    }
    public var hiddenUntil: Date? {
        didSet { refreshDisplayed() }
    }
    /// The alert's or toast's measured size, reported by the view for hit-testing.
    public internal(set) var cardSize: CGSize = .zero

    public var onClick: (() -> Void)?
    /// Taps the bar received, for the focus test's diagnostics.
    public private(set) var taps = 0
    func noteTap() { taps += 1 }
    public var onStop: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onAction: ((FlowBarNotice.Action, FlowBarNotice) -> Void)?
    public var onMenu: ((FlowBarMenuItem) -> Void)?

    private var transientTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var tooltipTask: Task<Void, Never>?

    public init() {}

    func resolved(_ s: FlowBarState) -> FlowBarState {
        if let hiddenUntil, hiddenUntil > Date(), s == .idle { return .hidden }
        if s == .idle && !showAtAllTimes { return .hidden }
        return s
    }

    private func refreshDisplayed() {
        displayed = forced ?? resolved(state)
    }

    private func stateChanged(from old: FlowBarState) {
        transientTask?.cancel()
        countdownTask?.cancel()
        refreshDisplayed()
        let tokens = LiveTokens.shared.value
        switch state {
        case .inserted:
            // Draw the check, hold it, then shrink back to idle unless something else happened meanwhile.
            transientTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(tokens.checkDraw + tokens.confirmationHold))
                guard let self, !Task.isCancelled, self.state == .inserted else { return }
                self.displayed = self.forced ?? self.resolved(.idle)
            }
        case .notice(let notice):
            if let total = notice.countdown { startCountdown(total, notice: notice) }
        default:
            break
        }
    }

    private func startCountdown(_ total: Double, notice: FlowBarNotice) {
        countdownRemaining = 1
        countdownPaused = false
        countdownTask = Task { [weak self] in
            let step = 0.05
            var left = total
            while left > 0 {
                try? await Task.sleep(for: .seconds(step))
                guard let self, !Task.isCancelled else { return }
                if !self.countdownPaused { left -= step }
                self.countdownRemaining = max(0, left / total)
            }
            guard let self, !Task.isCancelled, self.state == .notice(notice) else { return }
            self.onAction?(.dismiss, notice)
        }
    }

    // MARK: Hover and tooltip

    /// The pointer entered or left the pill. The tooltip follows after its delay, only over the idle pill.
    public func setHovering(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        tooltipTask?.cancel()
        guard on, displayed == .idle else { return hideTooltip() }
        let delay = LiveTokens.shared.value.tooltipDelay / max(0.05, UIDebug.shared.timeScale)
        tooltipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.hovering, self.displayed == .idle else { return }
            self.tooltipVisible = true
        }
    }

    private func hideTooltip() {
        tooltipTask?.cancel()
        if tooltipVisible { tooltipVisible = false }
    }

    /// Shows a gallery entry: its state, with the pointer over the pill (and the tooltip up) if it asks.
    public func force(_ entry: FlowBarGalleryEntry?) {
        forced = entry?.state
        hovering = entry?.hover ?? false
        tooltipTask?.cancel()
        tooltipVisible = entry?.hover ?? false
    }

    // MARK: Geometry

    public var notice: FlowBarNotice? {
        if case .notice(let notice) = displayed { notice } else { nil }
    }

    public var pill: FlowPill {
        switch displayed {
        case .hidden: .none
        case .idle: hovering ? .hover : .idle
        case .listening(let handsFree): handsFree ? .handsFree : .hold
        case .processing: .processing
        case .inserted: .inserted
        case .notice: resolved(.idle) == .hidden ? .none : (hovering ? .hover : .idle)
        }
    }

    /// The pill's drawn size.
    public var pillSize: CGSize {
        let t = LiveTokens.shared.value
        switch pill {
        case .none: return .zero
        case .idle: return CGSize(width: t.idleWidth, height: t.idleHeight)
        case .hover: return CGSize(width: t.hoverWidth, height: t.activeHeight)
        case .hold, .processing, .inserted: return CGSize(width: t.activeWidth, height: t.activeHeight)
        case .handsFree: return CGSize(width: t.handsFreeWidth, height: t.activeHeight)
        }
    }

    /// The pill's mouse target: the idle pill is tiny, so it answers over the hover pill's area.
    public var pillTarget: CGSize {
        let t = LiveTokens.shared.value
        let slop = V1Flow.hoverTargetSlop * 2
        switch pill {
        case .none: return .zero
        case .idle, .hover: return CGSize(width: t.hoverWidth + slop, height: t.activeHeight + slop)
        default: return CGSize(width: pillSize.width + slop, height: pillSize.height + slop)
        }
    }

    /// The tooltip's size, for hit-testing (its width follows the text).
    public var tooltipSize: CGSize {
        guard tooltipVisible else { return .zero }
        let t = LiveTokens.shared.value
        let font = V1Type.nsFont(V1Type.flowText)
        let width = (tooltipText as NSString).size(withAttributes: [.font: font]).width + V1Flow.tooltipPaddingH * 2
        return CGSize(width: width.rounded(.up), height: t.tooltipHeight)
    }

    // MARK: Levels

    /// The level to draw now, 0…1. While a state is forced from the debug menu or the gallery, a made-up
    /// voice stands in for the microphone so the bars can be judged without speaking.
    func level(at time: TimeInterval) -> Double {
        let t = LiveTokens.shared.value
        if forced != nil { return Self.syntheticVoice(at: time) }
        guard let db = levelSource?.read() else { return 0 }
        return min(1, max(0, (Double(db) - t.waveformFloorDb) / (t.waveformCeilingDb - t.waveformFloorDb)))
    }

    /// Syllable-like bursts: a fast carrier under a slow phrase envelope.
    static func syntheticVoice(at time: TimeInterval) -> Double {
        let syllable = abs(sin(time * 9.0)) * (0.55 + 0.45 * sin(time * 2.3))
        let phrase = 0.65 + 0.35 * sin(time * 0.9)
        return min(1, max(0, syllable * phrase))
    }
}

/// A Flow Bar state as the debug menu, the design gallery and the snapshot tool show it.
public struct FlowBarGalleryEntry: Sendable {
    public let name: String
    public let state: FlowBarState
    /// The pointer is over the pill, with the tooltip showing.
    public let hover: Bool

    init(_ name: String, _ state: FlowBarState, hover: Bool = false) {
        self.name = name
        self.state = state
        self.hover = hover
    }
}

extension FlowBarState {
    /// Every state the debug menu, the design gallery and the snapshot tool show.
    public static let gallery: [FlowBarGalleryEntry] = [
        .init("idle", .idle), .init("idle-hover", .idle, hover: true), .init("hidden", .hidden),
        .init("listening-hold", .listening(handsFree: false)), .init("listening-handsfree", .listening(handsFree: true)),
        .init("processing", .processing), .init("inserted", .inserted),
        .init("paste-error", .notice(FlowBarNotice(kind: .pasteError, message: "Couldn't paste. The text is on the clipboard."))),
        .init("transcription-error", .notice(FlowBarNotice(kind: .transcriptionError, message: "Transcription failed. The audio is saved in History."))),
        .init("no-audio", .notice(FlowBarNotice(kind: .noAudio, message: ""))),
        .init("mic-error", .notice(FlowBarNotice(kind: .micError, message: "The microphone is unavailable (MacBook Pro Microphone). Check it is connected, then Retry."))),
        .init("no-text-box", .notice(FlowBarNotice(kind: .noTextBox, message: "No text box had focus. Click one and press ⌃⌘V to paste the last transcript."))),
        .init("cancelled", .notice(FlowBarNotice(kind: .cancelled, message: "Cancelled"))),
        .init("info", .notice(FlowBarNotice(kind: .info, message: "Stopped at the 20-minute limit."))),
        .init("hidden-undo", .notice(FlowBarNotice(kind: .hidden, message: "Flow Bar hidden for an hour."))),
        .init("suggestion", .notice(FlowBarNotice(kind: .suggestion, message: "Add “Siobhan” to your dictionary?"))),
    ]
}

/// Right-click menu entries.
public enum FlowBarMenuItem: String, CaseIterable, Sendable {
    case pasteLast = "Paste last transcript"
    case copyLast = "Copy last transcript"
    case hideForHour = "Hide Flow Bar for 1 hour"
    case resetPosition = "Reset Flow Bar position"
    case openHistory = "Open History"
    case settings = "Settings…"
}
