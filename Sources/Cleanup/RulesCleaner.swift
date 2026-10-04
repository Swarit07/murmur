import Foundation

public struct DictionaryEntry: Sendable, Codable, Equatable {
    /// What the engine tends to produce, matched case-insensitively on word boundaries.
    public var term: String
    /// What should be written instead.
    public var replacement: String

    public init(term: String, replacement: String) {
        self.term = term
        self.replacement = replacement
    }
}

public struct Snippet: Sendable, Codable, Equatable {
    public var cue: String
    public var expansion: String

    public init(cue: String, expansion: String) {
        self.cue = cue
        self.expansion = expansion
    }
}

/// Text after the rules stage. Snippet expansions are held back as placeholders so the LLM stage
/// cannot alter them; `restore` puts them back.
public struct RulesOutput: Sendable, Equatable {
    public var text: String
    public var placeholders: [String: String]

    public func restore(_ s: String) -> String {
        placeholders.reduce(s) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    public var restoredText: String { restore(text) }
}

/// Deterministic cleanup: fillers, spoken punctuation and layout, dictionary fixes, snippet placeholders.
/// Runs in well under the 5 ms budget for normal dictation lengths.
public struct RulesCleaner: Sendable {
    public var dictionary: [DictionaryEntry]
    public var snippets: [Snippet]
    public var removeFillers: Bool

    public init(dictionary: [DictionaryEntry] = [], snippets: [Snippet] = [], removeFillers: Bool = true) {
        self.dictionary = dictionary
        self.snippets = snippets
        self.removeFillers = removeFillers
    }

    /// Hesitation sounds only. Words like "like" or "so" carry meaning too often to drop by rule;
    /// the LLM stage handles those.
    static let fillers = ["um", "umm", "uh", "uhh", "uh-huh-uh", "er", "erm", "ah", "hmm", "hm", "mm", "mmm"]

    /// Spoken punctuation, longest phrases first. `attach` means no space before the mark.
    static let spokenPunctuation: [(phrase: String, mark: String)] = [
        ("new paragraph", "\n\n"),
        ("next paragraph", "\n\n"),
        ("new line", "\n"),
        ("newline", "\n"),
        ("next line", "\n"),
        ("question mark", "?"),
        ("exclamation point", "!"),
        ("exclamation mark", "!"),
        ("full stop", "."),
        ("period", "."),
        ("comma", ","),
        ("semicolon", ";"),
        ("colon", ":"),
        ("open quote", "\u{201C}"),
        ("close quote", "\u{201D}"),
        ("end quote", "\u{201D}"),
        ("open paren", "("),
        ("close paren", ")"),
        ("dash dash", " — "),
        ("em dash", " — "),
    ]

    public func apply(_ input: String) -> RulesOutput {
        var text = input
        var placeholders: [String: String] = [:]

        // 1. Snippets become protected placeholders first, so later rules cannot touch them.
        for (index, snippet) in snippets.enumerated() where !snippet.cue.isEmpty {
            let key = "\u{27E6}S\(index)\u{27E7}"
            let pattern = #"(?i)\b"# + NSRegularExpression.escapedPattern(for: snippet.cue) + #"\b[.!?,]?"#
            if text.range(of: pattern, options: .regularExpression) != nil {
                text = text.replacingOccurrences(of: pattern, with: key, options: .regularExpression)
                placeholders[key] = snippet.expansion
            }
        }

        // 2. Fillers, with the comma or ellipsis an engine often puts after them.
        if removeFillers {
            let alternatives = Self.fillers.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            text = text.replacingOccurrences(
                of: #"(?i)(^|(?<=[\s,.;:!?]))(\#(alternatives))(\.\.\.|…|[,.])?(?=\s|$|[,.;:!?])"#,
                with: "", options: .regularExpression)
        }

        // 3. Spoken punctuation and layout. Engines sometimes already add a comma or period around
        // the spoken word ("comma," / ", comma"), so swallow adjacent marks.
        for (phrase, mark) in Self.spokenPunctuation {
            let words = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let body = words.joined(separator: #"[\s,.]+"#)
            let pattern = #"(?i)[\s,.]*\b"# + body + #"\b[,.]?"#
            let replacement: String
            switch mark {
            case "\n", "\n\n": replacement = mark
            case "\u{201C}", "(": replacement = " " + mark
            case " — ": replacement = mark
            default: replacement = mark
            }
            text = text.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: replacement), options: .regularExpression)
        }

        // 4. Dictionary fixes, longest term first.
        for entry in dictionary.sorted(by: { $0.term.count > $1.term.count }) where !entry.term.isEmpty {
            let pattern = #"(?i)(?<![\w])"# + NSRegularExpression.escapedPattern(for: entry.term) + #"(?![\w])"#
            text = text.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: entry.replacement), options: .regularExpression)
        }

        return RulesOutput(text: Self.tidy(text), placeholders: placeholders)
    }

    /// Spacing and capitalization after the edits above.
    static func tidy(_ input: String) -> String {
        var t = input
        // Spaces around line breaks, and runs of spaces.
        t = t.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        // No space before closing marks; collapse duplicate marks (", ," or ".,").
        t = t.replacingOccurrences(of: #"\s+([,.;:!?”)])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([,;:])[,;:]+"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[,;:]([.!?])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([.!?])[.,]+"#, with: "$1", options: .regularExpression)
        // No space after opening marks.
        t = t.replacingOccurrences(of: #"([“(])\s+"#, with: "$1", options: .regularExpression)
        // Space after a mark when a word follows directly.
        t = t.replacingOccurrences(of: #"([,;:!?])(?=[A-Za-z“(])"#, with: "$1 ", options: .regularExpression)
        // Leading punctuation left behind by a removed filler.
        t = t.replacingOccurrences(of: #"(^|\n)[ ,;:]+"#, with: "$1", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #"^\s+|\s+$"#, with: "", options: .regularExpression)
        return capitalizeSentences(t)
    }

    /// Capitalizes the first letter of the text and of each sentence. A mark only ends a sentence
    /// when whitespace follows it, so "3.5" and "murmur.app" are left alone.
    static func capitalizeSentences(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        var capitalizeNext = true
        var afterMark = false
        for ch in input {
            if afterMark {
                afterMark = false
                if ch.isWhitespace { capitalizeNext = true }
            }
            if capitalizeNext, ch.isLetter {
                out.append(contentsOf: ch.uppercased())
                capitalizeNext = false
                continue
            }
            out.append(ch)
            if ch == "\n" {
                capitalizeNext = true
            } else if ".!?".contains(ch) {
                afterMark = true
            } else if !ch.isWhitespace && ch != "\u{201C}" && ch != "(" {
                capitalizeNext = false
            }
        }
        return out
    }
}
