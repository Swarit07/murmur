import Core
import Foundation

public struct CleanupOutcome: Sendable {
    public enum Fallback: String, Sendable, Codable {
        case timeout
        case guardFlagged = "guard"
        case providerError = "error"
    }

    /// What gets inserted.
    public var text: String
    /// Rule-cleaned text with snippets restored. Always available as the fallback.
    public var rulesText: String
    /// The model's output before guard checks, if the model finished.
    public var modelText: String?
    public var fallback: Fallback?
    public var flags: [GuardFlag]
    public var error: String?
    public var rulesMs: Double
    public var llmMs: Double?
}

/// Rules, then the model with a hard time limit, then guard checks. The rule-cleaned text is
/// returned whenever the model is slow, fails, or changes a fact.
public struct CleanupRunner: Sendable {
    public var rules: RulesCleaner
    public var provider: (any CleanupProvider)?
    public var guardChecker: GuardChecker
    public var timeLimit: Duration

    public init(
        rules: RulesCleaner = RulesCleaner(),
        provider: (any CleanupProvider)?,
        guardChecker: GuardChecker = GuardChecker(),
        timeLimit: Duration = .milliseconds(800)
    ) {
        self.rules = rules
        self.provider = provider
        self.guardChecker = guardChecker
        self.timeLimit = timeLimit
    }

    /// Warms the provider for this request's instructions (dictionary, level, formatting), so the first
    /// dictation after a change does not pay for reading them.
    public func prewarm(_ request: CleanupRequest) async {
        guard let provider, request.level != .none else { return }
        await provider.prewarm(CleanupPrompt.messages(
            for: "OK", level: request.level, vocabulary: request.vocabulary, smartFormatting: request.smartFormatting))
    }

    public func run(_ transcript: String, request: CleanupRequest = CleanupRequest()) async -> CleanupOutcome {
        if request.level == .none {
            return CleanupOutcome(text: transcript, rulesText: transcript, modelText: nil, fallback: nil, flags: [], error: nil, rulesMs: 0, llmMs: nil)
        }
        let (ruled, rulesMs) = await Signposts.measure(.rules) { rules.apply(transcript) }
        let rulesText = ruled.restoredText
        guard let provider, !ruled.text.isEmpty else {
            return CleanupOutcome(text: rulesText, rulesText: rulesText, modelText: nil, fallback: nil, flags: [], error: nil, rulesMs: rulesMs, llmMs: nil)
        }

        let messages = CleanupPrompt.messages(
            for: ruled.text, level: request.level, vocabulary: request.vocabulary, smartFormatting: request.smartFormatting)
        let maxTokens = CleanupPrompt.maxTokens(for: ruled.text)
        let limit = Self.limit(timeLimit, words: ruled.text.split(whereSeparator: \.isWhitespace).count)
        let (result, llmMs) = await Signposts.measure(.llm) {
            await Self.withTimeLimit(limit) {
                try await provider.complete(messages, maxTokens: maxTokens)
            }
        }

        switch result {
        case .timedOut:
            return CleanupOutcome(text: rulesText, rulesText: rulesText, modelText: nil, fallback: .timeout, flags: [], error: nil, rulesMs: rulesMs, llmMs: llmMs)
        case .failed(let error):
            return CleanupOutcome(text: rulesText, rulesText: rulesText, modelText: nil, fallback: .providerError, flags: [], error: String(describing: error), rulesMs: rulesMs, llmMs: llmMs)
        case .finished(let raw):
            let cleaned = CleanupPrompt.strip(raw)
            let flags = guardChecker.check(
                input: ruled.text, output: cleaned, placeholders: Array(ruled.placeholders.keys),
                allowReorder: request.level == .medium, vocabulary: request.vocabulary, allowListMarkers: request.smartFormatting)
            if !flags.isEmpty {
                return CleanupOutcome(text: rulesText, rulesText: rulesText, modelText: cleaned, fallback: .guardFlagged, flags: flags, error: nil, rulesMs: rulesMs, llmMs: llmMs)
            }
            return CleanupOutcome(text: ruled.restore(cleaned), rulesText: rulesText, modelText: cleaned, fallback: nil, flags: [], error: nil, rulesMs: rulesMs, llmMs: llmMs)
        }
    }

    /// C6, as amended 2026-10-05: the base limit plus 10 ms per word over 30, at most 450 ms more, so a
    /// long dictation can finish cleanup while a stalled model still lands text within 1.5 s.
    public static func limit(_ base: Duration, words: Int) -> Duration {
        base + .milliseconds(min(450, 10 * max(0, words - 30)))
    }

    enum Timed<T: Sendable>: Sendable {
        case finished(T)
        case failed(any Error)
        case timedOut
    }

    /// Races `body` against a timer and cancels the loser. Returns as soon as the limit passes even if
    /// the body ignores cancellation, so a stalled model can never hold up insertion.
    static func withTimeLimit<T: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async throws -> T) async -> Timed<T> {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let work = Task {
                let result: Timed<T>
                do { result = .finished(try await body()) } catch { result = .failed(error) }
                once.resume(result)
            }
            Task {
                try? await Task.sleep(for: limit)
                if once.resume(.timedOut) { work.cancel() }
            }
        }
    }
}

/// Resumes a continuation exactly once with whichever result arrives first.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    /// Returns true if this call won.
    @discardableResult
    func resume(_ value: T) -> Bool {
        let c: CheckedContinuation<T, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        c?.resume(returning: value)
        return c != nil
    }
}
