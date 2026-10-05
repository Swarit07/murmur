import Cleanup
import Foundation
import MLX
import MLXLMCommon

/// Greedy generation that checks prompt-lookup guesses (`PromptLookupDrafter`) in one forward pass each.
///
/// Every token it returns is the argmax of the model's logits given all the tokens before it: a guessed
/// token is kept only when it equals that argmax, and the first token the model disagrees on is the model's
/// own. A pass over a few tokens reads the weights once, so each accepted guess saves part of a decoding step.
///
/// Not bit-identical to `TokenIterator`. MLX multiplies a quantized layer by several rows with other kernels
/// (`qmv_wide`, `qmm`) than by one row (`qmv`), which add in another order, so the logits differ in their
/// last bits (up to about 0.3) and a near-tie between two tokens can go the other way
/// (docs/cleanup-speed.md, `murmur-bench numerics-test`).
///
/// Rolling back a rejected guess. Attention layers keep a KV cache, which trims. Qwen3.5's GatedDeltaNet
/// layers keep a recurrent state that has absorbed every token of the pass and cannot be trimmed. Before a
/// pass the iterator keeps a reference to each recurrent state (MLX arrays are immutable, so this copies
/// nothing). When the model rejects part of the guess, it puts those states back, trims the attention caches
/// by the whole pass, and feeds the kept tokens again at the front of the next pass, where they ride along
/// with the next guess. Models whose caches all trim (Qwen3) just trim the rejected tokens.
struct PromptLookupTokenIterator: TokenIteratorProtocol {
    /// How replayed tokens are fed after a rollback: with the next guess, or in a pass of their own.
    enum Replay: String, Sendable { case nextPass = "next", ownPass = "own" }

    struct Settings: Sendable {
        /// Most guessed tokens per pass.
        var maxDraft = 31
        /// Most tokens per pass, replayed ones included.
        var maxPass = 32
        /// Longest run of output tokens looked up in the dictation.
        var ngram = 3
        var replay = Replay.nextPass
        /// Size each guess with `GuessSizer`. Off, every guess is as long as the limits allow.
        var adaptive = true

        static func fromEnvironment() -> Settings {
            let env = ProcessInfo.processInfo.environment
            var s = Settings()
            if env["MURMUR_LOOKUP_FIXED"] == "1" { s.adaptive = false }
            if let v = env["MURMUR_LOOKUP_DRAFT"].flatMap(Int.init) { s.maxDraft = Swift.max(0, v) }
            if let v = env["MURMUR_LOOKUP_PASS"].flatMap(Int.init) { s.maxPass = Swift.max(1, v) }
            if let v = env["MURMUR_LOOKUP_NGRAM"].flatMap(Int.init) { s.ngram = Swift.max(1, v) }
            if let v = env["MURMUR_LOOKUP_REPLAY"].flatMap(Replay.init) { s.replay = v }
            return s
        }
    }

    let model: any LanguageModel
    let cache: [KVCache]
    /// The recurrent-state caches, which roll back by snapshot instead of trimming.
    let recurrent: [MambaCache]
    let sampler: LogitSampler
    let settings: Settings
    var drafter: PromptLookupDrafter
    var sizer = GuessSizer()
    let stats: PromptLookupStatsBox

    public let maxTokens: Int?
    public var tokenCount = 0
    public var promptPrefillTime: TimeInterval = 0

    /// Every token produced so far, for lookups.
    var history: [Int] = []
    /// The newest token: already returned (or about to be), not yet fed to the model.
    var last = 0
    /// Accepted tokens before `last` that the caches lost in a rollback and must be fed again.
    var replay: [Int] = []
    var pending: [Int] = []
    var pendingIndex = 0
    /// When to next return MLX's unusable freed buffers.
    var nextClear = 0

