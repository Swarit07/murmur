import Foundation
import MurmurKit

/// Demo content for design snapshots and the gallery (UI_REDESIGN.md v2 §9: the boards' names, rows,
/// dictionary and snippets are fixture data for snapshots only). Never written to the owner's store.
public enum DemoData {
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
