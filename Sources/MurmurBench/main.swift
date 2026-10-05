import ArgumentParser
import Audio
import Cleanup
import Context
import Core
import Foundation
import Insertion
import Pipeline
import SpeechEngines

@main
struct MurmurBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "murmur-bench",
        abstract: "Milestone 0 bake-off: record the corpus, run engines and cleanup models, write the report.",
        subcommands: [RecordCorpus.self, Run.self, EnginePass.self, CleanupPass.self, StallTest.self, E2E.self, Report.self, Status.self],
        defaultSubcommand: Status.self
    )
}

struct CommonPaths: ParsableArguments {
    @Option(help: "Corpus folder with manifest.json.")
    var corpus: String = "corpus"

    @Option(help: "Folder for raw result files.")
    var results: String = "results/raw"

    var corpusURL: URL { URL(fileURLWithPath: corpus) }
    var resultsURL: URL { URL(fileURLWithPath: results) }
}

// MARK: - status

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show how much of the corpus is recorded and which results exist.")
    @OptionGroup var paths: CommonPaths

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        print("Corpus: \(corpus.clips.count) clips")
        for set in Corpus.setOrder {
            let clips = corpus.clips(in: set)
            let done = clips.filter { FileManager.default.fileExists(atPath: Corpus.audioURL($0, in: paths.corpusURL).path) }.count
            print("  \(set.padding(toLength: 11, withPad: " ", startingAt: 0)) \(String(format: "%3d / %3d", done, clips.count)) recorded")
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: paths.results)) ?? []
        print("Results in \(paths.results): \(files.filter { $0.hasSuffix(".json") }.sorted().joined(separator: ", "))")
    }
}

// MARK: - record-corpus

struct RecordCorpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record-corpus",
        abstract: "Walk through the corpus: shows each sentence, records it, saves the WAV and reference text."
    )
    @OptionGroup var paths: CommonPaths

    @Option(help: "Only this set (plain, numbers, names, quiet, silence, correction, levels).")
    var set: String?

    @Option(help: "Only this clip id, re-recording it.")
    var clip: String?

    @Flag(help: "Re-record clips that already have audio.")
    var redo = false

    func run() async throws {
        guard await MicrophonePermission.ensure() else {
            throw ValidationError("Microphone access is denied. Allow your terminal app in System Settings > Privacy & Security > Microphone, then run this again.")
        }
        let corpus = try Corpus.load(from: paths.corpusURL)
        var clips = corpus.clips
        if let set { clips = clips.filter { $0.set == set } }
        if let clip { clips = clips.filter { $0.id == clip } }
        let todo = clips.filter { redo || clip != nil || !FileManager.default.fileExists(atPath: Corpus.audioURL($0, in: paths.corpusURL).path) }
        guard !todo.isEmpty else {
            print("Everything selected is already recorded. Use --redo or --clip <id> to record again.")
            return
        }
        let recorder = AudioRecorder()
        recorder.prepare()
        print("""

        Murmur corpus recorder · \(todo.count) clips to record · microphone: \(recorder.deviceName)
        Use the microphone you will dictate with. For each clip: press Enter, speak, press Enter.
        After each take: Enter keeps it, r redoes it, p plays it back, s skips, q quits (progress is saved).

        """)
        var currentSet = ""
        var index = 0
        while index < todo.count {
            let item = todo[index]
            if item.set != currentSet {
                currentSet = item.set
                print("\n━━ \(item.set.uppercased()) ━━ \(corpus.sets[item.set] ?? "")\n")
            }
            print("[\(index + 1)/\(todo.count)] \(item.id)")
            if item.isSilence {
                print("   Do this (no words): \(item.instruction ?? "Stay silent.")")
            } else {
                print("   Read:  \(item.read)")
                if let say = item.say { print("   Say it like: \(say)") }
            }
            print("   Press Enter to start…", terminator: "")
            fflush(stdout)
            guard let startKey = await Terminal.readLine() else { return }
            if startKey.lowercased() == "q" { return }
            if startKey.lowercased() == "s" { index += 1; continue }
            try recorder.start()
            print("   ● Recording… press Enter to stop.", terminator: "")
            fflush(stdout)
            _ = await Terminal.readLine()
            let samples = recorder.stop()
            let url = Corpus.audioURL(item, in: paths.corpusURL)
            let tmp = url.deletingPathExtension().appendingPathExtension("take.wav")
            try WAV.write(samples, to: tmp)
            let seconds = Double(samples.count) / AudioFormat.sampleRate
            let peakDb = 20 * log10(max(Levels.peak(samples), 1e-6))
            var warning = ""
            if !item.isSilence && peakDb < -35 { warning = "  ⚠ very quiet; check the microphone" }
            if !item.isSilence && seconds < 0.8 { warning = "  ⚠ very short" }
            print(String(format: "   %.1f s · peak %.0f dBFS%@", seconds, peakDb, warning))

            var decided = false
            while !decided {
                print("   Keep? [Enter] keep · r redo · p play · q quit: ", terminator: "")
                fflush(stdout)
                let answer = (await Terminal.readLine() ?? "q").lowercased()
                switch answer {
                case "p":
                    let player = Process()
                    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    player.arguments = [tmp.path]
                    try? player.run()
                    player.waitUntilExit()
                case "r":
                    try? FileManager.default.removeItem(at: tmp)
                    decided = true
                case "q":
                    try? FileManager.default.removeItem(at: tmp)
                    return
                default:
                    try? FileManager.default.removeItem(at: url)
                    try FileManager.default.moveItem(at: tmp, to: url)
                    try (item.isSilence ? "" : item.reference).write(to: Corpus.referenceURL(item, in: paths.corpusURL), atomically: true, encoding: .utf8)
                    index += 1
                    decided = true
                }
            }
        }
        print("\nDone. Run `murmur-bench status` to check coverage, then `murmur-bench run`.")
    }
}

