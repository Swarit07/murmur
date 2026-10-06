import Foundation

/// Dictionary spellings matched against what the engine wrote (S1): "use effect" becomes useEffect,
/// "Okonko" becomes Okonkwo, "Chivon" (heard as "Chivan") becomes Siobhan. Deliberately conservative,
/// because a dictionary word appearing where nobody said it is worse than a missed fix: a near miss
/// must share the first letter, be at least six letters long and differ by at most one edit in five.
/// Three narrow additions: a capitalized fragment of a name the engine cut short ("Pri" for Priya), how a
/// hard-to-spell name in the dictionary is said ("shiv-awn" for Siobhan, `SpokenNames`), and a real word that
/// sounds exactly like a dictionary name when it sits in a list of names ("to Joaquín and mailing").
public struct SpellingMatcher: Sendable {
    struct Target: Sendable {
        let spelling: String
        let key: String
        /// How the name is said (from `SpokenNames`), matched by sound only.
        var spoken = false
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
            for spoken in SpokenNames.forms[Self.key(spelling)] ?? [] {
                targets.append(Target(spelling: spelling, key: spoken, spoken: true))
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

    /// How well `heard` (one to three words) matches a target; nil when it must not be replaced.
    static func score(heard: String, words: Int, target: Target) -> Double? {
        let key = target.key
        let h = Self.key(heard)
        guard !h.isEmpty else { return nil }
        if h == key {
            // Exact apart from case, spacing and punctuation. Joining words needs a longer key so
            // "a i" never becomes "AI" by accident.
            return key.count >= (words == 1 ? 2 : 4) ? 2 : nil
        }
        let english = heard.split(whereSeparator: { $0.isWhitespace }).allSatisfy({ EnglishWords.contains(String($0)) })
        if target.spoken {
            // How the name is said ("Chivan" sounds like "shivawn" for Siobhan): sound only, one word, never a real word.
            guard words == 1, !english, !ProperNames.contains(heard), h.count >= 3, similarity(h, key) >= 0.65 else { return nil }
            let code = phonetic(h)
            return code.count >= 3 && code == phonetic(key) ? 0.78 : nil
        }
        // A near miss never overwrites real words: "mailing" stays "mailing" even with Mei-Ling in the
        // dictionary, and "bell view" stays two words.
        // Nor a name of its own: "Alex" sounds like Alexa and "Josh" like Joshua, but they are other people.
        guard key.count >= 5, h.first == key.first, abs(h.count - key.count) <= 2, !english,
              !(words == 1 && ProperNames.contains(heard)) else { return nil }
        let s = similarity(h, key)
        if key.count >= 6, s >= 0.8 { return s }
        // A name the engine cut short ("Pri" for Priya): capitalized, at least three letters and 60% of the name.
        // Never when the fragment is a name of its own ("Alex" stays Alex with Alexa in the dictionary).
        if words == 1, h.count >= 3, key.hasPrefix(h), Double(h.count) / Double(key.count) >= 0.6, heard.first?.isUppercase == true,
           !ProperNames.contains(heard) {
            return 0.77
        }
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
        return targets.contains { $0.spelling == spelling && Self.score(heard: heard, words: max(words, 1), target: $0) != nil }
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
                    guard let score = Self.score(heard: heard, words: n, target: target) else { continue }
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
        replacements += namesInLists(ns, tokens: tokens, replaced: replacements)
        replacements.sort { $0.0.location < $1.0.location }
        var out = text
        for (range, replacement) in replacements.reversed() {
            out = (out as NSString).replacingCharacters(in: range, with: replacement)
        }
        return out
    }

    /// A real word that sounds exactly like a dictionary name, written as that name only when it sits in a list
    /// of names: right after "and"/"or" and another dictionary name, or right before them, and ending its phrase.
    /// "to Joaquín and mailing." becomes "to Joaquín and Mei-Ling."; "the mailing list" and "Joaquín and
    /// mailing lists" stay as they are.
    func namesInLists(_ ns: NSString, tokens: [NSRange], replaced: [(NSRange, String)]) -> [(NSRange, String)] {
        let spellingKeys = Set(targets.filter { !$0.spoken }.map { Self.key($0.spelling) })
        let taken = Set(replaced.map(\.0.location))
        func word(_ i: Int) -> String { i >= 0 && i < tokens.count ? ns.substring(with: tokens[i]) : "" }
        func isName(_ i: Int) -> Bool {
            guard i >= 0, i < tokens.count else { return false }
            if let r = replaced.first(where: { $0.0.location == tokens[i].location }) { return spellingKeys.contains(Self.key(r.1)) }
            return spellingKeys.contains(Self.key(word(i)))
        }
        func joins(_ i: Int) -> Bool { ["and", "or"].contains(word(i).lowercased()) }
        var out: [(NSRange, String)] = []
        for i in tokens.indices where !taken.contains(tokens[i].location) {
            let w = word(i)
            guard EnglishWords.contains(w), !Self.insideAddress(ns, tokens[i]) else { continue }
            let inList = (joins(i - 1) && isName(i - 2)) || (joins(i + 1) && isName(i + 2))
            // Ends its phrase: punctuation or the end follows, or the list goes on.
            let next = tokens[i].upperBound < ns.length ? ns.substring(with: NSRange(location: tokens[i].upperBound, length: 1)) : ""
            let endsPhrase = next.isEmpty || ".,;:!?".contains(next) || joins(i + 1)
            guard inList, endsPhrase else { continue }
            let h = Self.key(w), code = Self.phonetic(h)
            guard code.count >= 3, let target = targets.first(where: { t in
                !t.spoken && t.key.count >= 5 && abs(t.key.count - h.count) <= 2 && Self.phonetic(t.key) == code && Self.similarity(h, t.key) >= 0.6
            }) else { continue }
            out.append((tokens[i], target.spelling))
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

/// Common first names (`/usr/share/dict/propernames`, 1,308 of them). A heard word that is a name of its own is
/// never rewritten into a different dictionary name. Loaded on first use.
public enum ProperNames {
    static let names: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/propernames", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    public static func contains(_ word: String) -> Bool { names.contains(word.lowercased()) }
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
