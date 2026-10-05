import Foundation
import MurmurKit

/// Demo content for design snapshots and the gallery (UI_REDESIGN.md v2 §9: the boards' names, rows,
/// dictionary and snippets are fixture data for snapshots only). Never written to the owner's store.
public enum DemoData {
    /// Edge cases for QA (`murmur-snap --stress`): very long transcripts, names, triggers and expansions,
    /// a long app name, an unbroken token, and many rows across days.
    public static func seedStress(_ store: HistoryStore) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let long = String(repeating: "This is a very long dictation that keeps going to test wrapping and truncation in the History list. ", count: 6)
        let rows: [(Int, String, String, String, DictationRecord.Status)] = [
            (0, "Microsoft Outlook Web Access (Enterprise Edition)", "com.microsoft.Outlook", long, .inserted),
            (0, "Terminal", "com.apple.Terminal", "https://example.com/a/very/long/url/without/any/spaces/that/should/not/overflow/the/row/" + String(repeating: "x", count: 120), .inserted),
            (0, "Notes", "com.apple.Notes", "Short.", .inserted),
            (-1, "Mail", "com.apple.mail", "Numbers 1,234,567.89 and dates 2026-10-05 and emoji-free symbols ⌘⌥⇧ ← → and quotes “like this”.", .pasteFailed),
            (-3, "Slack", "com.tinyspeck.slackmacgap", "Older row from earlier in the week.", .inserted),
            (-40, "Safari", "com.apple.Safari", "Much older row from last month.", .inserted),
        ]
        for (i, row) in rows.enumerated() {
            let date = calendar.date(byAdding: DateComponents(day: row.0, hour: 9, minute: 50 - i), to: today) ?? today
            try? store.insert(DictationRecord(startedAt: date, durationMs: 9_000, appBundleId: row.2, appName: row.1, mode: "hold",
                                              engine: "parakeet-ultra", cleanup: "mlx:qwen3.5-4b", rawText: row.3, cleanText: row.3, status: row.4))
        }
        try? store.save(DictionaryRecord(term: "Supercalifragilisticexpialidocious Incorporated Holdings", replacement: "Supercalifragilisticexpialidocious Incorporated Holdings International", source: .manual))
        try? store.save(DictionaryRecord(term: "a", replacement: "A", source: .suggested))
        try? store.save(SnippetRecord(cue: "an extremely long trigger phrase that someone might actually say out loud", expansion: long))
        try? store.save(SnippetRecord(cue: "x", expansion: "y"))
    }

    public static func seed(_ store: HistoryStore) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: today) ?? today
        }
        // (time, app, bundle id, raw words, cleaned text, status)
        let rows: [(Date, String, String, String?, String?, DictationRecord.Status)] = [
            (at(0, 9, 41), "Mail", "com.apple.mail", "hi priya thanks for the notes uh let's ship friday and keep the beta list small",
             "Hi Priya, thanks for the notes. Let’s ship Friday and keep the beta list small.", .inserted),
            (at(0, 9, 32), "Messages", "com.apple.MobileSMS", "um running like ten min late save me a seat", "running 10 min late, save me a seat?", .inserted),
            (at(0, 9, 20), "Code", "com.microsoft.VSCode", "rename fetch user to load profile and add a null check before the paste fallback",
             "Rename fetchUser to loadProfile and add a null check before the paste fallback.", .inserted),
            (at(0, 9, 5), "Notes", "com.apple.Notes", "", "", .inserted),
            (at(-1, 17, 12), "Slack", "com.tinyspeck.slackmacgap", "build's ready for review feedback by friday", "Build’s ready for review. Feedback by Friday?", .inserted),
            (at(-1, 15, 48), "Notes", "com.apple.Notes", "remind me to call mom on sunday at noon", "Remind me to call Mom on Sunday at noon.", .pasteFailed),
            (at(-1, 11, 3), "Safari", "com.apple.Safari", nil, nil, .transcriptionFailed),
        ]
        for (date, app, bundle, raw, clean, status) in rows {
            let words = (clean ?? raw ?? "").split(separator: " ").count
            let r = DictationRecord(startedAt: date, durationMs: Double(max(words, 4)) * 420, appBundleId: bundle, appName: app,
                                    mode: "hold", engine: "parakeet-ultra", cleanup: "mlx:qwen3.5-4b", rawText: raw, cleanText: clean, status: status)
            try? store.insert(r)
        }
        let words: [(heard: String, word: String, learned: Bool)] = [
            ("Priya", "Priya", false), ("swift you eye", "SwiftUI", false), ("WhisperKit", "WhisperKit", true), ("Parakeet", "Parakeet", true),
            ("cube control", "kubectl", false), ("Newsreader", "Newsreader", false), ("chwen", "Qwen", true),
        ]
        for w in words {
            try? store.save(DictionaryRecord(term: w.heard, replacement: w.word, source: w.learned ? .suggested : .manual))
        }
        let snippets: [(String, String)] = [
            ("sign off", "Thanks,\nSwarit"), ("my calendar", "Here’s a link to grab time with me: [YOUR LINK]"),
            ("standup", "Yesterday:\nToday:\nBlockers: none"), ("repo link", "Murmur is open source: [GITHUB_URL]"),
            ("thanks for waiting", "Thanks for your patience. I’ll get back to you by end of day."), ("my address", "[YOUR ADDRESS]"),
        ]
        for (cue, expansion) in snippets {
            try? store.save(SnippetRecord(cue: cue, expansion: expansion))
        }
    }
}
