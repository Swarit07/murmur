@testable import Core
import Testing

@Suite("Spelling matcher")
struct SpellingMatcherTests {
    let matcher = SpellingMatcher(spellings: [
        "useEffect": [], "SwiftUI": [], "Okonkwo": [], "Bellevue": [], "Mei-Ling": [], "Siobhan": ["Chivan"], "Murmurly": ["marmalade"], "AI": [],
    ])

    @Test func joinsSplitWordsAndFixesCase() {
        #expect(matcher.apply("about the use effect hook") == "about the useEffect hook")
        #expect(matcher.apply("in the Swift Ui view model.") == "in the SwiftUI view model.")
        #expect(matcher.apply("Mei ling said hi") == "Mei-Ling said hi")
    }

    @Test func fixesCloseMissesAndSoundAlikes() {
        #expect(matcher.apply("Doctor Okonko recommended it.") == "Doctor Okonkwo recommended it.")
        #expect(matcher.apply("the appointment in Belouve.") == "the appointment in Bellevue.")
        #expect(matcher.apply("Ask Chivon whether") == "Ask Siobhan whether")
    }

    @Test func neverOverwritesRealWords() {
        #expect(matcher.apply("the mailing list") == "the mailing list")
        #expect(matcher.apply("the meeting moved") == "the meeting moved")
        #expect(matcher.apply("a bell view") == "a bell view")
        #expect(matcher.apply("the quick brown fox jumps over the lazy dog") == "the quick brown fox jumps over the lazy dog")
        #expect(matcher.apply("a i model") == "a i model")
    }

    @Test func keepsPossessivesAndAddresses() {
        #expect(matcher.apply("Okonko's notes") == "Okonkwo's notes")
        #expect(matcher.apply("see okonko.com/notes") == "see okonko.com/notes")
        #expect(matcher.apply("Use Effect.") == "useEffect.")
    }

    @Test func acceptsOnlyCloseRescoring() {
        #expect(matcher.accepts(heard: "Okonko", as: "Okonkwo"))
        #expect(matcher.accepts(heard: "use effect", as: "useEffect"))
        #expect(!matcher.accepts(heard: "lazy dog.", as: "Murmurly"))
        #expect(!matcher.accepts(heard: "meeting", as: "Mei-Ling"))
        #expect(!matcher.accepts(heard: "", as: "Murmurly"))
    }

    @Test func wordChanges() {
        let changes = SpellingMatcher.changes(from: ["over", "the", "lazy", "dog."], to: ["over", "the", "Murmurly."])
        #expect(changes.count == 1)
        #expect(changes[0].removed == ["lazy", "dog."])
        #expect(changes[0].inserted == ["Murmurly."])
    }

    @Test func englishWordsHandleInflections() {
        #expect(EnglishWords.contains("mailing"))
        #expect(EnglishWords.contains("meetings"))
        #expect(!EnglishWords.contains("Okonko"))
        #expect(!EnglishWords.contains("Belouve"))
    }
}
