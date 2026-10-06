import Foundation

/// The license, privacy notes and third-party notices bundled in `Resources/Legal`, so the app shows them
/// without a network fetch. `Scripts/gen-notices.py` copies them there from the repo root and `Licenses/`;
/// its `--check` mode fails when a copy is stale.
public enum LegalDocuments {
    /// Murmur's MIT License, as in the repo's `LICENSE`.
    public static var license: String? { text("LICENSE") }

    /// `PRIVACY.md`, as in the repo.
    public static var privacy: String? { text("PRIVACY.md") }

    /// The Acknowledgements: Murmur's own license first, then fonts, packages, models and license texts.
    public static var notices: Notices? {
        guard let data = text("notices.json")?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Notices.self, from: data)
    }

    /// License files wrap at about 80 columns for a terminal; in a proportional font those breaks land
    /// mid-line. This joins each paragraph's wrapped lines and keeps paragraph breaks, list items
    /// ("1.", "(a)", "-"), copyright lines and separator rules on lines of their own.
    public static func reflow(_ text: String) -> String {
        var paragraphs: [[String]] = [[]]
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !(paragraphs.last ?? []).isEmpty { paragraphs.append([]) }
            } else {
                paragraphs[paragraphs.count - 1].append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return paragraphs.filter { !$0.isEmpty }.map { lines in
            var out: [String] = []
            for line in lines {
                if let last = out.last, !startsOwnLine(line), !isRule(last) {
                    out[out.count - 1] = last + " " + line
                } else {
                    out.append(line)
                }
            }
            return out.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// A list item, a copyright line, a Markdown heading or a rule.
    static func startsOwnLine(_ line: String) -> Bool {
        if isRule(line) || line.hasPrefix("#") || line.hasPrefix("Copyright") || line.hasPrefix("©") { return true }
        if ["- ", "* ", "• "].contains(where: line.hasPrefix) { return true }
        // "1. ", "12) ", "(a) ", "(iv) ", "a) "
        let marker = line.prefix { $0 != " " }
        guard marker.count < line.count, let close = marker.last, close == "." || close == ")" else { return false }
        let body = marker.dropLast().drop { $0 == "(" }
        if body.isEmpty || body.count > 4 { return false }
        if body.allSatisfy(\.isNumber) { return true }
        return body.allSatisfy { $0.isLetter && $0.isLowercase } && (marker.hasPrefix("(") || close == ")" || body.count == 1)
    }

    static func isRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { "=-_*~".contains($0) }
    }

    /// The bundled file's text, or nil if it is missing from the bundle.
    static func text(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Legal") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// `notices.json`, written by `Scripts/gen-notices.py`.
    public struct Notices: Decodable, Sendable, Equatable {
        /// "Copyright (c) 2026 Swarit Sheel", from `LICENSE`.
        public let copyright: String
        public let sections: [Section]
    }

    public struct Section: Decodable, Sendable, Equatable, Identifiable {
        public let title: String
        public let entries: [Entry]
        public var id: String { title }
    }

    public struct Entry: Decodable, Sendable, Equatable, Identifiable {
        public let name: String
        /// SPDX id, such as "MIT" or "CC-BY-4.0".
        public let license: String
        /// Version and use, a copyright line, or a model's address. May be empty.
        public let detail: String
        /// The full license text, or a model's attribution.
        public let text: String
        public var id: String { name }
    }
}
