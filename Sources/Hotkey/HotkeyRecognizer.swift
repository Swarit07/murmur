import Foundation

/// Modifier keys the recognizer tracks. Fn is the Globe key on Apple keyboards.
public enum ModifierKey: String, Sendable, Codable, CaseIterable, Hashable {
    case fn, control, option, command, shift
}

/// One keyboard event, already decoded from the event tap. Times are monotonic nanoseconds.
public enum KeyEvent: Sendable, Equatable {
    /// The set of modifiers held changed. `held` is the full set after the change.
    case modifiers(held: Set<ModifierKey>, time: UInt64)
    /// A non-modifier key went down. `keyCode` is the virtual key code.
    case keyDown(keyCode: Int, time: UInt64)
}

/// What the dictation controller should do.
public enum HotkeyAction: Sendable, Equatable {
    /// Push-to-talk went down: start recording right away (it may still be discarded).
    case startHold
    /// Push-to-talk released after a real hold: finish and insert.
    case stopHold
    /// Start a hands-free dictation (double-tap or the hands-free chord).
    case startHandsFree
    /// Keep the current recording but switch it to hands-free (the chord pressed during a hold).
    case convertToHandsFree
    /// Finish a hands-free dictation and insert.
    case stopHandsFree
    /// Stop and insert nothing, keeping a History entry (Esc, or a rapid-tap guard).
    case cancel
    /// Stop and drop silently, no History entry: the key was a quick tap or part of another shortcut.
    case discard
}

public struct HotkeyConfiguration: Sendable, Codable, Equatable {
    /// Modifiers that, held together and alone, mean push-to-talk.
    public var pushToTalk: Set<ModifierKey>
    /// Modifiers plus a key for hands-free (default Fn+Space).
    public var handsFreeModifiers: Set<ModifierKey>
    public var handsFreeKey: Int
    /// Another key within this window after push-to-talk goes down cancels it (Fn+arrow, Fn+F5).
    public var otherKeyWindowNs: UInt64
    /// A press shorter than this is a tap, not a hold.
    public var tapMaxNs: UInt64
    /// Two taps closer than this start hands-free; a further tap this soon after starting cancels.
    public var doubleTapWindowNs: UInt64

    public static let spaceKeyCode = 49
    public static let escapeKeyCode = 53

    public init(
        pushToTalk: Set<ModifierKey> = [.fn],
        handsFreeModifiers: Set<ModifierKey> = [.fn],
        handsFreeKey: Int = HotkeyConfiguration.spaceKeyCode,
        otherKeyWindowNs: UInt64 = 250_000_000,
        tapMaxNs: UInt64 = 300_000_000,
        doubleTapWindowNs: UInt64 = 500_000_000
    ) {
        self.pushToTalk = pushToTalk
        self.handsFreeModifiers = handsFreeModifiers
        self.handsFreeKey = handsFreeKey
        self.otherKeyWindowNs = otherKeyWindowNs
        self.tapMaxNs = tapMaxNs
        self.doubleTapWindowNs = doubleTapWindowNs
    }

    /// Fn (Globe) on Apple keyboards.
    public static let appleKeyboard = HotkeyConfiguration()
    /// Ctrl+Option, and Ctrl+Option+Space for hands-free, for keyboards without Fn.
    public static let otherKeyboard = HotkeyConfiguration(pushToTalk: [.control, .option], handsFreeModifiers: [.control, .option])
}

/// Turns key events into dictation actions. Pure and deterministic, so every rule is unit-tested
/// with recorded event sequences (spec D1, D2, D3, D4).
public struct HotkeyRecognizer: Sendable {
    enum State: Equatable {
        case idle
        /// Push-to-talk is down and recording started at `since`.
        case holding(since: UInt64)
        /// Push-to-talk is still down but this press no longer means dictation.
        case suppressed
        /// A hands-free dictation runs. `startedAt` drives the rapid-tap guard. `pttDown` tracks the key.
        case handsFree(startedAt: UInt64, pttDown: Bool)
    }

    public var configuration: HotkeyConfiguration
    var state: State = .idle
    /// When the last quick tap ended, for double-tap detection.
    var lastTapUp: UInt64?
    var held: Set<ModifierKey> = []

