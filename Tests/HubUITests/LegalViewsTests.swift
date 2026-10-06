import Foundation
import MurmurKit
import Testing
import UI
@testable import HubUI

/// LEGAL_DOCS.md L5: the in-app privacy notes and Acknowledgements, and the "on-device" labels.
@Suite("Legal views")
@MainActor
struct LegalViewsTests {
    // MARK: Where the models run (audit M1)

    @Test func onDeviceWhenBothRunLocally() {
        let place = AppInfo.cloud(engine: "parakeet-ultra", cleanup: "mlx:qwen3.5-4b")
        #expect(!place.speech && !place.cleanup)
    }

    @Test func groqWhisperIsCloudSpeech() {
        #expect(AppInfo.cloud(engine: "groq-whisper", cleanup: "rules only").speech)
    }

    /// The bug: the provider id carries the model, so an exact match never saw cloud cleanup.
    @Test func cloudCleanupIdsWithAModelAreCloud() {
        #expect(AppInfo.cloud(engine: "parakeet-ultra", cleanup: "groq:openai/gpt-oss-20b").cleanup)
        #expect(AppInfo.cloud(engine: "parakeet-ultra", cleanup: "openrouter:meta-llama/llama-3.1-8b-instruct").cleanup)
        #expect(AppInfo.cloud(engine: "parakeet-ultra", cleanup: "groq").cleanup)
    }

    @Test func localAndUnloadedCleanupIsNotCloud() {
        for id in ["rules only", "loading…", "apple-foundation", "mlx:qwen3.5-4b", "groqish"] {
            #expect(!AppInfo.cloud(engine: "parakeet-ultra", cleanup: id).cleanup, "\(id)")
        }
    }

    // MARK: Markdown subset

    @Test func parsesHeadingsParagraphsAndSkipsCommentsAndTitle() {
        let blocks = DocumentParser.blocks("""
        # Privacy

        *Not a lawyer.* First line
        continues here.

        ## Summary

        <!-- audit: §1 -->
        ### Small
        """)
        #expect(blocks == [
            .paragraph("*Not a lawyer.* First line continues here."),
            .heading("Summary"),
            .heading("Small"),
        ])
    }

    @Test func parsesBulletsNumbersAndNesting() {
        let blocks = DocumentParser.blocks("""
        - one
        1. first
           - nested
        12. twelfth
        3.5 is not a list
        """)
        #expect(blocks == [
            .bullet("one", nested: false),
            .numbered("1", "first"),
            .bullet("nested", nested: true),
            .numbered("12", "twelfth"),
            .paragraph("3.5 is not a list"),
        ])
    }

    @Test func parsesTablesWithoutTheSeparatorRow() {
        let blocks = DocumentParser.blocks("""
        | What | Where |
        |---|---|
        | History | `~/Library` |
        | Audio | `Audio/` |
        After.
        """)
        #expect(blocks == [
            .table(header: ["What", "Where"], rows: [["History", "`~/Library`"], ["Audio", "`Audio/`"]]),
            .paragraph("After."),
        ])
    }

    @Test func keepsWebLinksAndDropsFileLinks() {
        let web = DocumentParser.inline("See [issues](https://github.com/Swarit07/murmur/issues).")
        #expect(web.runs.contains { $0.link?.absoluteString == "https://github.com/Swarit07/murmur/issues" })
        let mail = DocumentParser.inline("Or [me](mailto:someone@example.com).")
        #expect(mail.runs.contains { $0.link?.scheme == "mailto" })
        let file = DocumentParser.inline("Follow [SECURITY.md](SECURITY.md).")
        #expect(!file.runs.contains { $0.link != nil })
        #expect(String(file.characters) == "Follow SECURITY.md.")
    }

    /// The bundled PRIVACY.md renders as sections, with no comment or raw table syntax in the text.
    @Test func bundledPrivacyParses() throws {
        let blocks = DocumentParser.blocks(try #require(LegalDocuments.privacy))
        let headings = blocks.compactMap { if case .heading(let h) = $0 { h } else { nil } }
        #expect(headings.first == "Summary")
        #expect(headings.contains("Network") && headings.contains("Deleting everything"))
        #expect(blocks.contains { if case .table = $0 { true } else { false } })
        for block in blocks {
            if case .paragraph(let text) = block { #expect(!text.contains("<!--") && !text.hasPrefix("|")) }
        }
    }

    // MARK: Opening the dialogs

    func hub() throws -> HubModel {
        let store = try HistoryStore(url: nil)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "murmur.tests.legal") ?? .standard)
        return HubModel(controller: DictationController(settings: settings, store: store, sounds: nil), store: store)
    }

    @Test func openingFromHelpClosesHelpAndRemembersIt() throws {
        let model = try hub()
        model.helpOpen = true
        model.open(.acknowledgements, fromHelp: true)
        #expect(model.document == .acknowledgements && !model.helpOpen && model.documentFromHelp)
    }

    @Test func openingFromSettingsHasNoWayBackToHelp() throws {
        let model = try hub()
        model.open(.privacy)
        #expect(model.document == .privacy && !model.documentFromHelp)
    }
}
