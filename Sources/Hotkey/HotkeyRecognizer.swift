import Foundation

/// Modifier keys the recognizer tracks. Fn is the Globe key on Apple keyboards.
public enum ModifierKey: String, Sendable, Codable, CaseIterable, Hashable, Comparable {
    case fn, control, option, command, shift

    public static func < (a: ModifierKey, b: ModifierKey) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }

    public var symbol: String {
        switch self {
        case .fn: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        case .shift: "⇧"
        }
    }
}

/// A user-chosen shortcut (D8): modifiers alone, a key with optional modifiers, a mouse button, or Caps Lock.
public enum Shortcut: Codable, Equatable, Hashable, Sendable {
    case modifiers(Set<ModifierKey>)
    case key(keyCode: Int, modifiers: Set<ModifierKey>)
    /// Mouse button number as AppKit counts them: 2 is the middle button, 3 and up are side buttons.
    case mouse(button: Int)
    case capsLock

    public var displayName: String {
        switch self {
        case .modifiers(let mods): mods.sorted().map(\.symbol).joined(separator: " ")
        case .key(let code, let mods): (mods.sorted().map(\.symbol) + [KeyNames.name(for: code)]).joined(separator: " ")
        case .mouse(let button): button == 2 ? "Middle mouse button" : "Mouse button \(button + 1)"
        case .capsLock: "Caps Lock"
        }
    }
}

/// One input event, already decoded from the event tap (and, for Caps Lock, from the keyboard HID).
/// Times are monotonic nanoseconds.
public enum KeyEvent: Sendable, Equatable {
    /// The set of modifiers held changed. `held` is the full set after the change.
    case modifiers(held: Set<ModifierKey>, time: UInt64)
    /// A non-modifier key went down (auto-repeat excluded) or up.
    case keyDown(keyCode: Int, time: UInt64)
    case keyUp(keyCode: Int, time: UInt64)
    case mouseDown(button: Int, time: UInt64)
    case mouseUp(button: Int, time: UInt64)
    case capsLock(down: Bool, time: UInt64)
}

/// What the dictation controller should do.
public enum HotkeyAction: Sendable, Equatable {
    /// Push-to-talk went down: start recording right away (it may still be discarded).
    case startHold
    /// Push-to-talk released after a real hold: finish and insert.
    case stopHold
    /// Start a hands-free dictation (double-tap or the hands-free shortcut).
    case startHandsFree
    /// Keep the current recording but switch it to hands-free (the hands-free shortcut during a hold).
    case convertToHandsFree
    /// Finish a hands-free dictation and insert.
    case stopHandsFree
    /// Stop and insert nothing, keeping a History entry (Esc, or a rapid-tap guard).
    case cancel
    /// Stop and drop silently, no History entry: the key was a quick tap or part of another shortcut.
    case discard
    /// Command Mode (M1): the Command shortcut went down; record a spoken instruction.
    case startCommand
    /// The Command shortcut joined a push-to-talk hold right away: keep recording, as a command.
    case convertToCommand
    /// The Command shortcut was released after a real hold: run the instruction.
    case stopCommand
}

public struct HotkeyConfiguration: Sendable, Codable, Equatable {
    public var pushToTalk: Shortcut
    public var handsFree: Shortcut
    /// Command Mode's shortcut, or nil while Command Mode is off (Settings › Experimental).
    public var command: Shortcut?
    /// Another key within this window after push-to-talk goes down cancels it (Fn+arrow, Fn+F5).
    public var otherKeyWindowNs: UInt64
    /// A press shorter than this is a tap, not a hold.
    public var tapMaxNs: UInt64
    /// Two taps closer than this start hands-free; a further tap this soon after starting cancels.
    public var doubleTapWindowNs: UInt64

    public static let spaceKeyCode = 49
    public static let escapeKeyCode = 53

    public init(
        pushToTalk: Shortcut = .modifiers([.fn]),
        handsFree: Shortcut = .key(keyCode: HotkeyConfiguration.spaceKeyCode, modifiers: [.fn]),
        command: Shortcut? = nil,
        otherKeyWindowNs: UInt64 = 250_000_000,
        tapMaxNs: UInt64 = 300_000_000,
        doubleTapWindowNs: UInt64 = 500_000_000
    ) {
        self.pushToTalk = pushToTalk
        self.handsFree = handsFree
        self.command = command
        self.otherKeyWindowNs = otherKeyWindowNs
        self.tapMaxNs = tapMaxNs
        self.doubleTapWindowNs = doubleTapWindowNs
    }

