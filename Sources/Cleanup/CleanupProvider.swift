import Core
import Foundation

public enum CleanupLevel: String, Sendable, Codable, CaseIterable {
    /// Paste the raw transcript.
    case none
    /// Remove fillers, fix grammar and punctuation, resolve self-corrections. The default.
    case light
    /// Also edit for clarity and concision.
    case medium
}

public struct CleanupRequest: Sendable {
    public var level: CleanupLevel
    /// Terms the user cares about, given to the model so it keeps their spelling.
    public var vocabulary: [String]
    /// C3: numbered lists from spoken lists, paragraphs for long dictations.
    public var smartFormatting: Bool

    public init(level: CleanupLevel = .light, vocabulary: [String] = [], smartFormatting: Bool = false) {
        self.level = level
        self.vocabulary = vocabulary
        self.smartFormatting = smartFormatting
    }
}

public struct ChatMessage: Sendable, Codable, Equatable {
    public enum Role: String, Sendable, Codable { case system, user, assistant }
    public var role: Role
    public var content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

public protocol CleanupProvider: Sendable {
    var id: String { get }
    /// Downloads and loads whatever the provider needs. Safe to call more than once.
    func load() async throws
    /// Returns the model's cleaned text. Must honour task cancellation promptly.
    func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String
    func unload() async
    /// Prepares for these instructions (builds the cached prompt prefix) so the next real call is fast.
    func prewarm(_ messages: [ChatMessage]) async
}

public extension CleanupProvider {
    func prewarm(_ messages: [ChatMessage]) async {}
}

public enum CleanupError: Error, CustomStringConvertible {
    case missingKey(String)
    case unavailable(String)
    case http(Int, String)
    case badResponse

    public var description: String {
        switch self {
        case .missingKey(let name): "environment variable \(name) is not set"
        case .unavailable(let why): "unavailable: \(why)"
        case .http(let code, let body): "HTTP \(code): \(body.prefix(200))"
        case .badResponse: "unexpected response"
        }
    }
}
