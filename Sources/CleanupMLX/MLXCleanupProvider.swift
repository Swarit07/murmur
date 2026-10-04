import Cleanup
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A small local instruct model run through MLX Swift. Weights download from Hugging Face on first load
/// into the standard Hugging Face cache.
public actor MLXCleanupProvider: CleanupProvider {
    public static let models: [String: String] = [
        "qwen3.5-0.8b": "mlx-community/Qwen3.5-0.8B-4bit",
        "qwen3.5-2b": "mlx-community/Qwen3.5-2B-4bit",
        "qwen3.5-4b": "mlx-community/Qwen3.5-4B-4bit",
        "qwen3-4b-2507": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
    ]

    public nonisolated let id: String
    let repo: String
    var container: ModelContainer?

    /// `name` is a short name from `models` or a full Hugging Face repo id.
    public init(name: String) {
        self.id = "mlx:\(name)"
        self.repo = Self.models[name] ?? name
    }

    public func load() async throws {
        guard container == nil else { return }
        let configuration = ModelConfiguration(id: repo, extraEOSTokens: ["<|im_end|>"])
        container = try await #huggingFaceLoadModelContainer(configuration: configuration)
        // One short generation compiles the Metal kernels so the first dictation is not slow.
        _ = try await complete([ChatMessage(.user, "Say OK.")], maxTokens: 2)
    }

    public func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String {
        guard let container else { throw CleanupError.unavailable("model not loaded") }
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        let chat: [Chat.Message] = messages.map {
            switch $0.role {
            case .system: .system($0.content)
            case .user: .user($0.content)
            case .assistant: .assistant($0.content)
            }
        }
        return try await session.respond(to: chat)
    }

    public func unload() async {
        container = nil
    }
}
