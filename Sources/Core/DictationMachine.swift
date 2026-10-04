import Foundation

public enum DictationMode: String, Sendable, Codable, Equatable {
    case hold
    case handsFree = "hands-free"
    case command
}

public enum DictationErrorKind: String, Sendable, Codable, Equatable {
    case transcriptionFailed
    case pasteFailed
    case noTextBox
}

public enum DictationState: Sendable, Equatable {
    case idle
    case recording(DictationMode)
    case transcribing
    case cleaning
    case inserting
    case cancelled
    /// Error states keep the text so nothing is lost. `nil` only when transcription itself failed.
    case error(DictationErrorKind, text: String?)

    public var isBusy: Bool {
        switch self {
        case .idle: false
        default: true
        }
    }

    public var name: String {
        switch self {
        case .idle: "idle"
        case .recording(let mode): "recording.\(mode.rawValue)"
        case .transcribing: "transcribing"
        case .cleaning: "cleaning"
        case .inserting: "inserting"
        case .cancelled: "cancelled"
        case .error(let kind, _): "error.\(kind.rawValue)"
        }
    }
}

public enum DictationEvent: Sendable, Equatable {
    /// Push-to-talk key down, hands-free start, or a click on the Flow Bar.
    case start(DictationMode)
    /// Key up or stop.
    case stop
    /// The clip was under the minimum length or had no speech.
    case discard
    case transcribed(String)
    case transcriptionFailed
    case cleaned(String)
    case inserted
    case insertionFailed(DictationErrorKind, text: String)
    /// Esc or the X on the Flow Bar.
    case cancel
    /// Dismissing a notice or an error.
    case dismiss
}

/// Every transition is a pure function. `nil` means the event is ignored in that state
/// (for example a key press while a dictation is busy).
public enum DictationMachine {
    public static func next(_ state: DictationState, on event: DictationEvent) -> DictationState? {
        switch (state, event) {
        case (.idle, .start(let mode)):
            return .recording(mode)

        case (.recording, .stop):
            return .transcribing
        case (.recording, .discard):
            return .idle

        case (.recording, .cancel), (.transcribing, .cancel), (.cleaning, .cancel):
            return .cancelled

        case (.transcribing, .transcribed):
            return .cleaning
        case (.transcribing, .transcriptionFailed):
            return .error(.transcriptionFailed, text: nil)
        case (.transcribing, .discard):
            return .idle

        case (.cleaning, .cleaned):
            return .inserting

        case (.inserting, .inserted):
            return .idle
        case (.inserting, .insertionFailed(let kind, let text)):
            return .error(kind, text: text)

        case (.cancelled, .dismiss), (.error, .dismiss):
            return .idle

        default:
            return nil
        }
    }
}

/// Holds the current state and logs every accepted transition as a signpost event.
public final class DictationStateHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: DictationState = .idle

    public init() {}

    public var state: DictationState {
        lock.withLock { _state }
    }

    /// Applies the event. Returns the new state, or `nil` when the event was ignored.
    @discardableResult
    public func send(_ event: DictationEvent) -> DictationState? {
        let (from, to): (DictationState, DictationState?) = lock.withLock {
            let from = _state
            let to = DictationMachine.next(from, on: event)
            if let to { _state = to }
            return (from, to)
        }
        if let to {
            Signposts.transition(from: from.name, to: to.name)
        }
        return to
    }
}
