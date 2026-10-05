import Core
import Foundation

/// S4: where a dictation goes decides how it is written. The frontmost app picks one of four
/// categories (web apps by their address); each category has a style.
public enum AppCategory: String, CaseIterable, Sendable {
    case personal, work, email, other

    static let personalApps: Set<String> = [
        "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop",
        "org.whispersystems.signal-desktop", "com.facebook.archon", "com.hnc.Discord", "jp.naver.line.mac", "com.viber.osx",
    ]
    static let workApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "us.zoom.xos", "com.mattermost.desktop",
        "com.webex.meetingmanager", "com.cisco.webexmeetingsapp", "chat.rocket",
    ]
    static let emailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "com.superhuman.electron", "it.bloop.airmail2",
        "com.mimestream.Mimestream", "ch.protonmail.desktop", "com.freron.MailMate", "com.postbox-inc.postbox", "org.mozilla.thunderbird",
    ]
    /// Web apps by host (a suffix match, so "mail.google.com" also matches nothing broader).
    static let personalHosts = ["web.whatsapp.com", "messenger.com", "web.telegram.org", "discord.com", "instagram.com", "messages.google.com"]
    static let workHosts = ["app.slack.com", "teams.microsoft.com", "teams.live.com", "chat.google.com"]
    static let emailHosts = ["mail.google.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com", "mail.yahoo.com",
                             "app.fastmail.com", "mail.proton.me", "app.hey.com", "mail.superhuman.com"]

    /// The category for an app and, in a browser, the page's address. AI assistants and terminals,
    /// and anything unknown, are Other.
    public static func of(bundleId: String?, url: URL?) -> AppCategory {
        if let host = url?.host?.lowercased() {
            func matches(_ hosts: [String]) -> Bool { hosts.contains { host == $0 || host.hasSuffix("." + $0) } }
            if matches(emailHosts) { return .email }
            if matches(workHosts) { return .work }
            if matches(personalHosts) { return .personal }
            return .other
        }
        guard let bundleId else { return .other }
        if personalApps.contains(bundleId) { return .personal }
        if workApps.contains(bundleId) { return .work }
        if emailApps.contains(bundleId) { return .email }
        return .other
    }

    /// Styles offered for this category (very casual is Personal only; Excited! is not offered there).
    public var styles: [WritingStyle] {
        self == .personal ? [.formal, .casual, .veryCasual] : [.formal, .casual, .excited]
    }
}

public enum WritingStyle: String, CaseIterable, Sendable {
    /// Caps and punctuation: the cleaned text as is.
    case formal
    /// Caps, less punctuation: no comma after a greeting, no period at the end.
    case casual
    /// No caps, less punctuation.
    case veryCasual
    /// More exclamation marks.
    case excited

    /// Applies the style to cleaned text. Only plain English prose is restyled: text with line breaks
    /// (lists, paragraphs) or mostly non-English words is returned unchanged. Never touches facts:
    /// only sentence-initial capitals, a greeting's comma and sentence-final marks change.
    public func apply(to text: String) -> String {
        guard self != .formal, !text.contains("\n"), Self.looksEnglish(text) else { return text }
        var out = text
        switch self {
        case .formal:
            break
        case .casual:
            out = Self.dropGreetingComma(out)
            out = Self.dropFinalPeriod(out)
        case .veryCasual:
            out = Self.dropGreetingComma(out)
            out = Self.dropFinalPeriod(out)
            out = Self.lowercaseSentenceStarts(out)
        case .excited:
            out = Self.exclaim(out)
        }
        return out
    }

    static let greetings: Set<String> = ["hey", "hi", "hello", "thanks", "thank you", "yeah", "yes", "no", "ok", "okay", "sure", "oh", "so", "well", "great", "cool"]

    /// "Hey, are you free?" → "Hey are you free?"
    static func dropGreetingComma(_ text: String) -> String {
        guard let comma = text.firstIndex(of: ","), text.distance(from: text.startIndex, to: comma) <= 10 else { return text }
        let head = text[..<comma].lowercased()
        guard greetings.contains(head) else { return text }
        return String(text[..<comma]) + String(text[text.index(after: comma)...])
    }

    /// The last sentence's period goes; question and exclamation marks stay.
    static func dropFinalPeriod(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("."), !t.hasSuffix("..") {
            let lastWord = t.dropLast().split(separator: " ").last.map(String.init) ?? ""
            // Keep the dot of an abbreviation or a number like "3.5." stays sensible.
            if !lastWord.contains(".") { t.removeLast() }
        }
        return t
    }

    /// Lowercases each sentence's first word when it is an ordinary word (names, acronyms and
    /// dictionary spellings stay), and "I" in its usual forms.
    static func lowercaseSentenceStarts(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var sentenceStart = true
        for i in words.indices {
            let word = words[i]
            guard let first = word.first(where: \.isLetter) else { continue }
            let bare = word.trimmingCharacters(in: .punctuationCharacters)
            let pronounI = ["I", "I'm", "I'll", "I've", "I'd", "I’m", "I’ll", "I’ve", "I’d"].contains(bare)
            if (sentenceStart || pronounI), first.isUppercase, pronounI || isOrdinaryWord(bare) {
                if let index = word.firstIndex(of: first) {
                    words[i].replaceSubrange(index...index, with: String(first).lowercased())
                }
            }
            sentenceStart = word.last.map { ".!?".contains($0) } ?? false
        }
        return words.joined(separator: " ")
    }

    /// Capitalized only because it starts a sentence: the rest is lowercase and it is an English word.
    static func isOrdinaryWord(_ word: String) -> Bool {
        guard word.count > 0, word.dropFirst().allSatisfy({ !$0.isUppercase }) else { return false }
        return EnglishWords.contains(word.lowercased()) || ["let's", "let’s", "it's", "it’s", "that's", "that’s", "what's", "what’s"].contains(word.lowercased())
    }

    /// The final period becomes "!", and so does the period after a short thanks or greeting.
    static func exclaim(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix(".") && !t.hasSuffix("..") {
            t.removeLast()
            t += "!"
        } else if let last = t.last, last.isLetter || last.isNumber {
            t += "!"
        }
        for phrase in ["Thanks.", "Thank you.", "Congrats.", "Congratulations.", "Great.", "Awesome.", "Nice."] {
            t = t.replacingOccurrences(of: phrase, with: String(phrase.dropLast()) + "!")
        }
        return t
    }

    /// At least 60% of the words are in the English word list.
    static func looksEnglish(_ text: String) -> Bool {
        let words = text.split { !$0.isLetter && $0 != "'" && $0 != "’" }.map(String.init)
        guard !words.isEmpty else { return false }
        let known = words.filter { EnglishWords.contains($0) || ["i", "i'm", "i'll", "let's", "it's", "don't", "can't", "won't"].contains($0.lowercased()) }.count
        return Double(known) / Double(words.count) >= 0.6
    }
}
