import Core
import Foundation

/// One engine over the corpus. Written by `engine-pass` in its own process so memory is isolated.
struct EnginePassResult: Codable {
    struct Clip: Codable {
        var id: String
        var set: String
        var audioMs: Double
        var text: String?
        var ms: Double?
        var error: String?
        var energyGate: Bool
        var sileroGate: Bool?
    }

    struct Run: Codable {
        var id: String
        var audioMs: Double
        var ms: Double
    }

    var engine: String
    var isLocal: Bool
    var loadMs: Double?
    var footprintBeforeLoad: UInt64?
    var footprintAfterLoad: UInt64?
    var peakFootprint: UInt64?
    var clips: [Clip] = []
    var runs: [Run] = []
    var error: String?
    var date = Date()
    var build: String
}

/// One cleanup provider over the corpus text from a source (an engine's transcripts or the reference).
struct CleanupPassResult: Codable {
    struct Clip: Codable {
        var id: String
        var set: String
        var level: String
        var input: String
        var rulesText: String
        var modelText: String?
        var final: String
        var fallback: String?
        var flags: [String]
        var error: String?
        var rulesMs: Double
        var llmMs: Double?
    }

    struct Run: Codable {
        var id: String
        var rulesMs: Double
        var llmMs: Double?
        var totalMs: Double
        var fallback: String?
    }

    var provider: String
    var source: String
    var loadMs: Double?
    var footprintBeforeLoad: UInt64?
    var footprintAfterLoad: UInt64?
    var peakFootprint: UInt64?
    var clips: [Clip] = []
    var runs: [Run] = []
    var error: String?
    var date = Date()
    var build: String
}

/// Replays corpus clips through the full pipeline into a real text field.
struct E2EResult: Codable {
    struct Run: Codable {
        var id: String
        var status: String
        var audioMs: Double
        var timings: StageTimings
        var restored: Bool?
    }

    var engine: String
    var cleanup: String
    var app: String
    var runs: [Run] = []
    var date = Date()
    var build: String
}

enum ResultFiles {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(value).write(to: url)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(type, from: data)
    }

    static func safeName(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
    }

    static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}
