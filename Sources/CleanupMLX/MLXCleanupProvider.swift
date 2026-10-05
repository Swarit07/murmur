import Cleanup
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A small local instruct model run through MLX Swift. Weights download from Hugging Face on first load
/// into the standard Hugging Face cache.
///
/// The system prompt and worked examples are the same for every dictation, so their KV cache is built
/// once and copied for each call. A dictation then only pays for its own few dozen tokens.
public actor MLXCleanupProvider: CleanupProvider {
    public static let models: [String: String] = [
        "qwen3.5-0.8b": "mlx-community/Qwen3.5-0.8B-4bit",
        "qwen3.5-2b": "mlx-community/Qwen3.5-2B-4bit",
        "qwen3.5-4b": "mlx-community/Qwen3.5-4B-4bit",
        "qwen3-4b-2507": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        "smollm3-3b": "mlx-community/SmolLM3-3B-4bit",
        "gemma3-1b": "mlx-community/gemma-3-1b-it-qat-4bit",
    ]

    public nonisolated let id: String
    let repo: String
    let usePrefixCache: Bool
    var container: ModelContainer?
    let prefix = PrefixCache()

    /// `name` is a short name from `models` or a full Hugging Face repo id.
    public init(name: String, usePrefixCache: Bool = ProcessInfo.processInfo.environment["MURMUR_MLX_NO_PREFIX_CACHE"] == nil) {
        self.id = "mlx:\(name)"
        self.repo = Self.models[name] ?? name
        self.usePrefixCache = usePrefixCache
    }

    public func load() async throws {
        guard container == nil else { return }
        let configuration = ModelConfiguration(id: repo, extraEOSTokens: ["<|im_end|>", "<end_of_turn>"])
        container = try await #huggingFaceLoadModelContainer(configuration: configuration)
        // Build the prefix cache for the default prompt and compile the Metal kernels.
        _ = try await complete(CleanupPrompt.messages(for: "Say OK.", level: .light, vocabulary: []), maxTokens: 2)
    }

    public func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String {
        guard let container else { throw CleanupError.unavailable("model not loaded") }
        let rendered = messages.map { ["role": $0.role.rawValue, "content": $0.content] as [String: any Sendable] }
        let key = messages.dropLast().map(\.content).joined(separator: "\u{1F}")
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        let prefix = self.prefix
        let usePrefixCache = self.usePrefixCache
        return try await container.perform(values: Request(rendered: rendered, key: key)) { context, request in
            let extra: [String: any Sendable] = ["enable_thinking": false]
            let full = try context.tokenizer.applyChatTemplate(messages: request.rendered, tools: nil, additionalContext: extra)

            var cache: [KVCache]
            var start = 0
            if usePrefixCache, let (tokens, cached) = prefix.get(request.key), full.starts(with: tokens), tokens.count < full.count {
                cache = cached.map { $0.copy() }
                start = tokens.count
            } else if usePrefixCache {
                // Shared prefix: everything the full prompt has in common with the prompt minus the transcript.
                let head = try context.tokenizer.applyChatTemplate(
                    messages: Array(request.rendered.dropLast()), tools: nil, additionalContext: extra)
                let shared = min(zip(full, head).prefix { $0 == $1 }.count, full.count - 1)
                let built = try context.model.newCache(parameters: parameters)
                if shared > 0 {
                    let text = LMInput.Text(tokens: MLXArray(Array(full[0..<shared])))
                    _ = context.model(text[text: .newAxis], cache: built, state: nil)
                    eval(built.flatMap(\.state))
                    prefix.set(request.key, Array(full[0..<shared]), built)
                }
                cache = built.map { $0.copy() }
                start = shared
            } else {
                cache = try context.model.newCache(parameters: parameters)
            }

            let input = LMInput(tokens: MLXArray(Array(full[start...])))
            var output = ""
            for await event in try generate(input: input, cache: cache, parameters: parameters, context: context) {
                if case .chunk(let piece) = event { output += piece }
                if Task.isCancelled { break }
            }
            return output
        }
    }

    public func unload() async {
        container = nil
        prefix.clear()
    }

    struct Request: Sendable {
        let rendered: [[String: any Sendable]]
        let key: String
    }
}

/// Prefix KV caches keyed by the system prompt and examples. Only read and written inside
/// `ModelContainer.perform`, which serializes access to the model.
final class PrefixCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: ([Int], [KVCache])] = [:]

    func get(_ key: String) -> ([Int], [KVCache])? { lock.withLock { entries[key] } }

    func set(_ key: String, _ tokens: [Int], _ cache: [KVCache]) {
        lock.withLock {
            if entries.count >= 4 { entries.removeAll() }
            entries[key] = (tokens, cache)
        }
    }

    func clear() { lock.withLock { entries.removeAll() } }
}
