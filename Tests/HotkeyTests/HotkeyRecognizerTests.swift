@testable import Hotkey
import Testing

/// Scripted key sequences with times in milliseconds.
struct Script {
    var recognizer = HotkeyRecognizer()
    var actions: [HotkeyAction] = []

    init(_ configuration: HotkeyConfiguration = .appleKeyboard) {
        recognizer = HotkeyRecognizer(configuration: configuration)
    }

    mutating func mods(_ held: Set<ModifierKey>, at ms: UInt64) {
        actions += recognizer.handle(.modifiers(held: held, time: ms * 1_000_000))
    }

    mutating func key(_ code: Int, at ms: UInt64) {
        actions += recognizer.handle(.keyDown(keyCode: code, time: ms * 1_000_000))
    }
}

let space = HotkeyConfiguration.spaceKeyCode
let escape = HotkeyConfiguration.escapeKeyCode
let arrowLeft = 123
let f5 = 96

@Suite("Hotkey recognizer")
struct HotkeyRecognizerTests {
    @Test func holdStartsAndReleaseStops() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([], at: 1200)
        #expect(s.actions == [.startHold, .stopHold])
    }

    @Test func quickTapIsDiscarded() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([], at: 120)
        #expect(s.actions == [.startHold, .discard])
    }

    /// D1: Fn pressed with another key within 250 ms starts no dictation.
    @Test(arguments: [arrowLeft, f5])
    func fnWithAnotherKeyDiscards(code: Int) {
        var s = Script()
        s.mods([.fn], at: 0)
        s.key(code, at: 80)
        s.mods([], at: 400)
        #expect(s.actions == [.startHold, .discard])
    }

    @Test func otherKeyAfterWindowKeepsRecording() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.key(arrowLeft, at: 600)
        s.mods([], at: 1500)
        #expect(s.actions == [.startHold, .stopHold])
    }

    @Test func anotherModifierEarlyDiscards() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([.fn, .command], at: 100)
        s.mods([.fn], at: 200)
        s.mods([], at: 300)
        #expect(s.actions == [.startHold, .discard])
    }

    /// D2: double-tap within 0.5 s starts hands-free; the next press stops it.
    @Test func doubleTapStartsHandsFree() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([], at: 100)
        s.mods([.fn], at: 300)
        s.mods([], at: 400)
        s.mods([.fn], at: 4000)
        s.mods([], at: 4100)
        #expect(s.actions == [.startHold, .discard, .startHandsFree, .stopHandsFree])
    }

    @Test func slowSecondTapIsJustAnotherHold() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([], at: 100)
        s.mods([.fn], at: 900)
        s.mods([], at: 2500)
        #expect(s.actions == [.startHold, .discard, .startHold, .stopHold])
    }

    /// D2: Fn+Space switches the running recording to hands-free; releasing Fn does not stop it.
    @Test func chordConvertsHoldToHandsFree() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.key(space, at: 60)
        s.mods([], at: 200)
        s.mods([.fn], at: 5000)
        s.key(space, at: 5050)
        s.mods([], at: 5200)
        #expect(s.actions == [.startHold, .convertToHandsFree, .stopHandsFree])
    }

    /// D4: a third quick tap right after a double-tap start cancels instead of pasting.
    @Test func thirdRapidTapCancels() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([], at: 80)
        s.mods([.fn], at: 200)
        s.mods([], at: 280)
        s.mods([.fn], at: 400)
        s.mods([], at: 480)
        #expect(s.actions == [.startHold, .discard, .startHandsFree, .cancel])
    }

    /// D4: the hands-free chord pressed twice within 0.5 s of starting cancels.
    @Test func doubleChordCancels() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.key(space, at: 50)
        s.mods([], at: 120)
        s.mods([.fn], at: 300)
        s.mods([], at: 380)
        #expect(s.actions == [.startHold, .convertToHandsFree, .cancel])
    }

    /// D3: Esc cancels a hold and a hands-free dictation.
    @Test func escapeCancels() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.key(escape, at: 900)
        s.mods([], at: 1200)
        #expect(s.actions == [.startHold, .cancel])

        var h = Script()
        h.mods([.fn], at: 0)
        h.mods([], at: 100)
        h.mods([.fn], at: 250)
        h.mods([], at: 330)
        h.key(escape, at: 3000)
        h.mods([.fn], at: 6000)
        h.mods([], at: 7500)
        #expect(h.actions == [.startHold, .discard, .startHandsFree, .cancel, .startHold, .stopHold])
    }

    @Test func ctrlOptionConfiguration() {
        var s = Script(.otherKeyboard)
        s.mods([.control], at: 0)
        s.mods([.control, .option], at: 30)
        s.mods([.control], at: 1500)
        s.mods([], at: 1520)
        #expect(s.actions == [.startHold, .stopHold])

        var h = Script(.otherKeyboard)
        h.mods([.control, .option], at: 0)
        h.key(space, at: 40)
        h.mods([], at: 100)
        h.mods([.control, .option], at: 3000)
        h.mods([], at: 3100)
        #expect(h.actions == [.startHold, .convertToHandsFree, .stopHandsFree])
    }

    @Test func resetAfterExternalStop() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([], at: 100)
        s.mods([.fn], at: 250)
        s.mods([], at: 330)
        s.recognizer.reset()
        s.mods([.fn], at: 5000)
        s.mods([], at: 6000)
        #expect(s.actions == [.startHold, .discard, .startHandsFree, .startHold, .stopHold])
    }
}