    public init(configuration: HotkeyConfiguration = .appleKeyboard) {
        self.configuration = configuration
    }

    /// The controller calls this when a dictation ends for any other reason (stop icon, error, finished),
    /// so the recognizer does not think hands-free is still running.
    public mutating func reset() {
        state = configuration.pushToTalk.isSubset(of: held) ? .suppressed : .idle
        lastTapUp = nil
    }

    public mutating func handle(_ event: KeyEvent) -> [HotkeyAction] {
        switch event {
        case .modifiers(let newHeld, let time):
            let old = held
            held = newHeld
            return modifiersChanged(from: old, to: newHeld, time: time)
        case .keyDown(let code, let time):
            return keyDown(code, time: time)
        }
    }

    private var pttHeld: Bool { held == configuration.pushToTalk }

    private mutating func modifiersChanged(from old: Set<ModifierKey>, to new: Set<ModifierKey>, time: UInt64) -> [HotkeyAction] {
        let wasPTT = old == configuration.pushToTalk
        let isPTT = new == configuration.pushToTalk
        let pttKeysDown = configuration.pushToTalk.isSubset(of: new)

        switch state {
        case .idle:
            guard isPTT, !wasPTT else { return [] }
            if let lastTapUp, time &- lastTapUp <= configuration.doubleTapWindowNs {
                self.lastTapUp = nil
                state = .handsFree(startedAt: time, pttDown: true)
                return [.startHandsFree]
            }
            state = .holding(since: time)
            return [.startHold]

        case .holding(let since):
            if pttKeysDown && !isPTT {
                // Another modifier joined (Fn+Cmd…). Early on, that is a different shortcut.
                if time &- since <= configuration.otherKeyWindowNs {
                    state = .suppressed
                    return [.discard]
                }
                return []
            }
            guard !pttKeysDown else { return [] }
            // Released.
            if time &- since < configuration.tapMaxNs {
                lastTapUp = time
                state = .idle
                return [.discard]
            }
            state = .idle
            return [.stopHold]

        case .suppressed:
            if !pttKeysDown { state = .idle }
            return []

        case .handsFree(let startedAt, let pttDown):
            if isPTT && !pttDown {
                state = .handsFree(startedAt: startedAt, pttDown: true)
                // A further tap right after a double-tap start means the user is mashing the key: cancel (D4).
                if time &- startedAt <= configuration.doubleTapWindowNs {
                    state = .suppressed
                    return [.cancel]
                }
                state = .suppressed
                return [.stopHandsFree]
            }
            if !pttKeysDown && pttDown {
                state = .handsFree(startedAt: startedAt, pttDown: false)
            }
            return []
        }
    }

    private mutating func keyDown(_ code: Int, time: UInt64) -> [HotkeyAction] {
        if code == HotkeyConfiguration.escapeKeyCode {
            // Esc also cancels while the controller is still transcribing or cleaning up, after the key
            // was released, so it is always reported. The controller ignores it when nothing is running.
            switch state {
            case .holding: state = .suppressed
            case .handsFree(_, let down): state = down ? .suppressed : .idle
            default: break
            }
            return [.cancel]
        }
        let chordHeld = held == configuration.handsFreeModifiers && code == configuration.handsFreeKey
        switch state {
        case .idle:
            if chordHeld {
                state = .handsFree(startedAt: time, pttDown: configuration.pushToTalk.isSubset(of: held))
                return [.startHandsFree]
            }
            lastTapUp = nil
            return []
        case .holding(let since):
            if chordHeld {
                state = .handsFree(startedAt: since, pttDown: true)
                return [.convertToHandsFree]
            }
            if time &- since <= configuration.otherKeyWindowNs {
                state = .suppressed
                return [.discard]
            }
            return []
        case .handsFree(let startedAt, let down):
            if chordHeld {
                // The chord again within the window right after starting cancels (D4); later it stops.
                state = down ? .suppressed : .idle
                return time &- startedAt <= configuration.doubleTapWindowNs ? [.cancel] : [.stopHandsFree]
            }
            return []
        case .suppressed:
            return []
        }
    }
}
