import Foundation

/// S2: after a dictation is pasted, Murmur compares the field with what it was right after the paste.
/// A word Murmur wrote that the user replaced with a name or a term (not an everyday English word)
/// becomes a dictionary suggestion: "Chivan" corrected to "Siobhan" suggests Siobhan, heard as Chivan.
public enum CorrectionDetector {
    public struct Suggestion: Sendable, Equatable {
        /// What Murmur wrote (the dictionary's "Heard as").
        public var heard: String
        /// What the user wrote instead (the dictionary's spelling).
        public var spelling: String

        public var key: String { heard.lowercased() + "→" + spelling }
    }

    /// Fields this long are not compared (the diff would be slow and the change hard to place).
    static let maxWords = 3000

    public static func suggestions(before: String, after: String, inserted: String) -> [Suggestion] {
        let a = words(before), b = words(after)
        guard !a.isEmpty, a.count <= maxWords, b.count <= maxWords else { return [] }
        let ours = Set(words(inserted).map { $0.lowercased() })
        var out: [Suggestion] = []
        for change in SpellingMatcher.changes(from: a, to: b) {
            guard (1...2).contains(change.removed.count), (1...3).contains(change.inserted.count),
                  change.removed.allSatisfy({ ours.contains($0.lowercased()) }) else { continue }
            let heard = change.removed.joined(separator: " "), spelling = change.inserted.joined(separator: " ")
            let sameKey = SpellingMatcher.key(heard) == SpellingMatcher.key(spelling)
            // A spelling or capitalization fix of the same letters ("swift ui" → "SwiftUI"), or a word that
            // is not everyday English (a name, a product, jargon). Ordinary edits are not vocabulary.
            let unusual = change.inserted.contains { !EnglishWords.contains($0) }
            guard (sameKey && heard != spelling) || (!sameKey && unusual) else { continue }
            let suggestion = Suggestion(heard: heard, spelling: spelling)
            if !out.contains(suggestion) { out.append(suggestion) }
        }
        return out
    }

    /// Words with surrounding punctuation removed ("Siobhan," → "Siobhan"); inner apostrophes and
    /// hyphens stay.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }
}
