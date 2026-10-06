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
