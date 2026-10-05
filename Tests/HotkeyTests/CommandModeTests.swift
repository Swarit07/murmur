import Foundation
@testable import Hotkey
import Testing

@Suite("Command Mode shortcut")
struct CommandModeTests {
    var withCommand: HotkeyConfiguration {
        var c = HotkeyConfiguration.appleKeyboard
        c.command = HotkeyConfiguration.defaultCommand(appleKeyboard: true)
        return c
    }

    @Test func fnThenControlConvertsTheHold() {
        var s = Script(withCommand)
        s.mods([.fn], at: 0)
        s.mods([.fn, .control], at: 90)
        s.mods([.control], at: 1500)
        s.mods([], at: 1600)
        #expect(s.actions == [.startHold, .convertToCommand, .stopCommand])
    }

    @Test func controlThenFnStartsACommand() {
        var s = Script(withCommand)
        s.mods([.control], at: 0)
        s.mods([.fn, .control], at: 60)
        s.mods([.fn], at: 1400)
        s.mods([], at: 1500)
        #expect(s.actions == [.startCommand, .stopCommand])
    }

    @Test func quickCommandTapIsDiscarded() {
        var s = Script(withCommand)
        s.mods([.control], at: 0)
        s.mods([.fn, .control], at: 10)
        s.mods([.control], at: 150)
        #expect(s.actions == [.startCommand, .discard])
    }

    @Test func escapeCancelsACommand() {
        var s = Script(withCommand)
        s.mods([.control], at: 0)
        s.mods([.fn, .control], at: 10)
        s.key(escape, at: 700)
        s.mods([], at: 900)
        #expect(s.actions == [.startCommand, .cancel])
    }

    /// The owner's report: holding Fn, then pressing Control a moment later, must still be a command.
    @Test func controlLongAfterFnStillConverts() {
        var s = Script(withCommand)
        s.mods([.fn], at: 0)
        s.mods([.fn, .control], at: 900)
        s.mods([.control], at: 2500)
        s.mods([], at: 2600)
        #expect(s.actions == [.startHold, .convertToCommand, .stopCommand])
    }

    @Test func eitherKeyReleasedFirstFinishesTheCommand() {
        var s = Script(withCommand)
        s.mods([.fn], at: 0)
        s.mods([.fn, .control], at: 600)
        s.mods([.fn], at: 2000)
        s.mods([], at: 2100)
        #expect(s.actions == [.startHold, .convertToCommand, .stopCommand])
    }

    @Test func offMeansFnControlIsJustAnotherChord() {
        var s = Script()
        s.mods([.fn], at: 0)
        s.mods([.fn, .control], at: 90)
        s.mods([], at: 1500)
        #expect(s.actions == [.startHold, .discard])
    }

    @Test func savedConfigurationsWithoutCommandStillDecode() throws {
        let old = #"{"pushToTalk":{"modifiers":{"_0":["fn"]}},"handsFree":{"key":{"keyCode":49,"modifiers":["fn"]}},"otherKeyWindowNs":250000000,"tapMaxNs":300000000,"doubleTapWindowNs":500000000}"#
        let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: Data(old.utf8))
        #expect(decoded.command == nil)
        #expect(decoded.pushToTalk == .modifiers([.fn]))
    }
}