    /// Fn (Globe) and Fn+Space on Apple keyboards.
    public static let appleKeyboard = HotkeyConfiguration()
    /// Ctrl+Option and Ctrl+Option+Space for keyboards without Fn.
    public static let otherKeyboard = HotkeyConfiguration(
        pushToTalk: .modifiers([.control, .option]),
        handsFree: .key(keyCode: spaceKeyCode, modifiers: [.control, .option]))

    /// Command Mode's default: Fn+Control on Apple keyboards, Control+Option+Command otherwise.
    public static func defaultCommand(appleKeyboard: Bool) -> Shortcut {
        appleKeyboard ? .modifiers([.fn, .control]) : .modifiers([.control, .option, .command])
    }
}

/// Turns input events into dictation actions. Pure and deterministic, so every rule is unit-tested
/// with recorded event sequences (spec D1, D2, D3, D4, D8).
public struct HotkeyRecognizer: Sendable {
    enum State: Equatable {
        case idle
        /// Push-to-talk is down and recording started at `since`.
        case holding(since: UInt64)
        /// Push-to-talk is still down but this press no longer means dictation.
        case suppressed
        /// A hands-free dictation runs. `startedAt` drives the rapid-tap guard.
        case handsFree(startedAt: UInt64)
        /// The Command shortcut is held and an instruction is being recorded.
        case commanding(since: UInt64)
    }

    /// The edges and triggers events are reduced to, whatever kind of shortcut is configured.
    enum Input {
        case pttDown, pttUp, otherKey, handsFreeTrigger, escape, commandDown, commandUp
    }

    public var configuration: HotkeyConfiguration
    var state: State = .idle
    /// When the last quick tap ended, for double-tap detection.
    var lastTapUp: UInt64?
    var held: Set<ModifierKey> = []
    /// Whether the push-to-talk shortcut is physically down (key, mouse button or Caps Lock kinds).
    var pttPressed = false
    /// Whether a key-type Command shortcut is down.
    var commandPressed = false

    public init(configuration: HotkeyConfiguration = .appleKeyboard) {
        self.configuration = configuration
    }

    /// The controller calls this when a dictation ends for any other reason (stop icon, error, finished),
    /// so the recognizer does not think hands-free is still running.
    public mutating func reset() {
        state = pttIsDown ? .suppressed : .idle
        lastTapUp = nil
    }

    var pttIsDown: Bool {
        if case .modifiers(let set) = configuration.pushToTalk { return set.isSubset(of: held) }
        return pttPressed
    }

    public mutating func handle(_ event: KeyEvent) -> [HotkeyAction] {
        var actions: [HotkeyAction] = []
        for (input, time) in inputs(for: event) {
            actions += step(input, time: time)
        }
        return actions
    }

    // MARK: Events to inputs

    private mutating func inputs(for event: KeyEvent) -> [(Input, UInt64)] {
        let ptt = configuration.pushToTalk, hf = configuration.handsFree
        switch event {
        case .modifiers(let new, let time):
            let old = held
            held = new
            // Command Mode's modifiers (Fn+Control) contain push-to-talk's (Fn), so they are checked
            // first, and while a command records only its own edges count.
            if case .modifiers(let commandSet)? = configuration.command {
                if new == commandSet && old != commandSet { return [(.commandDown, time)] }
                if case .commanding = state {
                    return commandSet.isSubset(of: old) && !commandSet.isSubset(of: new) ? [(.commandUp, time)] : []
                }
            }
            var out: [(Input, UInt64)] = []
            if case .modifiers(let set) = ptt {
                if new == set && old != set && !set.isSubset(of: old) {
                    out.append((.pttDown, time))
                } else if set.isSubset(of: old) && !set.isSubset(of: new) {
                    out.append((.pttUp, time))
                } else if set.isSubset(of: new) && new != set && new.count > old.count {
                    // Another modifier joined while push-to-talk is held (Fn+Cmd…).
                    if case .modifiers(let hfSet) = hf, new == hfSet { out.append((.handsFreeTrigger, time)) } else { out.append((.otherKey, time)) }
                }
            } else if case .modifiers(let hfSet) = hf, new == hfSet, old != hfSet {
                out.append((.handsFreeTrigger, time))
            }
            if case .modifiers(let hfSet) = hf, case .modifiers(let set) = ptt, !hfSet.isSuperset(of: set), new == hfSet, old != hfSet {
                out.append((.handsFreeTrigger, time))
            }
            return out
        case .keyDown(let code, let time):
            if code == HotkeyConfiguration.escapeKeyCode { return [(.escape, time)] }
            if case .key(let c, let mods)? = configuration.command, code == c, held == mods {
                commandPressed = true
                return [(.commandDown, time)]
            }
            if case .key(let c, let mods) = ptt, code == c, held == mods {
                pttPressed = true
                return [(.pttDown, time)]
            }
            if case .key(let c, let mods) = hf, code == c, held == mods { return [(.handsFreeTrigger, time)] }
            return [(.otherKey, time)]
        case .keyUp(let code, let time):
            if case .key(let c, _)? = configuration.command, code == c, commandPressed {
                commandPressed = false
                return [(.commandUp, time)]
            }
            if case .key(let c, _) = ptt, code == c, pttPressed {
                pttPressed = false
                return [(.pttUp, time)]
            }
            return []
        case .mouseDown(let button, let time):
            if case .mouse(let b) = ptt, b == button { pttPressed = true; return [(.pttDown, time)] }
            if case .mouse(let b) = hf, b == button { return [(.handsFreeTrigger, time)] }
            return []
        case .mouseUp(let button, let time):
            if case .mouse(let b) = ptt, b == button, pttPressed { pttPressed = false; return [(.pttUp, time)] }
            return []
        case .capsLock(let down, let time):
            if ptt == .capsLock {
                pttPressed = down
                return [(down ? .pttDown : .pttUp, time)]
            }
            if hf == .capsLock, down { return [(.handsFreeTrigger, time)] }
            return []
        }
    }

