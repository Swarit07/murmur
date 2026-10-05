@testable import Core
import Testing

@Suite("Recording limits (D7)")
struct RecordingLimitsTests {
    let limits = RecordingLimits()

    @Test func warnsOnceAMinuteBeforeAndStopsAtTwentyMinutes() {
        #expect(limits.check(elapsed: 600, sinceAudio: 0.1, warned: false) == .none)
        #expect(limits.check(elapsed: 1140, sinceAudio: 0.1, warned: false) == .warn)
        #expect(limits.check(elapsed: 1150, sinceAudio: 0.1, warned: true) == .none)
        #expect(limits.check(elapsed: 1200, sinceAudio: 0.1, warned: true) == .stopAtLimit)
    }

    @Test func stopsWhenTheMicrophoneGoesQuietOnTheWire() {
        #expect(limits.check(elapsed: 10, sinceAudio: 2.9, warned: false) == .none)
        #expect(limits.check(elapsed: 10, sinceAudio: 3, warned: false) == .stopNoAudio)
        #expect(limits.check(elapsed: 1199, sinceAudio: 5, warned: true) == .stopNoAudio)
    }
}
