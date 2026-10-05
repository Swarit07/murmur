import Foundation
import MurmurKit

/// Demo content for design snapshots and the gallery: a few days of History in every state,
/// dictionary words and snippets. Never written to the owner's store.
public enum DemoData {
    /// Demo content for design snapshots: a few days of History in every state, dictionary words, snippets.
    public static func seed(_ store: HistoryStore) {
        let now = Date()
        let rows: [(Double, String, String?, DictationRecord.Status, Bool)] = [
            (0.1, "Can you send me the slides before the 3 pm sync? I want to add the Q3 numbers.", "Slack", .inserted, false),
            (0.6, "Thanks for the quick turnaround, this looks great. Let's ship it on Friday.", "Mail", .inserted, false),
            (1.2, "Refactor the history store so every write is its own transaction, then add a migration test for the useRaw column and run the full suite before merging. Also double-check the retry path for rows that were left in the recorded state after a crash, because those should come back as Recover, not Retry, and the button label should say so.", "Cursor", .inserted, false),
            (2.0, "Remind me to call Siobhan about the venue.", "Notes", .pasteFailed, false),
            (3.5, "um so I think we should uh move the launch to Friday", "Messages", .inserted, true),
            (26, "Here are the three things we agreed on: the pricing page, the onboarding email, and the changelog.", "Notion", .inserted, false),
            (27, "Book a table for four at 7:30.", "Messages", .inserted, false),
            (75, "The build is green again after the Metal fix.", "Terminal", .inserted, false),
            (76, "", "Safari", .transcriptionFailed, false),
        ]
        for (hoursAgo, text, app, status, useRaw) in rows {
            var r = DictationRecord(startedAt: now.addingTimeInterval(-hoursAgo * 3600), durationMs: Double(max(text.split(separator: " ").count, 4)) * 420,
                                    appBundleId: nil, appName: app, mode: "hold", engine: "parakeet-ultra", cleanup: "mlx:qwen3.5-4b",
                                    rawText: text.isEmpty ? nil : text, cleanText: text.isEmpty ? nil : (useRaw ? "I think we should move the launch to Friday." : text),
                                    status: status)
            r.useRaw = useRaw
            try? store.insert(r)
        }
        for (heard, word, suggested) in [("Chivan", "Siobhan", false), ("Q three", "Q3", false), ("Murmur", "Murmur", false), ("GRDB", "GRDB", false), ("Para keet", "Parakeet", true)] {
            try? store.save(DictionaryRecord(term: heard, replacement: word, source: suggested ? .suggested : .manual))
        }
        try? store.save(SnippetRecord(cue: "my email", expansion: "hello@example.com"))
        try? store.save(SnippetRecord(cue: "sign off", expansion: "Thanks,\nAlex"))
        try? store.save(SnippetRecord(cue: "calendar link", expansion: "https://cal.example.com/alex/30min"))
    }
}
