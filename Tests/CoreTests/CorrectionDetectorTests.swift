@testable import Core
import Testing

@Suite("Dictionary suggestions (S2)")
struct CorrectionDetectorTests {
    @Test func aCorrectedNameBecomesASuggestion() {
        let inserted = "Ask Chivan about the venue."
        let found = CorrectionDetector.suggestions(before: "Notes: Ask Chivan about the venue.", after: "Notes: Ask Siobhan about the venue.", inserted: inserted)
        #expect(found == [CorrectionDetector.Suggestion(heard: "Chivan", spelling: "Siobhan")])
    }

    @Test func spellingAndCaseFixesOfTheSameLettersCount() {
        let found = CorrectionDetector.suggestions(before: "fix the swift ui view", after: "fix the SwiftUI view", inserted: "fix the swift ui view")
        #expect(found == [CorrectionDetector.Suggestion(heard: "swift ui", spelling: "SwiftUI")])
    }

    @Test func ordinaryEditsAreNotVocabulary() {
        #expect(CorrectionDetector.suggestions(before: "Let's meet at noon.", after: "Let's talk at noon.", inserted: "Let's meet at noon.").isEmpty)
        #expect(CorrectionDetector.suggestions(before: "Let's meet at noon.", after: "Let's meet at noon. See you there!", inserted: "Let's meet at noon.").isEmpty)
    }

    @Test func onlyWordsMurmurWroteCount() {
        // The user fixed text that was there before the dictation.
        let found = CorrectionDetector.suggestions(before: "Dear Jhon, see you soon.", after: "Dear Jöhn, see you soon.", inserted: "see you soon.")
        #expect(found.isEmpty)
    }

    @Test func bigRewritesAreIgnored() {
        let found = CorrectionDetector.suggestions(before: "Ask Chivan about the venue.", after: "Ask Siobhan Murphy O'Neill and Kubernetes about it.", inserted: "Ask Chivan about the venue.")
        #expect(found.allSatisfy { $0.spelling.split(separator: " ").count <= 3 })
    }
}
