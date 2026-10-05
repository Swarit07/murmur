@testable import Cleanup
import Testing

@Suite("Prompt-lookup drafter")
struct PromptLookupDrafterTests {
    // Token ids stand in for words: 1 "so" 2 "the" 3 "plan" 4 "is" 5 "to" 6 "ship" 7 "on" 8 "Friday" 9 "um"
    let source = [9, 1, 2, 3, 4, 5, 6, 2, 3, 7, 8]

    @Test func copiesWhatFollowedTheLastTokensInTheDictation() {
        var d = PromptLookupDrafter(source: source)
        #expect(d.draft(after: [1, 2, 3], count: 3) == [4, 5, 6])
    }

    @Test func stopsAtTheEndOfTheSource() {
        var d = PromptLookupDrafter(source: source)
        #expect(d.draft(after: [7], count: 5) == [8])
        // Nothing follows the last token, so there is nothing to guess.
        #expect(d.draft(after: [8], count: 5) == [])
    }

    @Test func fallsBackToShorterRuns() {
        var d = PromptLookupDrafter(source: source)
        // "So the plan" became "The plan": the 3- and 2-token runs are new, the last token is not.
        #expect(d.draft(after: [42, 43, 4], count: 2) == [5, 6])
    }

    @Test func nothingWhenTheOutputLeftTheDictation() {
        var d = PromptLookupDrafter(source: source)
        #expect(d.draft(after: [42], count: 4) == [])
        #expect(d.draft(after: [1], count: 0) == [])
        #expect(d.draft(after: [], count: 4) == [])
    }

    @Test func repeatedWordsFollowTheDictationInOrder() {
        var d = PromptLookupDrafter(source: source)
        // "the plan" appears twice. Early on, the first one is next.
        #expect(d.draft(after: [2, 3], count: 2) == [4, 5])
        // Once the output has moved past "ship", the second one is next.
        #expect(d.draft(after: [5, 6], count: 1) == [2])
        #expect(d.draft(after: [2, 3], count: 2) == [7, 8])
        // A longer run decides by itself which occurrence it is, wherever the cursor is.
        #expect(d.draft(after: [1, 2, 3], count: 1) == [4])
    }

    @Test func guessesGrowWhileTheyAreRight() {
        var sizer = GuessSizer(acceptance: 0.5)
        // A one-token guess costs almost nothing, so there is always one.
        #expect(sizer.length(available: 31, fixed: 1) == 1)
        #expect(sizer.length(available: 0, fixed: 1) == 0)
        for _ in 0..<10 { sizer.record(kept: 8, checked: 8) }
        // Copying the dictation: one long pass, which costs about four short ones, gives 32 tokens.
        #expect(sizer.length(available: 31, fixed: 1) == 31)
        sizer.record(kept: 0, checked: 31)
        #expect(sizer.acceptance < 0.86)
    }

    @Test func replayedTokensFillTheirPass() {
        let sizer = GuessSizer(acceptance: 0.85)
        let alone = sizer.length(available: 31, fixed: 1)
        #expect((2...4).contains(alone))
        // Eleven replayed tokens already put the pass where extra tokens cost nothing, so guess up to 32.
        #expect(sizer.length(available: 31, fixed: 12) == 20)
    }

    @Test func statsAddUp() {
        var a = PromptLookupStats()
        a.passes = 2; a.tokens = 9; a.drafted = 10; a.accepted = 7
        var b = PromptLookupStats()
        b.passes = 1; b.tokens = 3; b.drafted = 2; b.accepted = 1; b.replayed = 2; b.rollbacks = 1
        let sum = a + b
        #expect(sum.passes == 3 && sum.tokens == 12 && sum.drafted == 12 && sum.accepted == 8 && sum.replayed == 2 && sum.rollbacks == 1)
        #expect(abs(sum.acceptance - 8.0 / 12.0) < 1e-9)
        #expect(sum.tokensPerPass == 4)
        #expect(PromptLookupStats().acceptance == 0)
    }
}
