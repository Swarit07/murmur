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
/// Prompt-lookup decoding (`PromptLookupTokenIterator`) checks guesses copied from the dictation in one forward
/// pass each. It is on by default (owner decision): about 1.6× faster on long dictations, so far more of them
/// finish inside the cleanup time limit. MLX rounds a pass over several tokens differently from one-token passes,
/// so a few dictations in a hundred come out worded slightly differently (near-ties like "6:30" vs "six thirty");
/// the guard checks every output as before (docs/cleanup-speed.md). `MURMUR_PROMPT_LOOKUP=0` turns it off.
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
    var promptLookup = ProcessInfo.processInfo.environment["MURMUR_PROMPT_LOOKUP"] != "0"
    let lookupSettings = PromptLookupTokenIterator.Settings.fromEnvironment()
    /// Counts from the last generation that used prompt lookup.
    public private(set) var lastLookupStats: PromptLookupStats?

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
        let lookup = promptLookup && draftRepo == nil ? self.lookupSettings : nil
        let lookupStats = PromptLookupStatsBox()
        lastLookupStats = nil
        let output = try await container.perform(values: Request(rendered: rendered, key: key)) { context, request in
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
            } else if let lookup, let iterator = try PromptLookupTokenIterator(
                input: input, model: context.model, cache: cache,
                source: Array(full[(start > 0 ? start : try Self.dictationStart(of: full, request: request, context: context))...]),
                parameters: parameters, settings: lookup, stats: lookupStats)
            {
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
        if lookup != nil, lookupStats.value.passes > 0 {
            let s = lookupStats.value
            lastLookupStats = s
            Self.log.info("prompt lookup: \(s.tokens, privacy: .public) tokens in \(s.passes, privacy: .public) passes, \(s.accepted, privacy: .public)/\(s.drafted, privacy: .public) guessed tokens kept, \(s.replayed, privacy: .public) replayed")
        }
        return output
    }

    /// Turns prompt-lookup decoding on or off for later calls (for side-by-side measurements).
    public func setPromptLookup(_ on: Bool) {
        promptLookup = on
    }

    /// Diagnostics: does a forward pass over several tokens compute what one-token passes compute, bit for bit?
    ///
    /// First a single quantized linear layer of the model: each row of an `n`-row product against the same
    /// row computed alone. Then the whole model: greedy decoding of `transcript` one token per pass, against
    /// one pass over the first `n` of the same tokens from the same cache, comparing every logit.
    public func numerics(transcript: String, lengths: [Int]) async throws -> [String] {
        guard loaded, let container else { throw CleanupError.unavailable("model not loaded") }
        let rendered = CleanupPrompt.messages(for: transcript, level: .light, vocabulary: [], smartFormatting: true)
            .map { ["role": $0.role.rawValue, "content": $0.content] as [String: any Sendable] }
        let parameters = GenerateParameters(temperature: 0)
        return try await container.perform(values: rendered) { context, rendered in
            var lines: [String] = []
            let longest = lengths.max() ?? 1

            // One layer.
            guard let (name, layer) = context.model.namedModules().compactMap({ key, module in
                (module as? QuantizedLinear).map { (key, $0) }
            }).first(where: { $0.1.weight.dim(0) >= 4096 }) else { return ["no quantized layer found"] }
            let inputDims = layer.weight.dim(1) * 32 / layer.bits
            MLXRandom.seed(7)
            let x = (MLXRandom.normal([1, longest, inputDims])).asType(.bfloat16)
            let alone = (0..<longest).map { layer(x[0..., $0 ..< ($0 + 1), 0...]) }
            eval(alone)
            lines.append("Layer \(name) (\(inputDims) → \(layer.weight.dim(0))), random bf16 input. Rows equal to the same row computed alone:")
            for n in lengths {
                let together = layer(x[0..., ..<n, 0...])
                let differ = (0..<n).map { r in (together[0..., r ..< (r + 1), 0...] .!= alone[r]).sum().item(Int.self) }
                lines.append("  \(n) rows: \(differ.filter { $0 == 0 }.count)/\(n) rows equal; \(differ.reduce(0, +)) of \(n * layer.weight.dim(0)) outputs differ")
            }

            // The whole model.
            let full = try context.tokenizer.applyChatTemplate(messages: rendered, tools: nil, additionalContext: ["enable_thinking": false])
            let prompt = try context.model.newCache(parameters: parameters)
            let first = context.model(LMInput.Text(tokens: MLXArray(full))[text: .newAxis], cache: prompt, state: nil).logits
            var token = argMax(first[0, -1], axis: -1).item(Int.self)
            eval(prompt.flatMap(\.state))
            var tokens: [Int] = []
            var single: [MLXArray] = []
            let cache = prompt.map { $0.copy() }
            for _ in 0..<longest {
                tokens.append(token)
                let logits = context.model(LMInput.Text(tokens: MLXArray([token]))[text: .newAxis], cache: cache, state: nil).logits[0, 0]
                eval([logits] + cache.flatMap(\.state))
                single.append(logits)
                token = argMax(logits, axis: -1).item(Int.self)
            }
            let margins = single.map { row -> Float in
                let top = sorted(row.asType(.float32))[(-2)...].asArray(Float.self)
                return top[1] - top[0]
            }
            lines.append("Whole model, greedy continuation of a \(transcript.split(separator: " ").count)-word dictation. Logit rows equal to one-token decoding:")
            for n in lengths {
                let batched = context.model(LMInput.Text(tokens: MLXArray(Array(tokens[..<n])))[text: .newAxis], cache: prompt.map { $0.copy() }, state: nil).logits[0]
                eval(batched)
                var equal = 0, sameChoice = 0
                var largest: Float = 0
                for r in 0..<n {
                    let a = single[r].asType(.float32), b = batched[r].asType(.float32)
                    if (a .== b).all().item(Bool.self) { equal += 1 }
                    if argMax(a).item(Int.self) == argMax(b).item(Int.self) { sameChoice += 1 }
                    largest = Swift.max(largest, abs(a - b).max().item(Float.self))
                }
                lines.append("  \(n) tokens in one pass: \(equal)/\(n) rows equal, same top token \(sameChoice)/\(n), largest logit difference \(largest)")
            }
            let sortedMargins = margins.sorted()
            lines.append("Gap between the top two logits in one-token decoding over these \(longest) tokens: smallest \(sortedMargins.first ?? 0), median \(sortedMargins[sortedMargins.count / 2])")
            return lines
        }
    }

    /// Diagnostics: the median time of one forward pass over `n` new tokens after a cached cleanup prompt for
    /// `transcript`, for each `n` in `lengths`: what a prompt-lookup pass costs by how many tokens it checks.
    public func passCost(transcript: String, lengths: [Int], repeats: Int) async throws -> [(tokens: Int, ms: Double)] {
        guard loaded, let container else { throw CleanupError.unavailable("model not loaded") }
        let rendered = CleanupPrompt.messages(for: transcript, level: .light, vocabulary: [], smartFormatting: true)
            .map { ["role": $0.role.rawValue, "content": $0.content] as [String: any Sendable] }
        let parameters = GenerateParameters(temperature: 0)
        return try await container.perform(values: rendered) { context, rendered in
            let full = try context.tokenizer.applyChatTemplate(messages: rendered, tools: nil, additionalContext: ["enable_thinking": false])
            let prompt = try context.model.newCache(parameters: parameters)
            _ = context.model(LMInput.Text(tokens: MLXArray(full))[text: .newAxis], cache: prompt, state: nil)
            eval(prompt.flatMap(\.state))
            var results: [(tokens: Int, ms: Double)] = []
            for n in lengths {
                let tokens = LMInput.Text(tokens: MLXArray(Array(full.suffix(n + 1).prefix(n))))[text: .newAxis]
                var times: [Double] = []
                for _ in 0..<repeats {
                    let cache = prompt.map { $0.copy() }
                    // One token first, so the timed pass writes into caches that have already grown.
                    let warm = context.model(LMInput.Text(tokens: MLXArray([full[full.count - 1]]))[text: .newAxis], cache: cache, state: nil)
                    eval([argMax(warm.logits[0], axis: -1)] + cache.flatMap(\.state))
                    let start = Date.timeIntervalSinceReferenceDate
                    let out = context.model(tokens, cache: cache, state: nil)
                    eval([argMax(out.logits[0], axis: -1)] + cache.flatMap(\.state))
                    times.append((Date.timeIntervalSinceReferenceDate - start) * 1000)
                }
                results.append((n, times.sorted()[times.count / 2]))
            }
            return results
        }
    }

    /// Where the last user message starts in the rendered prompt: the first token that differs from the same
    /// conversation with that message empty. Prompt-lookup guesses come from there on.
    static func dictationStart(of full: [Int], request: Request, context: ModelContext) throws -> Int {
        let probe = Array(request.rendered.dropLast()) + [["role": "user", "content": ""] as [String: any Sendable]]
        let head = try context.tokenizer.applyChatTemplate(messages: probe, tools: nil, additionalContext: ["enable_thinking": false])
        return min(zip(full, head).prefix { $0 == $1 }.count, full.count - 1)
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
