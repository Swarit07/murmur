import Cleanup
import Foundation
import os
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

/// A small local instruct model run through MLX Swift. Weights download from Hugging Face on first load
/// into the standard Hugging Face cache.
///
/// The system prompt and worked examples are the same for every dictation, so their KV cache is built
/// once and copied for each call. A dictation then only pays for its own few dozen tokens.
///
/// Unloading keeps the model and swaps its weights for empty placeholders, and reloading puts them back,
/// so memory returns to the same level after every idle unload (docs/mlx-unload-leak.md).
public actor MLXCleanupProvider: CleanupProvider {
    public static let models: [String: String] = [
        "qwen3.5-0.8b": "mlx-community/Qwen3.5-0.8B-4bit",
        "qwen3.5-2b": "mlx-community/Qwen3.5-2B-4bit",
        "qwen3.5-4b": "mlx-community/Qwen3.5-4B-4bit",
        "qwen3-4b-2507": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        "smollm3-3b": "mlx-community/SmolLM3-3B-4bit",
        "gemma3-1b": "mlx-community/gemma-3-1b-it-qat-4bit",
    ]

    /// Draft models for speculative decoding. The draft must share the main model's tokenizer, and both
    /// caches must be trimmable, so this works for the Qwen3 family but not Qwen3.5's hybrid layers.
    public static let drafts: [String: String] = [
        "qwen3-4b-2507": "mlx-community/Qwen3-0.6B-4bit",
    ]

    public nonisolated let id: String
    let repo: String
    let draftRepo: String?
    let usePrefixCache: Bool
    var container: ModelContainer?
    /// Whether the weights are in memory; `unload()` keeps the container and empties the model.
    var loaded = false
    let weights = WeightsFlag()
    let prefix = PrefixCache()
    let draftPrefix = PrefixCache()
    let draft = DraftBox()

    /// MLX compile is off. Qwen3.5's compiled decode traces keep its fused GDN input projections (about 400 MB)
    /// as constants, and MLX does not free them when the traces are released, so every reload leaked them.
    /// Uncompiled, the outputs are the same and cleanup is as fast (docs/mlx-unload-leak.md). Set once, before
    /// any model runs; `MURMUR_MLX_COMPILE=1` keeps it on for comparisons.
    static let compileOff: Void = {
        if ProcessInfo.processInfo.environment["MURMUR_MLX_COMPILE"] != "1" { MLX.compile(enable: false) }
    }()

    /// `name` is a short name from `models` or a full Hugging Face repo id.
    /// A name ending in `+draft` turns on speculative decoding with that model's draft.
    public init(name: String, usePrefixCache: Bool = ProcessInfo.processInfo.environment["MURMUR_MLX_NO_PREFIX_CACHE"] == nil) {
        self.id = "mlx:\(name)"
        let base = name.hasSuffix("+draft") ? String(name.dropLast(6)) : name
        self.repo = Self.models[base] ?? base
        self.draftRepo = name.hasSuffix("+draft") ? Self.drafts[base] : nil
        self.usePrefixCache = usePrefixCache
        _ = Self.compileOff
    }

    public func load() async throws {
        guard !loaded else { return }
        if let container {
            // Reload into the model `unload()` kept. If that fails (say the files were deleted meanwhile),
            // load from scratch, which can download them again.
            let draft = self.draft, weights = self.weights
            do {
                try await container.perform { context in
                    guard !weights.present else { return }
                    try await Self.restoreWeights(of: context)
                    if let draftContext = draft.context { try await Self.restoreWeights(of: draftContext) }
                    weights.present = true
                }
            } catch {
                Self.log.error("reload failed, loading from scratch: \(String(describing: error), privacy: .public)")
                self.container = nil
                draft.context = nil
            }
        }
        if container == nil {
            let configuration = ModelConfiguration(id: repo, extraEOSTokens: ["<|im_end|>", "<end_of_turn>"])
            let container = try await #huggingFaceLoadModelContainer(configuration: configuration)
            if let draftRepo {
                draft.context = try await #huggingFaceLoadModel(configuration: ModelConfiguration(id: draftRepo, extraEOSTokens: ["<|im_end|>"]))
            }
            weights.present = true
            self.container = container
        }
        loaded = true
        Self.log.notice("loaded weights: MLX active \(Memory.activeMemory / 1_048_576, privacy: .public) MB")
        // Build the prefix cache for the default prompt and compile the Metal kernels.
        if ProcessInfo.processInfo.environment["MURMUR_MLX_NO_WARMUP"] == nil {
            _ = try await complete(CleanupPrompt.messages(for: "Say OK.", level: .light, vocabulary: []), maxTokens: 2)
        }
        Self.log.notice("warmed: MLX active \(Memory.activeMemory / 1_048_576, privacy: .public) MB, cache \(Memory.cacheMemory / 1_048_576, privacy: .public) MB")
    }

    public func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String {
        guard loaded, let container else { throw CleanupError.unavailable("model not loaded") }
        let rendered = messages.map { ["role": $0.role.rawValue, "content": $0.content] as [String: any Sendable] }
        let key = messages.dropLast().map(\.content).joined(separator: "\u{1F}")
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        let prefix = self.prefix
        let draftPrefix = self.draftPrefix
        let draft = self.draft
        let usePrefixCache = self.usePrefixCache
        let weights = self.weights
        return try await container.perform(values: Request(rendered: rendered, key: key)) { context, request in
            // An unload that got the model first has emptied it.
            guard weights.present else { throw CleanupError.unavailable("model not loaded") }
            let extra: [String: any Sendable] = ["enable_thinking": false]
            let full = try context.tokenizer.applyChatTemplate(messages: request.rendered, tools: nil, additionalContext: extra)

            var cache: [KVCache]
            var start = 0
            if usePrefixCache, let (tokens, cached) = prefix.get(request.key), full.starts(with: tokens), tokens.count < full.count {
                cache = cached.map { $0.copy() }
                start = tokens.count
            } else if usePrefixCache {
                // Shared prefix: everything the full prompt has in common with the same conversation whose
                // last message is empty. (Rendering it without the last message fails for a lone system
                // prompt: chat templates require a user turn.)
                let probe = Array(request.rendered.dropLast()) + [["role": "user", "content": ""] as [String: any Sendable]]
                let head = try context.tokenizer.applyChatTemplate(messages: probe, tools: nil, additionalContext: extra)
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
            // The generator runs in its own task. On a timeout the caller cancels us; we cancel the
            // generator and wait for it to stop before giving the model back, so no two GPU jobs overlap
            // (an overlap crashed Metal in testing).
            let stream: AsyncStream<Generation>
            let producer: Task<Void, Never>
            if let draftModel = draft.context?.model {
                // The draft cache must cover the same prefix as the main cache.
                var draftCache: [KVCache]
                if start > 0, let (tokens, cached) = draftPrefix.get(request.key), tokens.count == start {
                    draftCache = cached.map { $0.copy() }
                } else {
                    let built = try draftModel.newCache(parameters: parameters)
                    if start > 0 {
                        let text = LMInput.Text(tokens: MLXArray(Array(full[0..<start])))
                        _ = draftModel(text[text: .newAxis], cache: built, state: nil)
                        eval(built.flatMap(\.state))
                        draftPrefix.set(request.key, Array(full[0..<start]), built)
                    }
                    draftCache = built.map { $0.copy() }
                }
                let iterator = try SpeculativeTokenIterator(
                    input: input, mainModel: context.model, draftModel: draftModel, mainCache: cache, draftCache: draftCache,
                    mainState: nil, parameters: parameters,
                    numDraftTokens: ProcessInfo.processInfo.environment["MURMUR_DRAFT_TOKENS"].flatMap(Int.init) ?? 4)
                (stream, producer) = generateTask(
                    promptTokenCount: input.text.tokens.size, modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer, iterator: iterator)
            } else {
                let iterator = try TokenIterator(input: input, model: context.model, cache: cache, parameters: parameters)
                (stream, producer) = generateTask(
                    promptTokenCount: input.text.tokens.size, modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer, iterator: iterator)
            }
            for await event in stream {
                if case .chunk(let piece) = event { output += piece }
                if Task.isCancelled { break }
            }
            producer.cancel()
            await producer.value
            MLXCleanupProvider.log.info("complete: MLX active \(Memory.activeMemory / 1_048_576, privacy: .public) MB, cache \(Memory.cacheMemory / 1_048_576, privacy: .public) MB")
            return output
        }
    }

    /// Builds the prefix cache for these instructions with a one-token generation.
    public func prewarm(_ messages: [ChatMessage]) async {
        _ = try? await complete(messages, maxTokens: 1)
    }

    public func unload() async {
        guard loaded else { return }
        loaded = false
        // Waits for any call still holding the model, so nothing runs on the GPU after this returns.
        //
        // The model itself stays: building a model leaves a few thousand MLX graph nodes that are never freed
        // (about 4 MB per load), so a reload fills the same model again instead of building a new one.
        let draft = self.draft, weights = self.weights
        _ = await container?.perform { context in
            weights.present = false
            context.model.invalidateCompiledTraces()
            Self.dropWeights(of: context.model)
            if let draftModel = draft.context?.model {
                draftModel.invalidateCompiledTraces()
                Self.dropWeights(of: draftModel)
            }
            return 0
        }
        prefix.clear()
        draftPrefix.clear()
        // MLX keeps freed GPU buffers for reuse; give them back so unloading actually frees the memory.
        Memory.clearCache()
        Self.log.notice("unloaded: MLX active \(Memory.activeMemory / 1_048_576, privacy: .public) MB, cache \(Memory.cacheMemory / 1_048_576, privacy: .public) MB")
    }

    /// Replaces every weight with an unevaluated array of zeros of the same shape and type. Those hold no
    /// memory, and the shapes let `restoreWeights` check the checkpoint against the model as a first load does.
    /// Replacing Qwen3.5's input projections also drops its fused copy of them.
    static func dropWeights(of model: Module) {
        var zero: [DType: MLXArray] = [:]
        let placeholders = model.parameters().flattened().map { key, value in
            let scalar = zero[value.dtype] ?? MLXArray.zeros([], dtype: value.dtype)
            zero[value.dtype] = scalar
            return (key, broadcast(scalar, to: value.shape))
        }
        do {
            try model.update(parameters: ModuleParameters.unflattened(placeholders), verify: [])
        } catch {
            log.error("could not empty the model: \(String(describing: error), privacy: .public)")
        }
    }

    /// Loads the checkpoint back into a model emptied by `dropWeights`: the same weight update, preparation
    /// (Qwen3.5's fused projections) and evaluation a first load ends with. The model is already quantized.
    static func restoreWeights(of context: ModelContext) async throws {
        guard case .directory(let directory) = context.configuration.id else {
            throw CleanupError.unavailable("model folder unknown")
        }
        try await loadWeights(modelDirectory: directory, model: context.model)
    }

    static let log = Logger(subsystem: "com.swaritsheel.Murmur", category: "mlx")

    /// MLX's live and cached memory, for diagnostics.
    public static func memoryReport() -> String {
        let (active, cache) = memoryMB()
        return "MLX active \(active) MB, cache \(cache) MB"
    }

    /// MLX's live and cached memory in MB, after returning the cache.
    public static func memoryMB() -> (active: Int, cache: Int) {
        Memory.clearCache()
        return (Memory.activeMemory / 1_048_576, Memory.cacheMemory / 1_048_576)
    }

    struct Request: Sendable {
        let rendered: [[String: any Sendable]]
        let key: String
    }
}

/// The draft model for speculative decoding. Only touched inside `ModelContainer.perform`.
final class DraftBox: @unchecked Sendable {
    var context: ModelContext?
}

/// Whether the model in the container has its weights. Only touched inside `ModelContainer.perform`, so a
/// call queued behind `unload()` finds the model empty instead of running it.
final class WeightsFlag: @unchecked Sendable {
    var present = false
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