// MARK: - engine-pass

struct EnginePass: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "engine-pass", abstract: "Run one engine over the recorded corpus (used by `run`).")
    @OptionGroup var paths: CommonPaths

    @Option var engine: String
    @Option(help: "Transcription latency samples to collect.")
    var runs: Int = 100
    @Option(help: "Only clips up to this many seconds count toward latency runs.")
    var maxSeconds: Double = 15

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let engine = try EngineCatalog.make(engine)
        var result = EnginePassResult(engine: engine.id, isLocal: engine.isLocal, build: ResultFiles.buildConfiguration)
        let out = paths.resultsURL.appendingPathComponent("engine-\(ResultFiles.safeName(engine.id)).json")
        result.footprintBeforeLoad = ProcessMemory.snapshot()?.footprint
        let start = Clock.now()
        do {
            try await engine.load()
        } catch {
            result.error = String(describing: error)
            try ResultFiles.write(result, to: out)
            print("\(engine.id): load failed: \(error)")
            return
        }
        result.loadMs = Clock.ms(since: start)
        result.footprintAfterLoad = ProcessMemory.snapshot()?.footprint
        print("\(engine.id): loaded in \(Format.ms(result.loadMs!))")

        let energy = EnergySpeechGate()
        let silero = SileroSpeechGate()
        try? await silero.load()
        var audio: [String: [Float]] = [:]
        for clip in corpus.clips {
            let url = Corpus.audioURL(clip, in: paths.corpusURL)
            guard let samples = try? WAV.read(url) else { continue }
            audio[clip.id] = samples
            let audioMs = Double(samples.count) / AudioFormat.sampleRate * 1000
            var entry = EnginePassResult.Clip(
                id: clip.id, set: clip.set, audioMs: audioMs,
                energyGate: await energy.hasSpeech(samples), sileroGate: await silero.hasSpeech(samples)
            )
            let t = Clock.now()
            do {
                entry.text = try await engine.transcribe(samples, options: TranscribeOptions(language: "en"))
                entry.ms = Clock.ms(since: t)
            } catch {
                entry.error = String(describing: error)
            }
            result.clips.append(entry)
            print("  \(clip.id) \(entry.ms.map(Format.ms) ?? "error") \(entry.text ?? entry.error ?? "")")
        }

        // Latency runs over speech clips up to maxSeconds, cycling until `runs` samples.
        let timed = corpus.clips.filter { !$0.isSilence }.compactMap { clip -> (String, [Float])? in
            guard let s = audio[clip.id], Double(s.count) / AudioFormat.sampleRate <= maxSeconds else { return nil }
            return (clip.id, s)
        }
        if !timed.isEmpty {
            var i = 0
            while result.runs.count < runs {
                let (id, samples) = timed[i % timed.count]
                let t = Clock.now()
                if (try? await engine.transcribe(samples, options: TranscribeOptions(language: "en"))) != nil {
                    result.runs.append(.init(id: id, audioMs: Double(samples.count) / 16, ms: Clock.ms(since: t)))
                }
                i += 1
                if i > runs * 3 { break }
            }
        }
        result.peakFootprint = ProcessMemory.snapshot()?.peakFootprint
        try ResultFiles.write(result, to: out)
        let ms = result.runs.map(\.ms)
        print("\(engine.id): \(result.clips.count) clips · p50 \(Stats.percentile(ms, 50).map(Format.ms) ?? "-") · p95 \(Stats.percentile(ms, 95).map(Format.ms) ?? "-") → \(out.path)")
    }
}

