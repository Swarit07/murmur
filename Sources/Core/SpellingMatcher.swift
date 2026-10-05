import Foundation

/// Dictionary spellings matched against what the engine wrote (S1): "use effect" becomes useEffect,
/// "Okonko" becomes Okonkwo, "Chivon" (heard as "Chivan") becomes Siobhan. Deliberately conservative,
/// because a dictionary word appearing where nobody said it is worse than a missed fix: a near miss
/// must share the first letter, be at least six letters long and differ by at most one edit in five.
public struct SpellingMatcher: Sendable {
    struct Target: Sendable {
        let spelling: String
        let key: String
    }

    let targets: [Target]

    /// `spellings` maps each dictionary spelling to what the engine tends to hear instead.
    public init(spellings: [String: [String]]) {
        var targets: [Target] = []
        for (spelling, heard) in spellings where !Self.key(spelling).isEmpty {
            for form in [spelling] + heard {
                let key = Self.key(form)
                if !key.isEmpty { targets.append(Target(spelling: spelling, key: key)) }
            }
        }
        self.targets = targets
    }

    public var isEmpty: Bool { targets.isEmpty }

    /// Lowercase letters and digits only, accents folded: "Mei-Ling" and "mei ling" both give "meiling".
    public static func key(_ s: String) -> String {
        String(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// 1 − edit distance / longer length.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + [Int](repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        let distance = a.isEmpty ? b.count : previous[b.count]
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }

    /// How well `heard` (one to three words) matches a target key; nil when it must not be replaced.
    static func score(heard: String, words: Int, key: String) -> Double? {
        let h = Self.key(heard)
        guard !h.isEmpty else { return nil }
        if h == key {
            // Exact apart from case, spacing and punctuation. Joining words needs a longer key so
            // "a i" never becomes "AI" by accident.
            return key.count >= (words == 1 ? 2 : 4) ? 2 : nil
        }
        // A near miss never overwrites real words: "mailing" stays "mailing" even with Mei-Ling in the
        // dictionary, and "bell view" stays two words.
        guard key.count >= 5, h.first == key.first, abs(h.count - key.count) <= 2,
              !heard.split(whereSeparator: { $0.isWhitespace }).allSatisfy({ EnglishWords.contains(String($0)) }) else { return nil }
        let s = similarity(h, key)
        if key.count >= 6, s >= 0.8 { return s }
        // Same sound ("Belouve" for Bellevue): a little below a close spelling match.
        let code = phonetic(h)
        return code.count >= 3 && code == phonetic(key) ? 0.79 : nil
    }

    /// A rough sound key: the first letter, then consonants with similar sounds merged and vowels dropped.
    /// "Belouve" and "Bellevue" both give "blf".
    public static func phonetic(_ key: String) -> String {
        var s = key
        for (from, to) in [("ph", "f"), ("ck", "k"), ("sch", "sk"), ("sh", "x"), ("ch", "x"), ("th", "0"), ("qu", "kw"), ("dg", "j"),
                           ("x", "ks"), ("q", "k"), ("z", "s"), ("v", "f"), ("w", "")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        var chars = Array(s)
        for i in chars.indices where chars[i] == "c" {
            chars[i] = i + 1 < chars.count && "eiy".contains(chars[i + 1]) ? "s" : "k"
        }
        guard let first = chars.first else { return "" }
        var out = [first]
        for c in chars.dropFirst() where !"aeiouy".contains(c) && out.last != c {
            out.append(c)
        }
        return String(out)
    }

    /// True if `heard` may be written as `spelling`.
    public func accepts(heard: String, as spelling: String) -> Bool {
        let words = heard.split(whereSeparator: \.isWhitespace).count
        return targets.contains { $0.spelling == spelling && Self.score(heard: heard, words: max(words, 1), key: $0.key) != nil }
    }

    static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#)

    /// Replaces near misses with their dictionary spelling, longest and closest match first. Words
    /// inside addresses (next to "." "/" "@") are left alone.
    public func apply(_ text: String) -> String {
        guard !targets.isEmpty else { return text }
        let ns = text as NSString
        let tokens = Self.wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        var replacements: [(NSRange, String)] = []
        var i = 0
        while i < tokens.count {
            var best: (score: Double, words: Int, spelling: String, suffix: String)?
            for n in stride(from: min(3, tokens.count - i), through: 1, by: -1) {
                let span = tokens[i..<(i + n)]
                // Only plain spaces between the words of a span.
                let gapsOK = zip(span, span.dropFirst()).allSatisfy { a, b in
                    ns.substring(with: NSRange(location: a.upperBound, length: b.location - a.upperBound)).allSatisfy { $0 == " " }
                }
                guard gapsOK, !Self.insideAddress(ns, NSRange(location: span.first!.location, length: span.last!.upperBound - span.first!.location)) else { continue }
                var heard = span.map { ns.substring(with: $0) }.joined(separator: " ")
                var suffix = ""
                for s in ["'s", "’s"] where heard.hasSuffix(s) {
                    heard.removeLast(2)
                    suffix = s
                }
                for target in targets {
                    guard let score = Self.score(heard: heard, words: n, key: target.key) else { continue }
                    if best == nil || score > best!.score || (score == best!.score && n > best!.words) {
                        best = (score, n, target.spelling, suffix)
                    }
                }
            }
            if let best {
                let range = NSRange(location: tokens[i].location, length: tokens[i + best.words - 1].upperBound - tokens[i].location)
                let replacement = best.spelling + best.suffix
                if ns.substring(with: range) != replacement { replacements.append((range, replacement)) }
                i += best.words
            } else {
                i += 1
            }
        }
        var out = text
        for (range, replacement) in replacements.reversed() {
            out = (out as NSString).replacingCharacters(in: range, with: replacement)
        }
        return out
    }

    static func insideAddress(_ ns: NSString, _ range: NSRange) -> Bool {
        let before = range.location > 0 ? ns.substring(with: NSRange(location: range.location - 1, length: 1)) : ""
        let after = range.upperBound < ns.length ? ns.substring(with: NSRange(location: range.upperBound, length: 1)) : ""
        let afterNext = range.upperBound + 1 < ns.length ? ns.substring(with: NSRange(location: range.upperBound + 1, length: 1)) : ""
        // A sentence-ending period is fine; a dot followed by a letter is part of an address.
        let dotted = after == "." && afterNext.rangeOfCharacter(from: .letters) != nil
        return ["/", "@", "."].contains(before) || ["/", "@"].contains(after) || dotted
    }

    /// Word-level changes from `a` to `b`: each run of removed words with the words that replaced it.
    public static func changes(from a: [String], to b: [String]) -> [(removed: [String], inserted: [String])] {
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [(removed: [String], inserted: [String])] = []
        var removed: [String] = [], inserted: [String] = []
        var i = 0, j = 0
        func flush() {
            if !removed.isEmpty || !inserted.isEmpty { out.append((removed, inserted)) }
            removed = []
            inserted = []
        }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush()
                i += 1
                j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                inserted.append(b[j])
                j += 1
            } else {
                removed.append(a[i])
                i += 1
            }
        }
        flush()
        return out
    }
}

/// The system word list (`/usr/share/dict/words`, lowercase entries), with simple suffix stripping so
/// "mailing" counts through "mail". Loaded on first use.
public enum EnglishWords {
    static let words: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").filter { $0.first?.isLowercase == true }.map(String.init))
    }()

    public static func contains(_ word: String) -> Bool {
        let w = word.lowercased().replacingOccurrences(of: "’", with: "'")
        guard w.count >= 2, w.allSatisfy({ $0.isLetter || $0 == "'" }) else { return false }
        var forms = [w]
        func strip(_ suffix: String, add: [String] = [""]) {
            guard w.hasSuffix(suffix), w.count > suffix.count + 1 else { return }
            let stem = String(w.dropLast(suffix.count))
            forms += add.map { stem + $0 }
            if let last = stem.last, stem.count > 2, stem.dropLast().last == last { forms.append(String(stem.dropLast())) }
        }
        strip("'s")
        strip("ing", add: ["", "e"])
        strip("ed", add: ["", "e"])
        strip("es")
        strip("s")
        strip("ies", add: ["y"])
        strip("er", add: ["", "e"])
        strip("est", add: ["", "e"])
        strip("ly")
        return forms.contains { words.contains($0) }
    }
}
