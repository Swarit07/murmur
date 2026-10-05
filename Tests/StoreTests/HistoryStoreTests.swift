import Core
import Foundation
@testable import Store
import Testing

@Suite("History store")
struct HistoryStoreTests {
    func record(_ status: DictationRecord.Status, raw: String? = nil, at seconds: TimeInterval = 0) -> DictationRecord {
        DictationRecord(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000 + seconds), durationMs: 2000, appBundleId: "com.apple.Notes",
            appName: "Notes", mode: "hold", engine: "parakeet-ultra", cleanup: "mlx:qwen3.5-4b", rawText: raw, status: status
        )
    }

    @Test func insertUpdateAndFetch() throws {
        let store = try HistoryStore(url: nil)
        var r = record(.recorded)
        try store.insert(r)
        try store.update(id: r.id) { $0.rawText = "hello there"; $0.status = .transcribed }
        r = try #require(try store.record(id: r.id))
        #expect(r.status == .transcribed)
        #expect(r.rawText == "hello there")
        var t = StageTimings()
        t.transcribeMs = 42
        try store.update(id: r.id) { $0.cleanText = "Hello there."; $0.status = .inserted; $0.timings = t }
        let done = try #require(try store.record(id: r.id))
        #expect(done.bestText == "Hello there.")
        #expect(done.timings?.transcribeMs == 42)
    }

    /// T2: the raw text is on disk before cleanup, so a process killed mid-cleanup leaves it.
    @Test func rawTextSurvivesReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let id: String
        do {
            let store = try HistoryStore(url: url)
            let r = record(.recorded)
            id = r.id
            try store.insert(r)
            try store.update(id: id) { $0.rawText = "keep me"; $0.status = .transcribed }
        }
        let reopened = try HistoryStore(url: url)
        #expect(try reopened.record(id: id)?.rawText == "keep me")
        #expect(try reopened.unfinished().map(\.id) == [id])
    }

    @Test func recentIsNewestFirstAndSearches() throws {
        let store = try HistoryStore(url: nil)
        try store.insert(record(.inserted, raw: "first one", at: 0))
        try store.insert(record(.inserted, raw: "second about Kubernetes", at: 10))
        try store.insert(record(.cancelled, raw: "third", at: 20))
        #expect(try store.recent().map(\.rawText) == ["third", "second about Kubernetes", "first one"])
        #expect(try store.recent(search: "kubernetes").count == 1)
        #expect(try store.lastWithText()?.rawText == "third")
    }

    @Test func lastWithTextSkipsEmptyRows() throws {
        let store = try HistoryStore(url: nil)
        try store.insert(record(.inserted, raw: "real text", at: 0))
        try store.insert(record(.recorded, raw: nil, at: 5))
        #expect(try store.lastWithText()?.rawText == "real text")
    }
}
