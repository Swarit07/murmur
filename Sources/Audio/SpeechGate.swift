import Foundation

/// Decides whether a clip should be transcribed at all (D6): clips under the minimum length or without
/// speech are dropped silently.
public protocol SpeechGate: Sendable {
    var id: String { get }
    func hasSpeech(_ samples: [Float]) async -> Bool
}

public enum Levels {
    /// RMS level in dBFS of a block of samples.
    public static func dbfs(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return -120 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        return 20 * log10(max(rms, 1e-6))
    }

    public static func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }
}

/// Energy-based gate: counts 20 ms frames clearly louder than the clip's own noise floor.
/// Cheap and dependency-free; fooled by loud non-speech such as typing or taps.
public struct EnergySpeechGate: SpeechGate {
    public let id = "energy"
    public var minClipMs: Double
    public var minSpeechMs: Double
    public var absoluteFloorDb: Float
    public var marginDb: Float

    public init(minClipMs: Double = 300, minSpeechMs: Double = 200, absoluteFloorDb: Float = -50, marginDb: Float = 12) {
        self.minClipMs = minClipMs
        self.minSpeechMs = minSpeechMs
        self.absoluteFloorDb = absoluteFloorDb
        self.marginDb = marginDb
    }

    public func hasSpeech(_ samples: [Float]) async -> Bool {
        let rate = AudioFormat.sampleRate
        guard Double(samples.count) / rate * 1000 >= minClipMs else { return false }
        let frame = Int(rate * 0.02)
        var levels: [Float] = []
        var i = 0
        while i + frame <= samples.count {
            levels.append(Levels.dbfs(samples[i..<(i + frame)]))
            i += frame
        }
        guard !levels.isEmpty else { return false }
        let floor = levels.sorted()[levels.count / 10]
        let threshold = max(absoluteFloorDb, floor + marginDb)
        let speechFrames = levels.filter { $0 > threshold }.count
        return Double(speechFrames) * 20 >= minSpeechMs
    }
}
