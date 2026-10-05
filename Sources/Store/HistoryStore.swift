import Core
import Foundation
import GRDB

/// Where Murmur keeps its files.
public enum MurmurPaths {
    public static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Murmur")
    }

    public static var database: URL { appSupport.appendingPathComponent("murmur.sqlite") }
    public static var audio: URL { appSupport.appendingPathComponent("Audio") }
}

/// One dictation, from key release to insertion. Spec section 4, data model.
public struct DictationRecord: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public enum Status: String, Codable, Sendable, CaseIterable {
        /// Audio captured, not yet transcribed. A row left here after a crash can be retried from audio.
        case recorded
        /// Raw transcript saved; cleanup not finished. A row left here keeps the raw text.
        case transcribed
        case inserted
        case cancelled
        case transcriptionFailed
        case pasteFailed
        case noTextBox
    }

    public static let databaseTableName = "dictation"

    public var id: String
    public var startedAt: Date
    public var durationMs: Double
    public var appBundleId: String?
    public var appName: String?
    public var mode: String
    public var engine: String
    public var cleanup: String?
    public var rawText: String?
    public var cleanText: String?
    public var status: Status
    public var errorCode: String?
    public var audioPath: String?
    public var timings: StageTimings?

    public init(
        id: String = UUID().uuidString, startedAt: Date, durationMs: Double, appBundleId: String?, appName: String?,
        mode: String, engine: String, cleanup: String?, rawText: String? = nil, cleanText: String? = nil,
        status: Status, errorCode: String? = nil, audioPath: String? = nil, timings: StageTimings? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.appBundleId = appBundleId
        self.appName = appName
        self.mode = mode
        self.engine = engine
        self.cleanup = cleanup
        self.rawText = rawText
        self.cleanText = cleanText
        self.status = status
        self.errorCode = errorCode
        self.audioPath = audioPath
        self.timings = timings
    }

    /// The best text this dictation has: cleaned if there is one, raw otherwise.
    public var bestText: String? {
        if let cleanText, !cleanText.isEmpty { return cleanText }
        if let rawText, !rawText.isEmpty { return rawText }
        return nil
    }

    public enum Columns {
        static let startedAt = Column(CodingKeys.startedAt)
        static let status = Column(CodingKeys.status)
        static let rawText = Column(CodingKeys.rawText)
        static let cleanText = Column(CodingKeys.cleanText)
    }
}

/// SQLite through GRDB. Every write is its own transaction, so a row survives the app being killed
/// right after the call returns.
public final class HistoryStore: Sendable {
    public static let didChange = Notification.Name("MurmurHistoryDidChange")

    let db: DatabaseQueue

    /// Opens (and migrates) the database at `url`; `nil` opens an in-memory database for tests.
    public init(url: URL? = MurmurPaths.database) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try DatabaseQueue(path: url.path)
        } else {
            db = try DatabaseQueue()
        }
        try Self.migrator.migrate(db)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.primaryKey("id", .text)
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("durationMs", .double).notNull()
                t.column("appBundleId", .text)
                t.column("appName", .text)
                t.column("mode", .text).notNull()
                t.column("engine", .text).notNull()
                t.column("cleanup", .text)
                t.column("rawText", .text)
                t.column("cleanText", .text)
                t.column("status", .text).notNull()
                t.column("errorCode", .text)
                t.column("audioPath", .text)
                t.column("timings", .jsonText)
            }
            // Used from Milestone 3 on (dictionary, snippets, styles); created now so the schema matches the spec.
            try db.create(table: "dictionary_entry") { t in
                t.primaryKey("id", .text)
                t.column("term", .text).notNull()
                t.column("replacement", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "snippet") { t in
                t.primaryKey("id", .text)
                t.column("cue", .text).notNull()
                t.column("expansion", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "app_style") { t in
                t.primaryKey("key", .text)
                t.column("category", .text).notNull()
                t.column("styleOverride", .text)
            }
        }
        return migrator
    }

    public func insert(_ record: DictationRecord) throws {
        try db.write { try record.insert($0) }
        notify()
    }

    /// Applies `change` to the stored row and saves it.
    @discardableResult
    public func update(id: String, _ change: (inout DictationRecord) -> Void) throws -> DictationRecord? {
        let updated = try db.write { db -> DictationRecord? in
            guard var record = try DictationRecord.fetchOne(db, key: id) else { return nil }
            change(&record)
            try record.update(db)
            return record
        }
        notify()
        return updated
    }

    public func record(id: String) throws -> DictationRecord? {
        try db.read { try DictationRecord.fetchOne($0, key: id) }
    }

    /// Newest first. `search` matches raw or cleaned text, case-insensitively.
    public func recent(limit: Int = 200, search: String? = nil) throws -> [DictationRecord] {
        try db.read { db in
            var request = DictationRecord.order(DictationRecord.Columns.startedAt.desc)
            if let search, !search.isEmpty {
                let pattern = "%\(search)%"
                request = request.filter(DictationRecord.Columns.rawText.like(pattern) || DictationRecord.Columns.cleanText.like(pattern))
            }
            return try request.limit(limit).fetchAll(db)
        }
    }

    /// The newest dictation that has any text, whatever its status. Used by Paste and Copy last transcript.
    public func lastWithText() throws -> DictationRecord? {
        try db.read { db in
            try DictationRecord
                .filter(DictationRecord.Columns.rawText != nil)
                .order(DictationRecord.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    /// Rows a crash or quit left unfinished (still `recorded` or `transcribed`).
    public func unfinished() throws -> [DictationRecord] {
        try db.read { db in
            try DictationRecord
                .filter([DictationRecord.Status.recorded.rawValue, DictationRecord.Status.transcribed.rawValue].contains(DictationRecord.Columns.status))
                .order(DictationRecord.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try db.read { try DictationRecord.fetchCount($0) }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
