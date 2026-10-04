import Core
import Foundation

public enum GuardFlag: Sendable, Codable, Equatable, CustomStringConvertible {
    case empty
    case artifact(String)
    case numberAdded(String)
    case numberRemoved(String)
    case urlAdded(String)
    case urlRemoved(String)
    case nameAdded(String)
    case nameRemoved(String)
    case negationChanged(from: Int, to: Int)
    case protectedSpanChanged(String)
    case placeholderLost(String)
    case lengthRatio(Double)

    public var description: String {
        switch self {
        case .empty: "empty output"
        case .artifact(let s): "model artifact \"\(s)\""
        case .numberAdded(let s): "number added: \(s)"
        case .numberRemoved(let s): "number removed: \(s)"
        case .urlAdded(let s): "url added: \(s)"
        case .urlRemoved(let s): "url removed: \(s)"
        case .nameAdded(let s): "name added: \(s)"
        case .nameRemoved(let s): "name removed: \(s)"
        case .negationChanged(let a, let b): "negations \(a) -> \(b)"
        case .protectedSpanChanged(let s): "quoted or code span changed: \(s)"
        case .placeholderLost(let s): "snippet placeholder lost: \(s)"
        case .lengthRatio(let r): String(format: "length ratio %.2f", r)
        }
    }

    /// Short machine-readable kind for result tables.
    public var kind: String {
        switch self {
        case .empty: "empty"
        case .artifact: "artifact"
        case .numberAdded, .numberRemoved: "number"
        case .urlAdded, .urlRemoved: "url"
        case .nameAdded, .nameRemoved: "name"
        case .negationChanged: "negation"
        case .protectedSpanChanged: "protected"
        case .placeholderLost: "placeholder"
        case .lengthRatio: "length"
        }
    }
}

/// Compares the rule-cleaned input with the model's output and flags any change to facts.
/// Numbers, URLs, names and negations may never be added or altered. They may only be removed
/// when the speaker corrected themselves ("2, actually 3"), which is what backtracking does.
public struct GuardChecker: Sendable {
    public var minRatio: Double
    public var maxRatio: Double
    /// Lower bound when the input contains a self-correction, since backtracking removes words.
    public var minRatioWithCorrection: Double

    public init(minRatio: Double = 0.55, maxRatio: Double = 1.35, minRatioWithCorrection: Double = 0.25) {
        self.minRatio = minRatio
        self.maxRatio = maxRatio
        self.minRatioWithCorrection = minRatioWithCorrection
    }

    static let correctionCues = [
        "actually", "i mean", "no wait", "wait no", "wait,", "sorry", "scratch that", "make that", "rather",
        "correction", "or rather", "let me rephrase", "instead", "change that to", "oops", "no no",
    ]

    static let artifacts = [
        "<think", "</think", "<transcript", "</transcript", "here is the", "here's the", "cleaned text:",
        "cleaned-up", "corrected text:", "transcript:", "as an ai", "i'm sorry, but", "i cannot",
    ]

    static let negationWords: Set<String> = [
        "not", "no", "never", "nothing", "nobody", "none", "nowhere", "neither", "nor", "cannot", "without",
    ]

    public static func hasCorrectionCue(_ text: String) -> Bool {
        let t = text.lowercased()
        return correctionCues.contains { t.contains($0) }
    }

