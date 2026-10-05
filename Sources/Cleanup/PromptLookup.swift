import Foundation

/// Guesses the next tokens of a cleanup from the dictation itself (prompt-lookup decoding).
///
/// A cleaned dictation is mostly a copy of the transcript, so whatever followed the output's last few tokens
/// in the transcript is a good guess for what comes next. The model checks a guess in one forward pass and
/// keeps only the part it would have written anyway, so a wrong guess costs time, never output.
public struct PromptLookupDrafter: Sendable {
    /// The tokens guesses are copied from: the dictation and the rest of the prompt after it.
    public let source: [Int]
    /// The longest run of output tokens to look up. Shorter runs are tried when it is not found.
    public let longest: Int
    /// Where the last guess started in `source`. The output follows the transcript in order, so a match at
    /// or after this point wins over an earlier one when a word appears more than once.
    public private(set) var cursor = 0
    /// Every position of each token in `source`, in increasing order.
    private let positions: [Int: [Int]]

    public init(source: [Int], longest: Int = 3) {
        self.source = source
        self.longest = max(1, longest)
        var positions: [Int: [Int]] = [:]
        for (i, token) in source.enumerated() { positions[token, default: []].append(i) }
        self.positions = positions
    }

    /// Up to `count` tokens to follow `history`, or none when the end of `history` is not in the source.
    public mutating func draft(after history: [Int], count: Int) -> [Int] {
        guard count > 0, !history.isEmpty else { return [] }
        for n in stride(from: min(longest, history.count), through: 1, by: -1) {
            let tail = history.suffix(n)
            guard let starts = positions[tail.first!] else { continue }
            var after: Int?
            var before: Int?
            for s in starts where s + n < source.count && source[s..<(s + n)].elementsEqual(tail) {
                if s + n >= cursor {
                    after = s + n
                    break
                }
                before = s + n
            }
            if let next = after ?? before {
                cursor = next
                return Array(source[next..<min(next + count, source.count)])
            }
        }
        return []
    }
}

/// Picks how many guessed tokens a pass checks, from how often guesses have been right and what a pass costs.
///
/// On MLX a pass is not free beyond two tokens: it costs about the same for 1–2 tokens, then grows by about a
/// third of a one-token pass per extra token up to 10, then stays flat from 13 to 32 (`murmur-bench
/// pass-cost`). So a guess should be short when guesses keep failing and long when the output is copying the
/// dictation.
public struct GuessSizer: Sendable {
    /// Time of a pass over n tokens (index n - 1) relative to a one-token pass, measured on an M4 Pro with
    /// Qwen3.5 4B 4-bit and smoothed. Longer passes are not considered.
    public static let m4Pro: [Double] = [
        1.00, 1.03, 1.26, 1.51, 1.81, 2.20, 2.67, 2.72, 3.30, 3.34, 4.10, 4.10, 4.20, 4.20, 4.20, 4.20,
        4.20, 4.20, 4.20, 4.25, 4.30, 4.35, 4.40, 4.40, 4.40, 4.40, 4.40, 4.40, 4.40, 4.40, 4.40, 4.40,
    ]

    public let cost: [Double]
    /// The chance that a guessed token is right when the ones before it were, learned as the output goes.
    public private(set) var acceptance: Double
    let rate: Double

    public init(cost: [Double] = GuessSizer.m4Pro, acceptance: Double = 0.85, rate: Double = 0.15) {
        self.cost = cost
        self.acceptance = acceptance
        self.rate = rate
    }

    /// How many of `available` guessed tokens to check in a pass that also feeds `fixed` tokens (the newest
    /// token and any being replayed): the count with the most expected new tokens per unit of time.
    public func length(available: Int, fixed: Int) -> Int {
        var best = 0, bestRate = 0.0
        var expected = 1.0, term = 1.0
        for k in 0...max(0, available) {
            if k > 0 {
                term *= acceptance
                expected += term
            }
            guard fixed + k <= cost.count else { break }
            let rate = expected / cost[fixed + k - 1]
            if rate > bestRate {
                best = k
                bestRate = rate
            }
        }
        return best
    }

    /// Learns from a pass in which `kept` of `checked` guessed tokens were right.
    public mutating func record(kept: Int, checked: Int) {
        for _ in 0..<kept { acceptance += rate * (1 - acceptance) }
        if kept < checked { acceptance -= rate * acceptance }
    }
}

/// What prompt-lookup decoding did in one generation. Counts only, never text.
public struct PromptLookupStats: Sendable, Codable, Equatable {
    /// Forward passes after the prompt, each checking one guess (possibly empty).
    public var passes = 0
    /// Tokens produced by those passes, including any past the stop token.
    public var tokens = 0
    /// Guessed tokens checked, and how many of them the model kept.
    public var drafted = 0
    public var accepted = 0
    /// Accepted tokens fed through the model a second time, after a rejected guess rolled back the
    /// recurrent layers' state.
    public var replayed = 0
    /// Passes whose guess was cut short by the model.
    public var rollbacks = 0

    public init() {}

    public var acceptance: Double { drafted == 0 ? 0 : Double(accepted) / Double(drafted) }
    public var tokensPerPass: Double { passes == 0 ? 0 : Double(tokens) / Double(passes) }

    public static func + (a: Self, b: Self) -> Self {
        var s = a
        s.passes += b.passes
        s.tokens += b.tokens
        s.drafted += b.drafted
        s.accepted += b.accepted
        s.replayed += b.replayed
        s.rollbacks += b.rollbacks
        return s
    }
}
