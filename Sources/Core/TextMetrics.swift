import Foundation

/// Word error rate and the normalizer it uses. The normalizer is deliberately simple and applied to
/// both sides, so it is fair across engines: lowercase, written numbers and number words both become
/// digits, punctuation becomes spaces, and a few spoken symbols are mapped to words.
public enum TextMetrics {
    public struct WERResult: Sendable, Codable, Equatable {
        public var substitutions: Int
        public var deletions: Int
        public var insertions: Int
        public var referenceWords: Int

        public var errors: Int { substitutions + deletions + insertions }
        public var rate: Double { referenceWords == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(referenceWords) }

        public static func + (a: WERResult, b: WERResult) -> WERResult {
            WERResult(
                substitutions: a.substitutions + b.substitutions,
                deletions: a.deletions + b.deletions,
                insertions: a.insertions + b.insertions,
                referenceWords: a.referenceWords + b.referenceWords
            )
        }

        public static let zero = WERResult(substitutions: 0, deletions: 0, insertions: 0, referenceWords: 0)
    }

    public static func wer(reference: String, hypothesis: String) -> WERResult {
        let ref = normalizedWords(reference)
        let hyp = normalizedWords(hypothesis)
        return align(ref, hyp)
    }

    public static func normalizedWords(_ text: String) -> [String] {
        var t = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")).lowercased()
        // Contractions and possessives: keep them as one word.
        t = t.replacingOccurrences(of: "’", with: "'")
        let symbolWords: [(String, String)] = [
            ("%", " percent "), ("&", " and "), ("@", " at "), ("+", " plus "), ("$", " dollar "),
        ]
        for (symbol, word) in symbolWords { t = t.replacingOccurrences(of: symbol, with: word) }
        // Ordinal suffixes on digits: 3rd -> 3.
        t = t.replacingOccurrences(of: #"(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        // Thousands separators: 1,500 -> 1500.
        t = t.replacingOccurrences(of: #"(\d),(\d{3})\b"#, with: "$1$2", options: .regularExpression)
        // Everything that is not a letter, digit or apostrophe separates words.
        t = t.replacingOccurrences(of: #"[^a-z0-9']+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(^|\s)'+|'+(\s|$)"#, with: " ", options: .regularExpression)
        var words = t.split(separator: " ").map(String.init)
        words = NumberWords.collapse(words)
        // Common spelling variants.
        let variants: [String: String] = ["ok": "okay", "dollars": "dollar", "percent": "percent", "mr": "mister", "dr": "doctor"]
        // Hesitation sounds are not counted: references include them, and engines differ on keeping them.
        let hesitations: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "hm", "mm", "mmm"]
        return words.filter { !hesitations.contains($0) }.map { variants[$0] ?? $0 }
    }

    static func align(_ ref: [String], _ hyp: [String]) -> WERResult {
        let n = ref.count, m = hyp.count
        if n == 0 { return WERResult(substitutions: 0, deletions: 0, insertions: m, referenceWords: 0) }
        if m == 0 { return WERResult(substitutions: 0, deletions: n, insertions: 0, referenceWords: n) }
        // (cost, subs, dels, ins)
        var prev = [(Int, Int, Int, Int)](repeating: (0, 0, 0, 0), count: m + 1)
        for j in 0...m { prev[j] = (j, 0, 0, j) }
        for i in 1...n {
            var cur = [(Int, Int, Int, Int)](repeating: (0, 0, 0, 0), count: m + 1)
            cur[0] = (i, 0, i, 0)
            for j in 1...m {
                if ref[i - 1] == hyp[j - 1] {
                    cur[j] = prev[j - 1]
                } else {
                    let sub = prev[j - 1], del = prev[j], ins = cur[j - 1]
                    if sub.0 <= del.0 && sub.0 <= ins.0 {
                        cur[j] = (sub.0 + 1, sub.1 + 1, sub.2, sub.3)
                    } else if del.0 <= ins.0 {
                        cur[j] = (del.0 + 1, del.1, del.2 + 1, del.3)
                    } else {
                        cur[j] = (ins.0 + 1, ins.1, ins.2, ins.3 + 1)
                    }
                }
            }
            prev = cur
        }
        let r = prev[m]
        return WERResult(substitutions: r.1, deletions: r.2, insertions: r.3, referenceWords: n)
    }
}

/// Converts runs of English number words into digits: "twenty five" -> "25",
/// "three thousand two hundred" -> "3200", "third" -> "3". Years read as pairs
/// ("twenty twenty six") become "2026".
public enum NumberWords {
    static let units: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "twentieth": 20, "thirtieth": 30,
    ]
    static let scales: [String: Int] = ["hundred": 100, "thousand": 1_000, "million": 1_000_000]

    public static func isNumberWord(_ w: String) -> Bool {
        units[w] != nil || tens[w] != nil || scales[w] != nil || ordinals[w] != nil
    }

    public static func collapse(_ words: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            // "oh" alone is a word, not zero; "second" alone is usually time.
            guard isNumberWord(w), !(w == "oh" && !(i + 1 < words.count && units[words[i + 1]] != nil)),
                  !(w == "second" && (i == 0 || !isNumberWord(words[i - 1]))) else {
                out.append(w)
                i += 1
                continue
            }
            var run: [String] = []
            var j = i
            while j < words.count, isNumberWord(words[j]) || (words[j] == "and" && !run.isEmpty && j + 1 < words.count && isNumberWord(words[j + 1])) {
                if words[j] != "and" { run.append(words[j]) }
                j += 1
                if ordinals[run.last ?? ""] != nil { break }
            }
            out.append(contentsOf: value(of: run).map { $0.map(String.init) } ?? run)
            i = j
        }
        return out
    }

    /// Value of a run of number words, or groups for runs like years ("twenty twenty six" -> 2026).
    static func value(of run: [String]) -> [Int]? {
        // Split into groups where two "small" numbers sit next to each other without a scale word,
        // which is how years and phone-style digits are read.
        var groups: [Int] = []
        var total = 0, current = 0
        var lastWasUnitOrTen = false
        var lastWasTen = false
        var hasValue = false
        func flush() {
            if hasValue { groups.append(total + current) }
            total = 0; current = 0; hasValue = false; lastWasUnitOrTen = false; lastWasTen = false
        }
        for w in run {
            if let u = units[w] ?? ordinals[w].flatMap({ $0 < 20 ? $0 : nil }) {
                if lastWasUnitOrTen && !(lastWasTen && u < 10) { flush() }
                current += u
                hasValue = true
                lastWasUnitOrTen = true
                lastWasTen = false
            } else if let t = tens[w] ?? ordinals[w].flatMap({ $0 >= 20 ? $0 : nil }) {
                if lastWasUnitOrTen { flush() }
                current += t
                hasValue = true
                lastWasUnitOrTen = true
                lastWasTen = true
            } else if let s = scales[w] {
                if !hasValue { current = 1 }
                if s == 100 {
                    current *= 100
                } else {
                    total += current * s
                    current = 0
                }
                hasValue = true
                lastWasUnitOrTen = false
                lastWasTen = false
            } else {
                return nil
            }
        }
        flush()
        guard !groups.isEmpty else { return nil }
        // Two two-digit groups read as a year: twenty twenty six -> 2026, nineteen ninety -> 1990.
        if groups.count == 2, (10...99).contains(groups[0]), (0...99).contains(groups[1]) {
            return [groups[0] * 100 + groups[1]]
        }
        return groups
    }
}