// MARK: - cleanup-pass

struct CleanupPass: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cleanup-pass", abstract: "Run one cleanup provider over corpus text (used by `run`).")
    @OptionGroup var paths: CommonPaths

    @Option var provider: String
    @Option(help: "\"reference\" for the written sentences, or an engine id to use its transcripts.")
    var source: String = "reference"
    @Option var runs: Int = 100
    @Option(help: "Time limit in milliseconds.")
    var limit: Int = 800

    static let sets = ["correction", "levels", "numbers", "names", "plain", "quiet"]

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let provider = try CleanupCatalog.make(provider)
        let providerId = provider?.id ?? "rules"
        var result = CleanupPassResult(provider: providerId, source: source, build: ResultFiles.buildConfiguration)
        let out = paths.resultsURL.appendingPathComponent("cleanup-\(ResultFiles.safeName(providerId))-\(ResultFiles.safeName(source)).json")

        // Inputs.
        var inputs: [(CorpusClip, String)] = []
        if source == "reference" {
            inputs = corpus.clips.filter { Self.sets.contains($0.set) }.map { ($0, $0.reference) }
        } else {
            let engineFile = paths.resultsURL.appendingPathComponent("engine-\(ResultFiles.safeName(source)).json")
            guard let engineResult = ResultFiles.read(EnginePassResult.self, from: engineFile) else {
                throw ValidationError("No transcripts at \(engineFile.path). Run the engine pass first.")
            }
            let texts = Dictionary(uniqueKeysWithValues: engineResult.clips.compactMap { c in c.text.map { (c.id, $0) } })
            inputs = corpus.clips.filter { Self.sets.contains($0.set) }.compactMap { clip in texts[clip.id].map { (clip, $0) } }
        }
        guard !inputs.isEmpty else { throw ValidationError("No inputs for source \(source).") }

        result.footprintBeforeLoad = ProcessMemory.snapshot()?.footprint
        if let provider {
            let start = Clock.now()
            do {
                try await provider.load()
            } catch {
                result.error = String(describing: error)
                try ResultFiles.write(result, to: out)
                print("\(providerId): load failed: \(error)")
                return
            }
            result.loadMs = Clock.ms(since: start)
            print("\(providerId): loaded in \(Format.ms(result.loadMs!))")
        }
        result.footprintAfterLoad = ProcessMemory.snapshot()?.footprint

        let runner = CleanupRunner(provider: provider, timeLimit: .milliseconds(limit))
        for (clip, text) in inputs {
            let levels: [CleanupLevel] = clip.set == "levels" ? [.light, .medium] : [.light]
            for level in levels {
                let o = await runner.run(text, request: CleanupRequest(level: level))
                result.clips.append(.init(
                    id: clip.id, set: clip.set, level: level.rawValue, input: text, rulesText: o.rulesText,
                    modelText: o.modelText, final: o.text, fallback: o.fallback?.rawValue, flags: o.flags.map(\.description),
                    error: o.error, rulesMs: o.rulesMs, llmMs: o.llmMs
                ))
                if level == .light {
                    result.runs.append(.init(id: clip.id, rulesMs: o.rulesMs, llmMs: o.llmMs, totalMs: o.rulesMs + (o.llmMs ?? 0), fallback: o.fallback?.rawValue))
                }
                print("  \(clip.id) [\(level.rawValue)] \(o.llmMs.map(Format.ms) ?? "-") \(o.fallback.map { "(\($0.rawValue)) " } ?? "")\(o.text)")
            }
        }
        // More latency samples until `runs`.
        var i = 0
        while result.runs.count < runs, !inputs.isEmpty {
            let (clip, text) = inputs[i % inputs.count]
            let o = await runner.run(text, request: CleanupRequest(level: .light))
            result.runs.append(.init(id: clip.id, rulesMs: o.rulesMs, llmMs: o.llmMs, totalMs: o.rulesMs + (o.llmMs ?? 0), fallback: o.fallback?.rawValue))
            i += 1
        }
        result.peakFootprint = ProcessMemory.snapshot()?.peakFootprint
        try ResultFiles.write(result, to: out)
        let llm = result.runs.compactMap(\.llmMs)
        print("\(providerId) on \(source): p50 \(Stats.percentile(llm, 50).map(Format.ms) ?? "-") · p95 \(Stats.percentile(llm, 95).map(Format.ms) ?? "-") → \(out.path)")
    }
}

