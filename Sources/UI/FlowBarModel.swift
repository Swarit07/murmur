import Core
import Foundation
import SwiftUI

/// A notice the bar shows in place of the pill (UI_REDESIGN.md v2 §5.1): a toast or an alert card.
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
        case retry, undo, openHistory, dismiss, pasteLast, add, switchMicrophone, testMic
    }

    public var kind: Kind
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// Buttons per kind, primary first (§5.1; SPEC §6 for the kinds the board doesn't show).
    public var actions: [Action] {
        switch kind {
        case .pasteError: []
        case .transcriptionError, .micError: [.retry]
        case .noAudio: [.switchMicrophone, .testMic]
        case .noTextBox, .info: [.dismiss]
        case .cancelled: [.undo, .openHistory]
        case .hidden: [.undo]
        case .suggestion: [.add, .dismiss]
        }
    }

    /// Seconds before it dismisses itself, or nil to stay until dismissed (§5.1, §6.1).
    @MainActor public var countdown: Double? {
        let t = LiveTokens.shared.value
        switch kind {
        case .cancelled: return t.cancelledToastDuration
        case .pasteError: return t.pasteToastDuration
        case .transcriptionError, .micError, .noAudio: return t.alertSticky
        case .info, .hidden: return t.alertSticky
        case .suggestion: return t.alertSticky * 2
        case .noTextBox: return nil
        }
    }

    /// Only the cancelled toast draws its countdown as a ring (§5.1 #7); the others just expire.
    public var showsRing: Bool { kind == .cancelled }
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

/// What the bar's one surface shows: the pill in a state, or a card in its place.
public enum FlowSurface: Equatable, Sendable {
    case none, idle, hover, hold, handsFree, processing, inserted
    case card(FlowBarNotice)

    /// A stable identity for transitions and animation values.
    public var id: String {
        switch self {
        case .card(let notice): "card-" + notice.kind.rawValue
        default: "\(self)"
        }
    }
}

/// What the Flow Bar shows and what it reports back. The app maps the dictation controller's status
/// onto `state`; the debug menu can force any state.
@MainActor
@Observable
public final class FlowBarModel {
    /// Command Mode is listening or working.
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
        didSet { displayedChanged(from: oldValue) }
    }

    /// The pointer is over the pill (set by the panel's mouse tracking).
    public private(set) var hovering = false
    /// The tooltip above the hovered idle pill, shown after `tooltipDelay`.
    public private(set) var tooltipVisible = false
    /// The push-to-talk key as the tooltip shows it in its key cap, for example "fn" or "⌃ Ctrl".
    public var shortcutLabel = "fn"
    public var tooltipText: String { "Hold \(shortcutLabel) to dictate" }
    /// The input device's name, for the no-audio card.
    public var microphoneName = "Built-in Microphone"
    /// Words in the text just inserted ("Inserted · 24 words"); nil hides the count.
    public var insertedWords: Int?
    /// The microphone level, read once per frame while listening.
    public var levelSource: MicLevelSource?
    /// When the current recording started, for the hands-free timer.
    public private(set) var listeningSince: Date?
    /// The idle pill fades after a while of nothing happening (§6.1 `bar.idleFade`).
    public private(set) var idleFaded = false

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
    private var fadeTask: Task<Void, Never>?

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
        if case .listening = state {
            if listeningSince == nil { listeningSince = Date() }
        } else {
            listeningSince = nil
        }
        refreshDisplayed()
        let tokens = LiveTokens.shared.value
        switch state {
        case .inserted:
            // Draw the check, hold it, then shrink back to idle unless something else happened meanwhile.
            transientTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(tokens.checkDraw + tokens.insertedHold))
                guard let self, !Task.isCancelled, self.state == .inserted else { return }
                self.displayed = self.forced ?? self.resolved(.idle)
            }
        case .notice(let notice):
            if let total = notice.countdown { startCountdown(total, notice: notice) }
        default:
            break
        }
    }

    private func displayedChanged(from old: FlowBarState) {
        if displayed != .idle { hideTooltip() }
        // The idle pill fades after a quiet spell; anything else (or hovering) brings it back.
        fadeTask?.cancel()
        if idleFaded { idleFaded = false }
        if displayed == .idle && !hovering { scheduleFade() }
    }

    private func scheduleFade() {
        let delay = LiveTokens.shared.value.idleFadeDelay
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.displayed == .idle, !self.hovering else { return }
            self.idleFaded = true
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

    /// The pointer entered or left the pill. Over the idle pill it grows to the hover size, and the
    /// tooltip follows after its delay.
    public func setHovering(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        tooltipTask?.cancel()
        fadeTask?.cancel()
        if on {
            idleFaded = false
        } else if displayed == .idle {
            scheduleFade()
        }
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
        if let elapsed = entry?.elapsed {
            listeningSince = Date().addingTimeInterval(-elapsed)
        } else if case .listening? = forced {
            listeningSince = Date()
        }
        if let words = entry?.words { insertedWords = words }
        if let faded = entry?.faded { idleFaded = faded }
    }

    // MARK: Surface

    public var notice: FlowBarNotice? {
        if case .notice(let notice) = displayed { notice } else { nil }
    }

    public var surface: FlowSurface {
        switch displayed {
        case .hidden: .none
        case .idle: hovering ? .hover : .idle
        case .listening(let handsFree): handsFree ? .handsFree : .hold
        case .processing: .processing
        case .inserted: .inserted
        case .notice(let notice): .card(notice)
        }
    }

    /// The hands-free timer shows from `timerDelay` on.
    public func timerVisible(at date: Date) -> Bool {
        guard surface == .handsFree, let since = listeningSince else { return false }
        return date.timeIntervalSince(since) >= LiveTokens.shared.value.timerDelay
    }

    // MARK: Levels

    /// The level to draw now, 0…1 before gain. While a state is forced from the debug menu or the
    /// gallery, the wave draws a fixed preview level so it can be judged without speaking.
    func level(at time: TimeInterval) -> Double {
        let t = LiveTokens.shared.value
        if forced != nil { return WaveTokens.previewLevel }
        guard let db = levelSource?.read() else { return 0 }
        return min(1, max(0, (Double(db) - t.waveformFloorDb) / (t.waveformCeilingDb - t.waveformFloorDb)))
    }
}

