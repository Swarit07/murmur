@testable import Cleanup
import Foundation
import Testing

@Suite("Styles (S4)")
struct StylesTests {
    let sentence = "Hey, are you free for lunch tomorrow? Let's do 12 if that works."

    @Test func eachStyleMatchesTheSpecExample() {
        #expect(WritingStyle.formal.apply(to: sentence) == sentence)
        #expect(WritingStyle.casual.apply(to: sentence) == "Hey are you free for lunch tomorrow? Let's do 12 if that works")
        #expect(WritingStyle.veryCasual.apply(to: sentence) == "hey are you free for lunch tomorrow? let's do 12 if that works")
        #expect(WritingStyle.excited.apply(to: sentence) == "Hey, are you free for lunch tomorrow? Let's do 12 if that works!")
    }

    @Test func veryCasualKeepsNamesAndFacts() {
        #expect(WritingStyle.veryCasual.apply(to: "Priya said the build is green. I'm happy.") == "Priya said the build is green. i'm happy")
        #expect(WritingStyle.veryCasual.apply(to: "Meet at 3.30 at the cafe.") == "meet at 3.30 at the cafe")
    }

    @Test func excitedTurnsThanksIntoExclamations() {
        #expect(WritingStyle.excited.apply(to: "Thanks. The demo went well.") == "Thanks! The demo went well!")
        #expect(WritingStyle.excited.apply(to: "Can you join?") == "Can you join?")
    }

    @Test func listsAndOtherLanguagesAreLeftAlone() {
        let list = "My goals:\n1. Ship the app.\n2. Write the docs.\n3. Rest."
        #expect(WritingStyle.casual.apply(to: list) == list)
        #expect(WritingStyle.veryCasual.apply(to: "Nos vemos mañana en la estación.") == "Nos vemos mañana en la estación.")
    }

    @Test func categoriesFromAppsAndAddresses() {
        #expect(AppCategory.of(bundleId: "com.apple.MobileSMS", url: nil) == .personal)
        #expect(AppCategory.of(bundleId: "com.tinyspeck.slackmacgap", url: nil) == .work)
        #expect(AppCategory.of(bundleId: "com.apple.mail", url: nil) == .email)
        #expect(AppCategory.of(bundleId: "com.apple.mail", url: URL(string: "about:blank")) == .email)
        #expect(AppCategory.of(bundleId: "com.google.Chrome", url: URL(string: "https://mail.google.com/mail/u/0/#inbox")) == .email)
        #expect(AppCategory.of(bundleId: "com.google.Chrome", url: URL(string: "https://app.slack.com/client/T1/C2")) == .work)
        #expect(AppCategory.of(bundleId: "com.apple.Safari", url: URL(string: "https://web.whatsapp.com/")) == .personal)
        #expect(AppCategory.of(bundleId: "com.apple.Safari", url: URL(string: "https://claude.ai/new")) == .other)
        #expect(AppCategory.of(bundleId: "com.apple.Terminal", url: nil) == .other)
        #expect(AppCategory.of(bundleId: "com.openai.chat", url: nil) == .other)
    }

    @Test func stylesOfferedPerCategory() {
        #expect(AppCategory.personal.styles == [.formal, .casual, .veryCasual])
        #expect(AppCategory.email.styles == [.formal, .casual, .excited])
    }
}

@Suite("Press enter (C11)")
struct PressEnterTests {
    @Test func splitsOnlyATrailingCommandWhenOn() {
        #expect(PressEnter.split("Sounds good, see you then. Press enter.", enabled: true) == ("Sounds good, see you then", true))
        #expect(PressEnter.split("ship it press enter", enabled: true) == ("ship it", true))
        #expect(PressEnter.split("Press enter", enabled: true) == ("", true))
        #expect(PressEnter.split("Ship it. Press enter.", enabled: false) == ("Ship it. Press enter.", false))
        #expect(PressEnter.split("Don't press enter yet, I'm still typing.", enabled: true) == ("Don't press enter yet, I'm still typing.", false))
        #expect(PressEnter.split("the express enterprise plan", enabled: true) == ("the express enterprise plan", false))
    }
}
