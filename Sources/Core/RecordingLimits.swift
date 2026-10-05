import Foundation

/// D7: a recording warns a minute before the 20-minute limit, stops at the limit, and stops early
/// when the microphone has sent no audio for a few seconds. Whatever was recorded is transcribed and
/// kept in History either way.
public struct RecordingLimits: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case none, warn, stopAtLimit, stopNoAudio
    }

    public var maxSeconds: Double
    public var warnBeforeSeconds: Double
    public var noAudioSeconds: Double

    public init(maxSeconds: Double = 1200, warnBeforeSeconds: Double = 60, noAudioSeconds: Double = 3) {
        self.maxSeconds = maxSeconds
        self.warnBeforeSeconds = warnBeforeSeconds
        self.noAudioSeconds = noAudioSeconds
    }

    /// `sinceAudio` counts from the newest audio buffer, or from the start before the first one.
    public func check(elapsed: Double, sinceAudio: Double, warned: Bool) -> Action {
        if sinceAudio >= noAudioSeconds { return .stopNoAudio }
        if elapsed >= maxSeconds { return .stopAtLimit }
        if !warned, elapsed >= maxSeconds - warnBeforeSeconds { return .warn }
        return .none
    }
}