// MARK: - stall-test

struct StallTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stall-test", abstract: "C6: with the model deliberately stalled, text must land within 1.5 s.")
    @OptionGroup var paths: CommonPaths
    @Option var trials: Int = 20

    func run() async throws {
        let runner = CleanupRunner(provider: StalledCleanupProvider(), timeLimit: .milliseconds(800))
        var times: [Double] = []
        for i in 0..<trials {
            let start = Clock.now()
            let o = await runner.run("um let's meet at 3 at the cafe", request: CleanupRequest())
            let ms = Clock.ms(since: start)
            times.append(ms)
            print("  trial \(i + 1): \(Format.ms(ms)) · fallback \(o.fallback?.rawValue ?? "none") · \(o.text)")
        }
        let summary: [String: Double] = ["max": times.max() ?? 0, "p50": Stats.percentile(times, 50) ?? 0, "trials": Double(trials)]
        try ResultFiles.write(summary, to: paths.resultsURL.appendingPathComponent("stall-test.json"))
        print("max \(Format.ms(times.max() ?? 0)) over \(trials) trials (limit 1500 ms): \((times.max() ?? 9999) < 1500 ? "PASS" : "FAIL")")
    }
}

// MARK: - e2e

struct E2E: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "e2e",
        abstract: "Replay recorded clips through the whole pipeline into a real TextEdit document: transcribe, clean up, paste. Needs Accessibility.",
        discussion: "Opens a new TextEdit document and pastes into it. Do not use the keyboard or mouse while it runs."
    )
    @OptionGroup var paths: CommonPaths
    @Option var engine: String = "parakeet-v3"
    @Option var cleanup: String = "rules"
    @Option var runs: Int = 100

    func run() async throws {
        guard Permissions.accessibility else {
            Permissions.promptAccessibility()
            throw ValidationError("Accessibility is not granted for your terminal app. Add it in System Settings > Privacy & Security > Accessibility, then reopen the terminal.")
        }
        let corpus = try Corpus.load(from: paths.corpusURL)
        let clips = corpus.clips.filter { !$0.isSilence && Set(["plain", "numbers", "names", "levels"]).contains($0.set) }
            .compactMap { c in (try? WAV.read(Corpus.audioURL(c, in: paths.corpusURL))).map { (c, $0) } }
        guard !clips.isEmpty else { throw ValidationError("No recorded clips yet. Run record-corpus first.") }

        let engine = try EngineCatalog.make(engine)
        try await engine.load()
        let provider = try CleanupCatalog.make(cleanup)
        try await provider?.load()
        let pipeline = DictationPipeline(engine: engine, cleanup: CleanupRunner(provider: provider))

        let script = """
        tell application "TextEdit"
            activate
            make new document
        end tell
        """
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        try osa.run()
        osa.waitUntilExit()
        try await Task.sleep(for: .seconds(1.5))

        var result = E2EResult(engine: engine.id, cleanup: provider?.id ?? "rules", app: "com.apple.TextEdit", build: ResultFiles.buildConfiguration)
        for i in 0..<runs {
            let (clip, samples) = clips[i % clips.count]
            let focus = FocusContext.snapshot()
            guard focus.bundleId == "com.apple.TextEdit" else {
                print("TextEdit lost focus (now \(focus.bundleId ?? "?")); stopping.")
                break
            }
            _ = pipeline.begin()
            let released = Clock.now()
            let r = await pipeline.finish(samples: samples, releasedAt: released, captureFlushMs: 0, expectedFocus: focus)
            var restored: Bool?
            if case .inserted(let rest) = r.insertion { restored = rest }
            result.runs.append(.init(id: clip.id, status: r.status.rawValue, audioMs: Double(samples.count) / 16, timings: r.timings, restored: restored))
            print("  [\(i + 1)/\(runs)] \(clip.id) \(r.status.rawValue) · \(r.timings.summary)")
            // Separate entries in the document.
            try? await Task.sleep(for: .milliseconds(150))
        }
        let out = paths.resultsURL.appendingPathComponent("e2e-\(ResultFiles.safeName(engine.id))-\(ResultFiles.safeName(provider?.id ?? "rules")).json")
        try ResultFiles.write(result, to: out)
        let totals = result.runs.compactMap(\.timings.totalMs)
        print("release → paste: p50 \(Stats.percentile(totals, 50).map(Format.ms) ?? "-") · p95 \(Stats.percentile(totals, 95).map(Format.ms) ?? "-") over \(totals.count) runs → \(out.path)")
    }
}