    public func check(input: String, output: String, placeholders: [String] = []) -> [GuardFlag] {
        var flags: [GuardFlag] = []
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.empty]
        }
        let lowerOut = trimmed.lowercased()
        let lowerIn = input.lowercased()
        for a in Self.artifacts where lowerOut.contains(a) && !lowerIn.contains(a) {
            flags.append(.artifact(a))
        }

        let corrected = Self.hasCorrectionCue(input)

        // Numbers, compared in digit form so "three" -> "3" is not a change.
        let numIn = Self.numbers(input), numOut = Self.numbers(trimmed)
        for n in numOut.subtracting(numIn) { flags.append(.numberAdded(n)) }
        if !corrected { for n in numIn.subtracting(numOut) { flags.append(.numberRemoved(n)) } }

        let urlIn = Self.urls(input), urlOut = Self.urls(trimmed)
        for u in urlOut.subtracting(urlIn) { flags.append(.urlAdded(u)) }
        if !corrected { for u in urlIn.subtracting(urlOut) { flags.append(.urlRemoved(u)) } }

        // Names: capitalized words that are not sentence-initial. Compared lowercased, and a name in the
        // output is fine if the same word appears anywhere in the input in any case.
        let wordsIn = Set(Self.words(input).map { $0.lowercased() })
        let namesIn = Self.names(input), namesOut = Self.names(trimmed)
        for n in namesOut where !wordsIn.contains(n) { flags.append(.nameAdded(n)) }
        if !corrected {
            let wordsOut = Set(Self.words(trimmed).map { $0.lowercased() })
            for n in namesIn where !wordsOut.contains(n) { flags.append(.nameRemoved(n)) }
        }

        let negIn = Self.negationCount(input), negOut = Self.negationCount(trimmed)
        if corrected ? negOut > negIn : negOut != negIn {
            flags.append(.negationChanged(from: negIn, to: negOut))
        }

        for span in Self.protectedSpans(input) where !trimmed.contains(span) {
            flags.append(.protectedSpanChanged(span))
        }
        for p in placeholders where input.contains(p) && !trimmed.contains(p) {
            flags.append(.placeholderLost(p))
        }

        let inCount = Self.words(input).count, outCount = Self.words(trimmed).count
        if inCount >= 4 {
            let ratio = Double(outCount) / Double(inCount)
            let lower = corrected ? minRatioWithCorrection : minRatio
            if ratio < lower || ratio > maxRatio { flags.append(.lengthRatio(ratio)) }
        } else if outCount > inCount + 4 {
            flags.append(.lengthRatio(Double(outCount) / Double(max(inCount, 1))))
        }
        return flags
    }

    // MARK: - Extraction

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }).map(String.init)
    }

    static func numbers(_ text: String) -> Set<String> {
        // Strip URLs first so their digits are compared as part of the URL instead.
        var t = text
        for u in urls(text) { t = t.replacingOccurrences(of: u, with: " ", options: .caseInsensitive) }
        let lowered = t.lowercased()
            .replacingOccurrences(of: #"(\d),(\d{3})\b"#, with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        let tokens = lowered.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == ":") })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:")) }
        // Times and decimals stay whole (4:30, 3.5); number words become digits.
        var out: Set<String> = []
        var wordRun: [String] = []
        func flushRun() {
            if !wordRun.isEmpty {
                for w in NumberWords.collapse(wordRun) where w.first?.isNumber == true { out.insert(w) }
                wordRun = []
            }
        }
        for tok in tokens {
            if tok.first?.isNumber == true {
                flushRun()
                out.insert(tok)
            } else if NumberWords.isNumberWord(tok) || (tok == "and" && !wordRun.isEmpty) {
                wordRun.append(tok)
            } else {
                flushRun()
            }
        }
        flushRun()
        return out
    }

    static func urls(_ text: String) -> Set<String> {
        let pattern = #"(?i)\b(?:https?://)?(?:[a-z0-9-]+\.)+(?:com|org|net|io|dev|app|ai|co|edu|gov|me|xyz|uk|us|de|fr)(?:/[^\s,;)]*)?|[\w.+-]+@[\w-]+\.[\w.]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        })
    }

    static let commonCapitalized: Set<String> = [
        "i", "i'm", "i'll", "i've", "i'd", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december", "ok", "okay",
    ]

    static func names(_ text: String) -> Set<String> {
        var out: Set<String> = []
        var sentenceStart = true
        var token = ""
        func finish(_ next: Character?) {
            guard !token.isEmpty else { return }
            if !sentenceStart, let first = token.first, first.isUppercase {
                let lower = token.lowercased()
                if !commonCapitalized.contains(lower) { out.insert(lower) }
            }
            sentenceStart = false
            token = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" {
                token.append(ch)
            } else {
                finish(ch)
                if ".!?\n:\u{201C}\"".contains(ch) { sentenceStart = true }
            }
        }
        finish(nil)
        return out
    }

    public static func negationCount(_ text: String) -> Int {
        words(text.lowercased()).reduce(0) { count, w in
            let w = w.replacingOccurrences(of: "’", with: "'")
            return count + ((negationWords.contains(w) || w.hasSuffix("n't")) ? 1 : 0)
        }
    }

    /// Text inside quotes or backticks must survive verbatim.
    static func protectedSpans(_ text: String) -> [String] {
        let pattern = #"`[^`]+`|\u201C[^\u201D]+\u201D|"[^"]+""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            Range(m.range, in: text).map { String(text[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "`\"\u{201C}\u{201D}")) }
        }
    }
}
