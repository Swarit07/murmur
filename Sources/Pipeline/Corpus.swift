import Core
import Foundation

public struct CorpusClip: Codable, Sendable, Identifiable {
    public var id: String
    public var set: String
    /// What the speaker reads. Empty for the silence set.
    public var read: String
    /// Optional pronunciation hint shown under the sentence.
    public var say: String?
    /// What to do for clips with no words.
    public var instruction: String?
    /// Strings that must survive transcription and cleanup.
    public var entities: [String]?
    /// Correction set: the cleaned result.
    public var expected: String?
    public var mustInclude: [String]?
    public var mustExclude: [String]?
    public var note: String?

    /// The written reference transcript (what was read).
    public var reference: String { read }
    public var isSilence: Bool { self.set == "silence" }
}

public struct Corpus: Codable, Sendable {
    public var version: Int
    public var notes: String?
    public var sets: [String: String]
    public var clips: [CorpusClip]

    public static let setOrder = ["plain", "numbers", "names", "quiet", "silence", "correction", "levels"]

    public static func load(from directory: URL) throws -> Corpus {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(Corpus.self, from: data)
    }

    public static func audioURL(_ clip: CorpusClip, in directory: URL) -> URL {
        directory.appendingPathComponent("audio").appendingPathComponent("\(clip.id).wav")
    }

    public static func referenceURL(_ clip: CorpusClip, in directory: URL) -> URL {
        directory.appendingPathComponent("audio").appendingPathComponent("\(clip.id).txt")
    }

    public func clips(in name: String) -> [CorpusClip] { clips.filter { $0.set == name } }
}

/// Checks on cleaned or transcribed text against the corpus expectations.
public enum CorpusChecks {
    /// True if `needle`'s normalized words appear as a contiguous run in `haystack`'s.
    public static func contains(_ haystack: String, _ needle: String) -> Bool {
        let h = TextMetrics.normalizedWords(haystack), n = TextMetrics.normalizedWords(needle)
        guard !n.isEmpty, n.count <= h.count else { return n.isEmpty }
        for i in 0...(h.count - n.count) where Array(h[i..<(i + n.count)]) == n { return true }
        return false
    }

    /// URLs and emails must match exactly (case-insensitive), not just as words.
    public static func entityPresent(_ text: String, _ entity: String) -> Bool {
        if entity.contains("@") || entity.contains("/") {
            return text.lowercased().contains(entity.lowercased())
        }
        return contains(text, entity)
    }

    public static func missingEntities(_ text: String, _ clip: CorpusClip) -> [String] {
        (clip.entities ?? []).filter { !entityPresent(text, $0) }
    }

    /// Correction set: the correction resolved and nothing else changed meaning.
    public static func correctionResolved(_ output: String, _ clip: CorpusClip) -> (ok: Bool, why: String?) {
        for word in clip.mustInclude ?? [] where !contains(output, word) { return (false, "missing \"\(word)\"") }
        for word in clip.mustExclude ?? [] where contains(output, word) { return (false, "still has \"\(word)\"") }
        if let expected = clip.expected {
            let wer = TextMetrics.wer(reference: expected, hypothesis: output)
            if wer.rate > 0.25 { return (false, String(format: "differs from expected (WER %.2f)", wer.rate)) }
        }
        return (true, nil)
    }
}
