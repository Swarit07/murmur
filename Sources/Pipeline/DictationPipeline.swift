import Audio
import Cleanup
import Context
import Core
import Foundation
import Insertion
import SpeechEngines

public struct DictationResult: Sendable {
    public enum Status: String, Sendable, Codable {
        case inserted
        case dropped
        case cancelled
        case transcriptionFailed
        case insertionFailed
    }

    public var status: Status
    public var raw: String?
    public var final: String?
    public var cleanup: CleanupOutcome?
    public var insertion: InsertionResult?
    public var timings: StageTimings
    public var error: String?
}

/// Release-to-paste pipeline: gate, transcribe, rules, model cleanup with time limit, insertion.
/// Drives the Core state machine so every transition is checked and signposted.
public final class DictationPipeline: Sendable {
    public let engine: any SpeechEngine
    public let cleanup: CleanupRunner
    public let gate: any SpeechGate
    public let insertion: InsertionTransaction
    public let request: CleanupRequest
    public let transcribeOptions: TranscribeOptions
    public let state = DictationStateHolder()

    public init(
        engine: any SpeechEngine,
        cleanup: CleanupRunner,
        gate: any SpeechGate = EnergySpeechGate(),
        insertion: InsertionTransaction = InsertionTransaction(),
        request: CleanupRequest = CleanupRequest(),
        transcribeOptions: TranscribeOptions = TranscribeOptions()
    ) {
        self.engine = engine
        self.cleanup = cleanup
        self.gate = gate
        self.insertion = insertion
        self.request = request
        self.transcribeOptions = transcribeOptions
    }

    /// Call on key down. Returns false when a dictation is already busy (the press is ignored).
    public func begin(mode: DictationMode = .hold) -> Bool {
        state.send(.start(mode)) != nil
    }

    public func cancel() {
        state.send(.cancel)
        state.send(.dismiss)
    }

    /// Runs everything after key release. `releasedAt` is the key-up time (Clock.now()), so the total
    /// covers capture flush through paste posted. `expectedFocus` is what had focus at key down.
    public func finish(
        samples: [Float],
        releasedAt: UInt64,
        captureFlushMs: Double,
        expectedFocus: FocusSnapshot?,
        currentFocus: @Sendable () -> FocusSnapshot = { FocusContext.snapshot() }
    ) async -> DictationResult {
        var timings = StageTimings()
        timings.captureFlushMs = captureFlushMs

        guard await gate.hasSpeech(samples) else {
            state.send(.discard)
            return DictationResult(status: .dropped, timings: timings)
        }
        guard state.send(.stop) != nil else {
            return DictationResult(status: .cancelled, timings: timings)
        }

        let raw: String
        do {
            let (text, ms) = try await Signposts.measure(.transcribe) {
                try await engine.transcribe(samples, options: transcribeOptions)
            }
            raw = text
            timings.transcribeMs = ms
        } catch {
            state.send(.transcriptionFailed)
            state.send(.dismiss)
            return DictationResult(status: .transcriptionFailed, timings: timings, error: String(describing: error))
        }
        guard state.state == .transcribing else { return DictationResult(status: .cancelled, raw: raw, timings: timings) }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.send(.discard)
            return DictationResult(status: .dropped, raw: raw, timings: timings)
        }
        state.send(.transcribed(raw))

        let outcome = await cleanup.run(raw, request: request)
        timings.rulesMs = outcome.rulesMs
        timings.llmMs = outcome.llmMs
        guard state.send(.cleaned(outcome.text)) != nil else {
            return DictationResult(status: .cancelled, raw: raw, final: outcome.text, cleanup: outcome, timings: timings)
        }

        guard let expectedFocus else {
            state.send(.insertionFailed(.pasteFailed, text: outcome.text))
            state.send(.dismiss)
            return DictationResult(status: .insertionFailed, raw: raw, final: outcome.text, cleanup: outcome, timings: timings)
        }
        let insertStart = Clock.now()
        let pastedAt = TimeStamp()
        let result = await insertion.insert(outcome.text, expected: expectedFocus, current: currentFocus()) {
            pastedAt.set(Clock.now())
        }
        if let pasted = pastedAt.value {
            timings.insertMs = Clock.ms(from: insertStart, to: pasted)
            timings.totalMs = Clock.ms(from: releasedAt, to: pasted)
        }
        switch result {
        case .inserted:
            state.send(.inserted)
            return DictationResult(status: .inserted, raw: raw, final: outcome.text, cleanup: outcome, insertion: result, timings: timings)
        case .failed(let failure):
            state.send(.insertionFailed(failure == .noTextBox ? .noTextBox : .pasteFailed, text: outcome.text))
            state.send(.dismiss)
            return DictationResult(status: .insertionFailed, raw: raw, final: outcome.text, cleanup: outcome, insertion: result, timings: timings, error: failure.rawValue)
        }
    }
}

final class TimeStamp: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64?
    func set(_ v: UInt64) { lock.withLock { _value = v } }
    var value: UInt64? { lock.withLock { _value } }
}

/// Appends one JSON line of timings per dictation. Never contains transcript text.
public enum TimingLog {
    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Murmur/m0/dictate-timings.jsonl")
    }

    public struct Entry: Codable, Sendable {
        public var date: Date
        public var engine: String
        public var cleanup: String
        public var status: String
        public var audioMs: Double
        public var firstAudioMs: Double?
        public var fallback: String?
        public var timings: StageTimings
        public var app: String?

        public init(
            date: Date, engine: String, cleanup: String, status: String, audioMs: Double, firstAudioMs: Double?,
            fallback: String?, timings: StageTimings, app: String?
        ) {
            self.date = date
            self.engine = engine
            self.cleanup = cleanup
            self.status = status
            self.audioMs = audioMs
            self.firstAudioMs = firstAudioMs
            self.fallback = fallback
            self.timings = timings
            self.app = app
        }
    }

    public static func append(_ entry: Entry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    public static func read() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }
}
