import Foundation

/// The license, privacy notes and third-party notices bundled in `Resources/Legal`, so the app shows them
/// without a network fetch. `Scripts/gen-notices.py` copies them there from the repo root and `Licenses/`;
/// its `--check` mode fails when a copy is stale.
public enum LegalDocuments {
    /// Murmur's MIT License, as in the repo's `LICENSE`.
    public static var license: String? { text("LICENSE") }

    /// The bundled file's text, or nil if it is missing from the bundle.
    static func text(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Legal") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
