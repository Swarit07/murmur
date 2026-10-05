import Foundation
import SwiftUI

/// A notice the bar shows as a card: errors, cancelled, no text box.
public struct FlowBarNotice: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case pasteError, transcriptionError, noTextBox, cancelled, info, micError
    }

    public enum Action: String, Sendable {
        case retry, undo, openHistory, dismiss, pasteLast
    }

    public var kind: Kind
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// Buttons per kind (spec section 6 state table).
    public var actions: [Action] {
        switch kind {
        case .pasteError: [.dismiss]
        case .transcriptionError, .micError: [.retry, .dismiss]
        case .noTextBox: [.dismiss]
        case .cancelled: [.undo, .openHistory]
        case .info: [.dismiss]
        }
    }

    /// Seconds before it dismisses itself, or nil to stay until dismissed.
    @MainActor public var countdown: Double? {
        let t = LiveTokens.shared.value
        switch kind {
        case .cancelled: return t.cancelledToastDuration
        case .noTextBox, .info: return t.noticeDuration
        case .pasteError, .transcriptionError, .micError: return nil
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

/// What the Flow Bar shows and what it reports back. The app maps the dictation controller's status
/// onto `state`; the debug menu can force any state.
@MainActor
@Observable
public final class FlowBarModel {
    /// The state from the dictation controller.
    public var state: FlowBarState = .idle {
        didSet { stateChanged(from: oldValue) }
    }

    /// A state forced from the debug menu; wins over `state` until cleared.
    public var forced: FlowBarState? {
        didSet {
            if let forced, case .listening = forced { startFakeLevels() } else { stopFakeLevels() }
            displayed = forced ?? state
        }
    }

    /// What is on screen: the forced state, or the controller's state with transient states applied.
    public private(set) var displayed: FlowBarState = .idle

    /// Smoothed waveform heights, 0…1, oldest first.
    public private(set) var levels: [Double] = []
    /// Countdown progress for notices, 1 → 0.
    public private(set) var countdownRemaining: Double = 1
    public var countdownPaused = false
    /// Show the idle pill when nothing is happening (A5, "Show Flow Bar at all times").
    public var showAtAllTimes = true {
        didSet { displayed = forced ?? resolved(state) }
    }
    public var hiddenUntil: Date? {
        didSet { displayed = forced ?? resolved(state) }
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
    private var fakeLevelTask: Task<Void, Never>?
    private var smoothed: Double = 0
    private var lastLevelAt = Date.distantPast

    public init() {
        levels = Array(repeating: 0, count: max(1, LiveTokens.shared.value.waveformBars))
    }

    func resolved(_ s: FlowBarState) -> FlowBarState {
        if let hiddenUntil, hiddenUntil > Date(), s == .idle { return .hidden }
        if s == .idle && !showAtAllTimes { return .hidden }
        return s
    }

    private func stateChanged(from old: FlowBarState) {
        transientTask?.cancel()
        countdownTask?.cancel()
        if case .listening = state { resetLevels() }
        displayed = forced ?? resolved(state)
        let tokens = LiveTokens.shared.value
        switch state {
        case .inserted:
            // A brief confirmation, then back to idle unless something else happened meanwhile.
            transientTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(tokens.confirmationHold))
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

    // MARK: Waveform

    func resetLevels() {
        smoothed = 0
        levels = Array(repeating: 0, count: max(1, LiveTokens.shared.value.waveformBars))
    }

    /// Feeds one microphone level (dBFS). Throttled to the waveform frame rate.
    public func push(level dbfs: Float) {
        let t = LiveTokens.shared.value
        let target = min(1, max(0, (Double(dbfs) - t.waveformFloorDb) / (t.waveformCeilingDb - t.waveformFloorDb)))
        let k = target > smoothed ? t.waveformAttack : t.waveformRelease
        smoothed += (target - smoothed) * k
        let now = Date()
        guard now.timeIntervalSince(lastLevelAt) >= 1 / max(1, t.waveformFrameRate) else { return }
        lastLevelAt = now
        var next = levels
        if next.count != t.waveformBars { next = Array(repeating: 0, count: max(1, t.waveformBars)) }
        next.removeFirst()
        next.append(smoothed)
        levels = next
    }

    private func startFakeLevels() {
        fakeLevelTask?.cancel()
        fakeLevelTask = Task { [weak self] in
            var phase = 0.0
            while !Task.isCancelled {
                phase += 0.35
                let db = -40 + 22 * abs(sin(phase)) * (0.6 + 0.4 * sin(phase * 0.37))
                self?.push(level: Float(db))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopFakeLevels() {
        fakeLevelTask?.cancel()
        fakeLevelTask = nil
    }

    /// The size the bar wants for what it displays, from the tokens.
    public var barSize: CGSize {
        let t = LiveTokens.shared.value
        switch displayed {
        case .hidden: return .zero
        case .idle: return CGSize(width: t.idleWidth, height: t.idleHeight)
        case .listening(let handsFree): return CGSize(width: handsFree ? t.handsFreeWidth : t.activeWidth, height: t.activeHeight)
        case .processing, .inserted: return CGSize(width: t.activeWidth, height: t.activeHeight)
        case .notice: return CGSize(width: t.noticeWidth, height: t.noticeHeight)
        }
    }
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
