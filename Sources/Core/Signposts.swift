import Foundation
import os

/// Pipeline stages. Each one emits an `os_signpost` interval named after its raw value.
public enum Stage: String, Sendable, Codable, CaseIterable {
    case captureFlush = "capture-flush"
    case transcribe
    case rules
    case llm
    case insert
    case total
}

public enum Signposts {
    static let signposter = OSSignposter(subsystem: "dev.murmur", category: "pipeline")

    public static func transition(from: String, to: String) {
        signposter.emitEvent("transition", "\(from, privacy: .public) -> \(to, privacy: .public)")
    }

    /// Runs `body` inside a signpost interval and returns its result with the elapsed milliseconds.
    public static func measure<T>(_ stage: Stage, _ body: () async throws -> T) async rethrows -> (T, Double) {
        let state = signposter.beginInterval("stage", id: signposter.makeSignpostID(), "\(stage.rawValue, privacy: .public)")
        let start = Clock.now()
        defer { signposter.endInterval("stage", state) }
        let value = try await body()
        return (value, Clock.ms(since: start))
    }
}

/// Monotonic clock helpers in milliseconds.
public enum Clock {
    public static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    public static func ms(since start: UInt64) -> Double {
        Double(now() &- start) / 1_000_000
    }

    public static func ms(from start: UInt64, to end: UInt64) -> Double {
        Double(end &- start) / 1_000_000
    }
}

/// Per-dictation stage timings in milliseconds. Logged without any transcript text.
public struct StageTimings: Sendable, Codable, Equatable {
    public var captureFlushMs: Double?
    public var transcribeMs: Double?
    public var rulesMs: Double?
    public var llmMs: Double?
    public var insertMs: Double?
    /// Key release to paste posted.
    public var totalMs: Double?

    public init() {}

    public subscript(stage: Stage) -> Double? {
        get {
            switch stage {
            case .captureFlush: captureFlushMs
            case .transcribe: transcribeMs
            case .rules: rulesMs
            case .llm: llmMs
            case .insert: insertMs
            case .total: totalMs
            }
        }
        set {
            switch stage {
            case .captureFlush: captureFlushMs = newValue
            case .transcribe: transcribeMs = newValue
            case .rules: rulesMs = newValue
            case .llm: llmMs = newValue
            case .insert: insertMs = newValue
            case .total: totalMs = newValue
            }
        }
    }

    public var summary: String {
        Stage.allCases.compactMap { stage in
            self[stage].map { "\(stage.rawValue) \(Format.ms($0))" }
        }.joined(separator: " · ")
    }
}

public enum Format {
    public static func ms(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f ms", value) : String(format: "%.1f ms", value)
    }

    public static func mb(_ bytes: UInt64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    public static func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
