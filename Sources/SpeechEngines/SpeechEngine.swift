import Foundation

public struct TranscribeOptions: Sendable {
    /// ISO 639-1 code, or nil for automatic detection.
    public var language: String?
    /// Dictionary terms passed to the engine as a prompt or bias where the engine supports it.
    public var vocabulary: [String]

    public init(language: String? = nil, vocabulary: [String] = []) {
        self.language = language
        self.vocabulary = vocabulary
    }
}

/// Every speech engine sits behind this protocol. Engines take 16 kHz mono Float32 samples.
public protocol SpeechEngine: Sendable {
    var id: String { get }
    /// Whether the engine runs on this Mac (false for cloud engines).
    var isLocal: Bool { get }
    /// Downloads if needed and loads the model. Safe to call more than once.
    func load() async throws
    func transcribe(_ samples: [Float], options: TranscribeOptions) async throws -> String
    func unload() async
}

public enum SpeechError: Error, CustomStringConvertible {
    case notLoaded
    case missingKey(String)
    case unavailable(String)
    case http(Int, String)
    case badResponse

    public var description: String {
        switch self {
        case .notLoaded: "model not loaded"
        case .missingKey(let name): "environment variable \(name) is not set"
        case .unavailable(let why): "unavailable: \(why)"
        case .http(let code, let body): "HTTP \(code): \(body.prefix(200))"
        case .badResponse: "unexpected response"
        }
    }
}

public enum EngineCatalog {
    public static let ids = ["parakeet-v3", "parakeet-v2", "parakeet-ultra", "whisper-turbo", "apple-speech", "groq-whisper"]

    public static func make(_ id: String) throws -> any SpeechEngine {
        switch id {
        case "parakeet-v3": ParakeetEngine(version: .v3)
        case "parakeet-v2": ParakeetEngine(version: .v2)
        case "parakeet-ultra": ParakeetEngine(version: .ultra)
        case "whisper-turbo": WhisperKitEngine(model: "large-v3-v20240930_turbo")
        case "whisper-turbo-626mb": WhisperKitEngine(model: "large-v3-v20240930_626MB")
        case "apple-speech": AppleSpeechEngine()
        case "groq-whisper": GroqWhisperEngine()
        default: throw SpeechError.unavailable("unknown engine \(id). Known: \(ids.joined(separator: ", "))")
        }
    }
}
