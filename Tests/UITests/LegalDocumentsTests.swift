import Foundation
import Testing
@testable import UI

/// LEGAL_DOCS.md L1: the MIT License ships inside the app, and the bundled copy matches the repo's.
@Suite("Legal documents")
struct LegalDocumentsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func licenseIsBundled() throws {
        let bundled = try #require(LegalDocuments.license)
        #expect(bundled.hasPrefix("MIT License"))
        #expect(bundled.contains("Copyright (c) 2026 Swarit Sheel"))
    }

    @Test func bundledLicenseMatchesTheRepo() throws {
        let repo = try String(contentsOf: Self.root.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(LegalDocuments.license == repo)
    }

    @Test func missingFileIsNil() {
        #expect(LegalDocuments.text("NO-SUCH-FILE") == nil)
    }
}
