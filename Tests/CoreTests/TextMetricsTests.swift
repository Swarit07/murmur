@testable import Core
import Testing

@Suite("Text metrics")
struct TextMetricsTests {
    @Test func identicalIsZero() {
        #expect(TextMetrics.wer(reference: "Hello, world.", hypothesis: "hello world").rate == 0)
    }

    @Test func countsEditOperations() {
        let r = TextMetrics.wer(reference: "the quick brown fox", hypothesis: "the quick red fox jumps")
        #expect(r.substitutions == 1)
        #expect(r.insertions == 1)
        #expect(r.deletions == 0)
        #expect(r.referenceWords == 4)
        #expect(abs(r.rate - 0.5) < 1e-9)
    }

    @Test func deletions() {
        let r = TextMetrics.wer(reference: "one small step", hypothesis: "small")
        #expect(r.deletions == 2)
    }

    @Test func numberWordsMatchDigits() {
        #expect(TextMetrics.wer(reference: "It costs 25 dollars", hypothesis: "It costs twenty five dollars").rate == 0)
        #expect(TextMetrics.wer(reference: "March 3rd", hypothesis: "March third").rate == 0)
        #expect(TextMetrics.wer(reference: "in 2026", hypothesis: "in twenty twenty six").rate == 0)
        #expect(TextMetrics.wer(reference: "1,500 people", hypothesis: "fifteen hundred people").rate == 0)
        #expect(TextMetrics.wer(reference: "40%", hypothesis: "forty percent").rate == 0)
    }

    @Test func numberWordCollapse() {
        #expect(NumberWords.collapse(["three", "hundred", "and", "twelve"]) == ["312"])
        #expect(NumberWords.collapse(["two", "thousand", "twenty", "six"]) == ["2026"])
        #expect(NumberWords.collapse(["one", "two", "three"]) == ["1", "2", "3"])
        #expect(NumberWords.collapse(["oh", "well"]) == ["oh", "well"])
        #expect(NumberWords.collapse(["wait", "a", "second"]) == ["wait", "a", "second"])
    }

    @Test func emptyReference() {
        #expect(TextMetrics.wer(reference: "", hypothesis: "").rate == 0)
        #expect(TextMetrics.wer(reference: "", hypothesis: "noise").rate == 1)
    }

    @Test func percentiles() {
        let v = (1...100).map(Double.init)
        #expect(Stats.percentile(v, 50) == 50)
        #expect(Stats.percentile(v, 95) == 95)
        #expect(Stats.percentile([7], 95) == 7)
        #expect(Stats.percentile([], 50) == nil)
    }
}
