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

    // Names the engine cut short, names in lists, and how hard names are said (2026-10-05).
    let names = SpellingMatcher(spellings: ["Priya": [], "Marcus": [], "Joaquín": [], "Mei-Ling": [], "Siobhan": [], "Figma": []])

    @Test func fixesANameTheEngineCutShort() {
        #expect(names.apply("Pri and Marcus will present the migration.") == "Priya and Marcus will present the migration.")
        // Lowercase, too short a fragment, or a real word: left alone.
        #expect(names.apply("the pri setting") == "the pri setting")
        #expect(names.apply("Pr and Marcus") == "Pr and Marcus")
        #expect(names.apply("Mar and Priya") == "Mar and Priya")
        // A fragment that is a name of its own is a different person.
        let others = SpellingMatcher(spellings: ["Alexa": [], "Christa": [], "Jonas": [], "Joshua": []])
        #expect(others.apply("Alex and Chris met Jon and Josh.") == "Alex and Chris met Jon and Josh.")
    }

    @Test func writesASoundAlikeWordAsANameOnlyInAListOfNames() {
        #expect(names.apply("Send the link to Joaquin and mailing.") == "Send the link to Joaquín and Mei-Ling.")
        #expect(names.apply("Ask mailing and Priya.") == "Ask Mei-Ling and Priya.")
        #expect(names.apply("Check the mailing list.") == "Check the mailing list.")
        #expect(names.apply("Joaquín and mailing lists are next.") == "Joaquín and mailing lists are next.")
        #expect(names.apply("Send it to the team and mailing.") == "Send it to the team and mailing.")
    }

    @Test func matchesHowAHardNameIsSaid() {
        #expect(names.apply("Ask Chivan whether the replica is caught up.") == "Ask Siobhan whether the replica is caught up.")
        #expect(names.apply("Shivon said yes.") == "Siobhan said yes.")
        // Not in the dictionary: nothing to match.
        #expect(matcherWithout.apply("Ask Chivan whether") == "Ask Chivan whether")
        // Sounds alike but spelled far from the spoken form, or a real word: left alone.
        #expect(SpellingMatcher(spellings: ["Joaquín": []]).apply("Ask Aiken about it.") == "Ask Aiken about it.")
        #expect(names.apply("the chicken was fine") == "the chicken was fine")
    }

    var matcherWithout: SpellingMatcher { SpellingMatcher(spellings: ["Priya": []]) }
}