    /// Returns nil when this model's caches cannot be rolled back, or the parameters are not greedy, so the
    /// caller uses `TokenIterator`.
    init?(
        input: LMInput, model: any LanguageModel, cache: [KVCache], source: [Int], parameters: GenerateParameters,
        settings: Settings, stats: PromptLookupStatsBox
    ) throws {
        guard parameters.temperature == 0, parameters.processor() == nil else { return nil }
        var recurrent: [MambaCache] = []
        for entry in cache {
            if entry.isTrimmable { continue }
            guard let state = entry as? MambaCache else { return nil }
            recurrent.append(state)
        }
        self.model = model
        self.cache = cache
        self.recurrent = recurrent
        self.sampler = parameters.sampler()
        self.settings = settings
        self.drafter = PromptLookupDrafter(source: source, longest: settings.ngram)
        self.stats = stats
        self.maxTokens = parameters.maxTokens

        // The prompt goes through exactly as in `TokenIterator`, so the first token is the same.
        let start = Date.timeIntervalSinceReferenceDate
        let logits: MLXArray
        switch try model.prepare(input, cache: cache, state: nil, prefill: parameters.prefill) {
        case .tokens(let remaining):
            logits = model(remaining[text: .newAxis], cache: cache, state: nil).logits
        case .logits(let result):
            logits = result.logits
        }
        let first = sampler.sample(logits: logits[0..., -1, 0...])
        eval([first] + cache.flatMap(\.state))
        last = first.item(Int.self)
        history = [last]
        pending = [last]
        promptPrefillTime = Date.timeIntervalSinceReferenceDate - start
    }

    mutating func next() -> Int? {
        if let maxTokens, tokenCount >= maxTokens { return nil }
        if pendingIndex == pending.count {
            // Return MLX's unusable freed buffers after the prompt and every 256 tokens, as `TokenIterator` does.
            if tokenCount >= nextClear {
                MLX.Memory.clearCache()
                nextClear = tokenCount + 256
            }
            autoreleasepool { round() }
        }
        let token = pending[pendingIndex]
        pendingIndex += 1
        tokenCount += 1
        return token
    }

    /// One forward pass: replayed tokens, the newest token, then the guess. Leaves the tokens it produced in
    /// `pending`.
    mutating func round() {
        if settings.replay == .ownPass, !replay.isEmpty {
            _ = model(LMInput.Text(tokens: MLXArray(replay.map(Int32.init)))[text: .newAxis], cache: cache, state: nil)
            eval(cache.flatMap(\.state))
            stats.value.replayed += replay.count
            replay = []
        }
        // Guess no further than the token budget: a pass always produces at least one token of its own.
        let budget = maxTokens.map { $0 - tokenCount - 1 } ?? .max
        let room = Swift.min(settings.maxDraft, settings.maxPass - replay.count - 1, budget)
        var guess = room > 0 ? drafter.draft(after: history, count: room) : []
        if settings.adaptive { guess = Array(guess.prefix(sizer.length(available: guess.count, fixed: replay.count + 1))) }

        let fed = replay + [last] + guess
        let saved = guess.isEmpty ? [] : recurrent.map { ($0[0], $0[1]) }
        let logits = model(LMInput.Text(tokens: MLXArray(fed.map(Int32.init)))[text: .newAxis], cache: cache, state: nil).logits
        // The model's own choice after `last` and after each guessed token.
        let chosen = sampler.sample(logits: logits[0, replay.count..., 0...])
        eval([chosen] + cache.flatMap(\.state))
        let picks = chosen.asArray(Int.self)

        var kept = 0
        while kept < guess.count, guess[kept] == picks[kept] { kept += 1 }
        sizer.record(kept: kept, checked: guess.count)
        let produced = Array(guess[..<kept]) + [picks[kept]]

        var s = stats.value
        s.passes += 1
        s.tokens += produced.count
        s.drafted += guess.count
        s.accepted += kept
        s.replayed += replay.count
        if kept < guess.count {
            s.rollbacks += 1
            let rejected = guess.count - kept
            if recurrent.isEmpty {
                // Every cache trims: drop the rejected tokens and keep the rest.
                for entry in cache { entry.trim(rejected) }
                replay = []
            } else {
                // Put the recurrent states back as they were before the pass, take the whole pass back out of
                // the attention caches, and feed the kept tokens again next time.
                for (state, (conv, recurrentState)) in zip(recurrent, saved) {
                    state[0] = conv
                    state[1] = recurrentState
                }
                for entry in cache where entry.isTrimmable { entry.trim(fed.count) }
                replay = fed.dropLast(rejected)
            }
        } else {
            replay = []
        }
        stats.value = s

        last = produced.last!
        history += produced
        pending = produced
        pendingIndex = 0
    }
}

/// Where a `PromptLookupTokenIterator` leaves its counts. Written only by the generation task, and read
/// after it has finished.
final class PromptLookupStatsBox: @unchecked Sendable {
    var value = PromptLookupStats()
}