// MARK: - run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run every engine pass and cleanup pass (each in its own process), the stall test, then write docs/m0-results.md."
    )
    @OptionGroup var paths: CommonPaths

    @Option(help: "Comma-separated engines. Default: all local engines, plus groq-whisper if GROQ_API_KEY is set.")
    var engines: String?

    @Option(help: "Comma-separated cleanup providers. Default: rules, apple-foundation, the MLX models, plus groq if GROQ_API_KEY is set.")
    var cleanups: String?

    @Option var runs: Int = 100

    @Option(help: "Comma-separated engines whose transcripts go through cleanup. Default: the local engine with the lowest WER.")
    var cleanupSources: String?

    @Flag(help: "Skip engine passes and reuse existing engine results.")
    var skipEngines = false

    @Flag(help: "Skip cleanup passes and reuse existing cleanup results.")
    var skipCleanup = false

    @Flag(help: "Skip cleanup passes on the written sentences (keep existing ones).")
    var skipReference = false

    func run() async throws {
        let hasKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]?.isEmpty == false
        let engineIds = engines.map { $0.split(separator: ",").map(String.init) }
            ?? ["parakeet-v3", "parakeet-v2", "parakeet-ultra", "parakeet-phonon2", "whisper-turbo", "apple-speech"] + (hasKey ? ["groq-whisper"] : [])
        var cleanupIds = cleanups.map { $0.split(separator: ",").map(String.init) }
            ?? ["rules", "apple-foundation"] + (CleanupCatalog.mlxAvailable ? CleanupCatalog.mlxNames.map { "mlx:\($0)" } : []) + (hasKey ? ["groq"] : [])
        if !CleanupCatalog.mlxAvailable { cleanupIds.removeAll { $0.hasPrefix("mlx:") } }

        let corpus = try Corpus.load(from: paths.corpusURL)
        let recorded = corpus.clips.filter { FileManager.default.fileExists(atPath: Corpus.audioURL($0, in: paths.corpusURL).path) }.count
        print("Corpus: \(recorded) of \(corpus.clips.count) clips recorded.")

        if !skipEngines && recorded > 0 {
            for id in engineIds {
                print("\n▶ engine-pass \(id)")
                try Self.spawn(["engine-pass", "--engine", id, "--runs", "\(runs)", "--corpus", paths.corpus, "--results", paths.results])
            }
        }

        // Pick the transcript source for end-to-end cleanup: the engine with the lowest WER.
        let sources = cleanupSources.map { $0.split(separator: ",").map(String.init) }
            ?? ReportBuilder(paths: paths).bestEngine().map { [$0] } ?? []
        if !skipCleanup {
            for id in cleanupIds {
                if !skipReference {
                    print("\n▶ cleanup-pass \(id) on reference text")
                    try Self.spawn(["cleanup-pass", "--provider", id, "--source", "reference", "--runs", "\(runs)", "--corpus", paths.corpus, "--results", paths.results])
                }
                for source in sources {
                    print("\n▶ cleanup-pass \(id) on \(source) transcripts")
                    try Self.spawn(["cleanup-pass", "--provider", id, "--source", source, "--runs", "0", "--corpus", paths.corpus, "--results", paths.results])
                }
            }
        }
        print("\n▶ stall-test")
        try Self.spawn(["stall-test", "--results", paths.results])

        let markdown = ReportBuilder(paths: paths).markdown()
        try markdown.write(to: URL(fileURLWithPath: "docs/m0-results-tables.md"), atomically: true, encoding: .utf8)
        print("\nWrote docs/m0-results-tables.md")
    }

    /// Runs this executable again with `arguments`, so each pass gets a fresh process and clean memory numbers.
    static func spawn(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        if !FileManager.default.isExecutableFile(atPath: process.executableURL!.path) {
            process.executableURL = Bundle.main.executableURL
        }
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }
}

// MARK: - report

struct Report: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Rebuild docs/m0-results-tables.md from the raw result files.")
    @OptionGroup var paths: CommonPaths
    @Option var out: String = "docs/m0-results-tables.md"

    func run() async throws {
        let markdown = ReportBuilder(paths: paths).markdown()
        try markdown.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
        print(markdown)
    }
}

enum Terminal {
    /// Reads a line without blocking the cooperative thread pool. Nil at end of input.
    static func readLine() async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            Thread.detachNewThread {
                c.resume(returning: Swift.readLine())
            }
        }
    }
}