/// A Flow Bar state as the debug menu, the design gallery and the snapshot tool show it.
public struct FlowBarGalleryEntry: Sendable {
    public let name: String
    public let state: FlowBarState
    /// The pointer is over the pill, with the tooltip showing.
    public let hover: Bool
    /// Seconds already recorded (shows the hands-free timer).
    public let elapsed: TimeInterval?
    /// The inserted word count.
    public let words: Int?
    /// The idle pill after its fade.
    public let faded: Bool?

    init(_ name: String, _ state: FlowBarState, hover: Bool = false, elapsed: TimeInterval? = nil, words: Int? = nil, faded: Bool? = nil) {
        self.name = name
        self.state = state
        self.hover = hover
        self.elapsed = elapsed
        self.words = words
        self.faded = faded
    }
}

extension FlowBarState {
    /// Every state the debug menu, the design gallery and the snapshot tool show (§5.1's twelve, plus
    /// the SPEC notices the board doesn't draw).
    public static let gallery: [FlowBarGalleryEntry] = [
        .init("01-idle", .idle, faded: false), .init("01-idle-faded", .idle, faded: true), .init("02-idle-hover", .idle, hover: true),
        .init("03-listening-hold", .listening(handsFree: false)), .init("04-listening-handsfree", .listening(handsFree: true), elapsed: 7),
        .init("05-processing", .processing), .init("06-inserted", .inserted, words: 24),
        .init("07-cancelled", .notice(FlowBarNotice(kind: .cancelled, message: "Cancelled"))),
        .init("08-paste-error", .notice(FlowBarNotice(kind: .pasteError, message: "Couldn't paste. The text is on the clipboard."))),
        .init("09-transcription-error", .notice(FlowBarNotice(kind: .transcriptionError, message: "Transcription failed. The audio is saved in History."))),
        .init("10-no-text-box", .notice(FlowBarNotice(kind: .noTextBox, message: "No text box had focus. Click one and press ⌃⌘V to paste the last transcript."))),
        .init("11-no-audio", .notice(FlowBarNotice(kind: .noAudio, message: ""))),
        .init("mic-error", .notice(FlowBarNotice(kind: .micError, message: "The microphone is unavailable (MacBook Pro Microphone). Check it is connected, then Retry."))),
        .init("info", .notice(FlowBarNotice(kind: .info, message: "Stopped at the 20-minute limit."))),
        .init("hidden-undo", .notice(FlowBarNotice(kind: .hidden, message: "Flow Bar hidden for an hour."))),
        .init("suggestion", .notice(FlowBarNotice(kind: .suggestion, message: "Add “Siobhan” to your dictionary?"))),
        .init("hidden", .hidden),
    ]
}

/// Right-click menu entries (§5.1 #12, a native menu). "Reset Flow Bar position" stays from SPEC
/// (the bar can be dragged).
public enum FlowBarMenuItem: String, CaseIterable, Sendable {
    case startHandsFree = "Start hands-free"
    case pasteLast = "Paste last transcript"
    case hideForHour = "Hide for 1 hour"
    case settings = "Settings…"
    case resetPosition = "Reset Flow Bar position"
}
