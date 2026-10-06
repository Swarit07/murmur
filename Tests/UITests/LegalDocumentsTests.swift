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

    @Test func reflowJoinsWrappedLinesAndKeepsParagraphs() {
        let text = """
        MIT License

        Copyright (c) 2026 Someone

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files.
        """
        #expect(LegalDocuments.reflow(text) == """
        MIT License

        Copyright (c) 2026 Someone

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files.
        """)
    }

    @Test func reflowKeepsListItemsCopyrightsAndRules() {
        let text = """
           1. Definitions.
           (a) You must give any other recipients of the Work or
               Derivative Works a copy of this License; and
           b) a second item
           - a bullet
             that wraps
        Copyright 2009 One
        Copyright 2011 Two
        All rights reserved.
        =====
        swift-transformers
        =====
        """
        #expect(LegalDocuments.reflow(text) == """
        1. Definitions.
        (a) You must give any other recipients of the Work or Derivative Works a copy of this License; and
        b) a second item
        - a bullet that wraps
        Copyright 2009 One
        Copyright 2011 Two All rights reserved.
        =====
        swift-transformers
        =====
        """)
    }

    @Test func reflowLeavesOrdinaryWordsAlone() {
        #expect(!LegalDocuments.startsOwnLine("a copy of the Software"))
        #expect(!LegalDocuments.startsOwnLine("e.g. this"))
        #expect(!LegalDocuments.startsOwnLine("Apache."))
        #expect(LegalDocuments.startsOwnLine("(iv) item"))
        #expect(LegalDocuments.startsOwnLine("12) item"))
    }

    /// L2/L5: the app's privacy notes are the repo's PRIVACY.md, so in-app and repo can't disagree.
    @Test func bundledPrivacyMatchesTheRepo() throws {
        let repo = try String(contentsOf: Self.root.appendingPathComponent("PRIVACY.md"), encoding: .utf8)
        #expect(LegalDocuments.privacy == repo)
    }

    /// L3: the Acknowledgements start with Murmur's license and credit the CC BY models (L3.5).
    @Test func noticesDecodeWithMurmurFirst() throws {
        let notices = try #require(LegalDocuments.notices)
        #expect(notices.copyright == "Copyright (c) 2026 Swarit Sheel")
        let first = try #require(notices.sections.first?.entries.first)
        #expect(first.name == "Murmur" && first.license == "MIT")
        let models = try #require(notices.sections.first { $0.title == "Models Murmur downloads" })
        #expect(models.entries.contains { $0.license == "CC-BY-4.0" && $0.text.contains("NVIDIA") })
        let packages = try #require(notices.sections.first { $0.title == "Swift packages" })
        #expect(packages.entries.contains { $0.name == "FluidAudio" && $0.text.contains("Apache License") })
        #expect(notices.sections.allSatisfy { $0.entries.allSatisfy { !$0.text.isEmpty } })
    }
}