    // MARK: State machine

    private mutating func step(_ input: Input, time: UInt64) -> [HotkeyAction] {
        switch (input, state) {
        case (.escape, .holding):
            state = .suppressed
            return [.cancel]
        case (.escape, .handsFree):
            state = pttIsDown ? .suppressed : .idle
            return [.cancel]
        case (.escape, .commanding):
            state = .suppressed
            return [.cancel]

        case (.commandDown, .idle):
            lastTapUp = nil
            state = .commanding(since: time)
            return [.startCommand]
        case (.commandDown, .holding):
            // Control joined a Fn hold, however long after: the order of the two keys does not matter.
            // The command's own clock starts now, so the quick-tap and other-key windows apply to it.
            state = .commanding(since: time)
            return [.convertToCommand]
        case (.commandDown, _):
            return []
        case (.commandUp, .commanding(let since)):
            state = .idle
            return time &- since < configuration.tapMaxNs ? [.discard] : [.stopCommand]
        case (.commandUp, _):
            return []
        case (.escape, _):
            // Esc also cancels while the controller is still transcribing or cleaning up, after the key
            // was released, so it is always reported. The controller ignores it when nothing is running.
            return [.cancel]

        case (.pttDown, .idle):
            if let lastTapUp, time &- lastTapUp <= configuration.doubleTapWindowNs {
                self.lastTapUp = nil
                state = .handsFree(startedAt: time)
                return [.startHandsFree]
            }
            state = .holding(since: time)
            return [.startHold]
        case (.pttDown, .handsFree(let startedAt)):
            // A further press right after a hands-free start means the user is mashing the key: cancel (D4).
            state = .suppressed
            return time &- startedAt <= configuration.doubleTapWindowNs ? [.cancel] : [.stopHandsFree]
        case (.pttDown, _):
            return []

        case (.pttUp, .holding(let since)):
            state = .idle
            if time &- since < configuration.tapMaxNs {
                lastTapUp = time
                return [.discard]
            }
            return [.stopHold]
        case (.pttUp, .suppressed):
            state = .idle
            return []
        case (.pttUp, _):
            return []

        case (.otherKey, .holding(let since)):
            if time &- since <= configuration.otherKeyWindowNs {
                state = .suppressed
                return [.discard]
            }
            return []
        case (.otherKey, .commanding(let since)):
            if time &- since <= configuration.otherKeyWindowNs {
                state = .suppressed
                return [.discard]
            }
            return []
        case (.otherKey, .idle):
            lastTapUp = nil
            return []
        case (.otherKey, _):
            return []

        case (.handsFreeTrigger, .idle):
            state = .handsFree(startedAt: time)
            return [.startHandsFree]
        case (.handsFreeTrigger, .holding(let since)):
            state = .handsFree(startedAt: since)
            return [.convertToHandsFree]
        case (.handsFreeTrigger, .handsFree(let startedAt)):
            // The shortcut again right after starting cancels (D4); later it stops.
            state = pttIsDown ? .suppressed : .idle
            return time &- startedAt <= configuration.doubleTapWindowNs ? [.cancel] : [.stopHandsFree]
        case (.handsFreeTrigger, .suppressed):
            return []
        case (.handsFreeTrigger, .commanding):
            return []
        }
    }
}

/// Display names for virtual key codes in shortcuts.
public enum KeyNames {
    static let names: [Int: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 76: "Enter",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
    ]

    public static func name(for keyCode: Int) -> String { names[keyCode] ?? "Key \(keyCode)" }
}
