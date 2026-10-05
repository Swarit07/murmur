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
        subcommands: [RecordCorpus.self, Run.self, EnginePass.self, CleanupPass.self, StallTest.self, E2E.self, Report.self, Status.self, VocabTest.self, VocabFalseTest.self, StyleTest.self, LongTest.self, GuardTest.self, PunctuationTest.self],
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

    @Flag(help: "Turn Smart Formatting on, as the app does by default.")
    var smartFormatting = false

    static let sets = ["correction", "levels", "numbers", "names", "plain", "quiet"]

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let provider = try CleanupCatalog.make(provider)
        let providerId = provider?.id ?? "rules"
        var result = CleanupPassResult(provider: providerId, source: source, build: ResultFiles.buildConfiguration)
        let out = paths.resultsURL.appendingPathComponent("cleanup-\(ResultFiles.safeName(providerId))-\(ResultFiles.safeName(source))\(smartFormatting ? "-formatting" : "").json")
        if smartFormatting { result.source += " (Smart Formatting on)" }

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
                let o = await runner.run(text, request: CleanupRequest(level: level, smartFormatting: smartFormatting))
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
            let o = await runner.run(text, request: CleanupRequest(level: .light, smartFormatting: smartFormatting))
            result.runs.append(.init(id: clip.id, rulesMs: o.rulesMs, llmMs: o.llmMs, totalMs: o.rulesMs + (o.llmMs ?? 0), fallback: o.fallback?.rawValue))
            i += 1
        }
        result.peakFootprint = ProcessMemory.snapshot()?.peakFootprint
        await provider?.unload()
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
        // Half short, half long (the limit grows with length up to 1,250 ms).
        let long = Array(repeating: "so the plan for the launch is that we ship the beta on Friday and then collect feedback", count: 5).joined(separator: " and ")
        for i in 0..<trials {
            let start = Clock.now()
            let o = await runner.run(i % 2 == 0 ? "um let's meet at 3 at the cafe" : long, request: CleanupRequest())
            let ms = Clock.ms(since: start)
            times.append(ms)
            print("  trial \(i + 1): \(Format.ms(ms)) · fallback \(o.fallback?.rawValue ?? "none") · \(o.text.prefix(40))")
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

// MARK: - vocab-test

struct VocabTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vocab-test",
        abstract: "T4: dictionary terms passed to the engine. Transcribes the names and numbers clips with and without a dictionary of their terms and reports, per term, which runs got it right."
    )
    @OptionGroup var paths: CommonPaths
    @Option var engine: String = "parakeet-ultra"
    @Option(help: "Also run the rules (with the dictionary) and this cleanup provider with the vocabulary, and score the final text.")
    var pipeline: String?
    @Flag(help: "Bias the engine acoustically toward the terms (off in the app).") var boost = false

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let clips = corpus.clips.filter { ["names", "numbers"].contains($0.set) }
        // Terms: names and technical words (not numbers, URLs or plain words).
        let terms = Array(Set(clips.flatMap { $0.entities ?? [] }.filter { e in
            e.first?.isLetter == true && !e.contains("/") && !e.contains("@") && e.rangeOfCharacter(from: .decimalDigits) == nil
                && !["Friday", "Monday", "staging", "doesn't", "macOS 14"].contains(e)
        })).sorted()
        print("Dictionary (\(terms.count)): \(terms.joined(separator: ", "))")
        let engine = try EngineCatalog.make(engine)
        try await engine.load()
        var runner: CleanupRunner?
        if let pipeline {
            let provider = try CleanupCatalog.make(pipeline)
            try await provider?.load()
            runner = CleanupRunner(rules: RulesCleaner(dictionary: terms.map { DictionaryEntry(term: $0, replacement: $0) }), provider: provider)
        }
        var rows: [(term: String, clip: String, bare: Bool, biased: Bool, bareText: String, biasedText: String)] = []
        var bareMs: [Double] = [], biasedMs: [Double] = []
        for clip in clips {
            guard let samples = try? WAV.read(Corpus.audioURL(clip, in: paths.corpusURL)) else { continue }
            var t = Clock.now()
            let bare = try await engine.transcribe(samples, options: TranscribeOptions(language: "en"))
            bareMs.append(Clock.ms(since: t))
            t = Clock.now()
            var biased = try await engine.transcribe(samples, options: TranscribeOptions(language: "en", vocabulary: terms, boost: boost))
            biasedMs.append(Clock.ms(since: t))
            if let runner {
                biased = await runner.run(biased, request: CleanupRequest(level: .light, vocabulary: terms)).text
            }
            for term in (clip.entities ?? []) where terms.contains(term) {
                rows.append((term, clip.id, CorpusChecks.entityPresent(bare, term), CorpusChecks.entityPresent(biased, term), bare, biased))
            }
        }
        let missedBare = rows.filter { !$0.bare }
        let fixed = missedBare.filter(\.biased)
        let broke = rows.filter { $0.bare && !$0.biased }
        print("\nTerm occurrences: \(rows.count). Bare engine right: \(rows.count - missedBare.count). With dictionary right: \(rows.filter(\.biased).count).")
        print("Missed by the bare engine: \(missedBare.count); recognized with the dictionary: \(fixed.count) of them (target 8 of 10).")
        print("Broken by the dictionary: \(broke.count)")
        for r in missedBare { print("  \(r.biased ? "✓" : "✗") \(r.term) [\(r.clip)]  bare: \(r.bareText)  →  biased: \(r.biasedText)") }
        for r in broke { print("  ! \(r.term) [\(r.clip)] broken: \(r.biasedText)") }
        print(String(format: "\nTranscription p50: bare %@, with dictionary %@ (first biased run includes loading the CTC model)",
                     Stats.percentile(bareMs, 50).map(Format.ms) ?? "-", Stats.percentile(Array(biasedMs.dropFirst()), 50).map(Format.ms) ?? "-"))
        let summary: [String: Double] = ["occurrences": Double(rows.count), "missedBare": Double(missedBare.count), "fixed": Double(fixed.count), "broken": Double(broke.count),
                                         "bareP50": Stats.percentile(bareMs, 50) ?? 0, "biasedP50": Stats.percentile(Array(biasedMs.dropFirst()), 50) ?? 0]
        try ResultFiles.write(summary, to: paths.resultsURL.appendingPathComponent("vocab-test-\(ResultFiles.safeName(engine.id)).json"))
    }
}

// MARK: - vocab-false-test

struct VocabFalseTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vocab-false-test",
        abstract: "T4 false insertions: transcribes every clip (and system-voice phrases) with a dictionary and counts dictionary words that appear where nobody said them, and words the dictionary changed in clips that contain none of its terms."
    )
    @OptionGroup var paths: CommonPaths
    @Option var engine: String = "parakeet-ultra"
    @Flag(help: "Print every changed clip.") var verbose = false
    @Option(help: "Use only these entries instead of the corpus names: \"Term=alias|alias,Term2\".") var terms: String?

    static let phrases = [
        "The quick brown fox jumps over the lazy dog.",
        "Please add my quality signature.",
        "Um, so I think we should, uh, move the launch to Friday.",
        "My three goals for today are, first, ship the app, second, write the docs, and third, take a break.",
        "Let's grab coffee after the meeting.",
        "Can you send me the slides before the three pm sync?",
        "Remind me to water the plants when I get home tonight.",
        "I think the new design looks a lot cleaner than the old one.",
    ]

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let names = Array(Set(corpus.clips.filter { ["names", "numbers"].contains($0.set) }.flatMap { $0.entities ?? [] }.filter { e in
            e.first?.isLetter == true && !e.contains("/") && !e.contains("@") && e.rangeOfCharacter(from: .decimalDigits) == nil
                && !["Friday", "Monday", "staging", "doesn't", "macOS 14"].contains(e)
        })).sorted()
        var aliases: [String: [String]] = ["Murmurly": ["marmalade"], "Siobhan": ["Chivan", "Shivon"]]
        var terms = names + aliases.keys.filter { !names.contains($0) }.sorted()
        if let custom = self.terms {
            aliases = [:]
            terms = custom.split(separator: ",").map { entry in
                let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { aliases[parts[0]] = parts[1].split(separator: "|").map(String.init) }
                return parts[0]
            }
        }
        print("Dictionary (\(terms.count)): \(terms.joined(separator: ", "))")

        var clips: [(id: String, reference: String, samples: [Float])] = []
        for clip in corpus.clips where !clip.isSilence {
            if let samples = try? WAV.read(Corpus.audioURL(clip, in: paths.corpusURL)), !samples.isEmpty {
                clips.append((clip.id, clip.reference, samples))
            }
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-vocab-false")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for (i, phrase) in Self.phrases.enumerated() {
            let url = tmp.appendingPathComponent("say-\(i).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEI16@16000", phrase]
            try say.run()
            say.waitUntilExit()
            let pad = [Float](repeating: 0, count: 8_000)
            if let samples = try? WAV.read(url) { clips.append(("say-\(i)", phrase, pad + samples + pad)) }
        }

        let engine = try EngineCatalog.make(engine)
        try await engine.load()
        var mappings: [DictionaryEntry] = []
        for term in terms {
            mappings.append(DictionaryEntry(term: term, replacement: term))
            for alias in aliases[term] ?? [] { mappings.append(DictionaryEntry(term: alias, replacement: term)) }
        }
        let plain = RulesCleaner(), ruled = RulesCleaner(dictionary: mappings)
        struct Tally { var falseInsertions = 0, changedClean = 0, fixed = 0, broken = 0 }
        let configs = ["boost", "rules", "boost+rules"]
        var tallies = Dictionary(uniqueKeysWithValues: configs.map { ($0, Tally()) })
        var cleanClips = 0, termClips = 0
        for clip in clips {
            let bare = try await engine.transcribe(clip.samples, options: TranscribeOptions(language: "en"))
            let boosted = try await engine.transcribe(clip.samples, options: TranscribeOptions(language: "en", vocabulary: terms, aliases: aliases, boost: true))
            let plainBare = plain.apply(bare).restoredText
            let outputs: [String: (base: String, out: String)] = [
                "boost": (bare, boosted),
                "rules": (plainBare, ruled.apply(bare).restoredText),
                "boost+rules": (plainBare, ruled.apply(boosted).restoredText),
            ]
            let said = terms.filter { CorpusChecks.contains(clip.reference, $0) || (aliases[$0] ?? []).contains { CorpusChecks.contains(clip.reference, $0) } }
            if said.isEmpty { cleanClips += 1 } else { termClips += 1 }
            for config in configs {
                let (base, out) = outputs[config]!
                let inserted = terms.filter { CorpusChecks.contains(out, $0) && !CorpusChecks.contains(base, $0) && !said.contains($0) }
                let changed = TextMetrics.normalizedWords(base) != TextMetrics.normalizedWords(out)
                tallies[config]!.falseInsertions += inserted.count
                if said.isEmpty, changed { tallies[config]!.changedClean += 1 }
                for term in said {
                    let b = CorpusChecks.contains(base, term), v = CorpusChecks.contains(out, term)
                    if !b && v { tallies[config]!.fixed += 1 }
                    if b && !v { tallies[config]!.broken += 1 }
                }
                if (changed && (said.isEmpty || verbose)) || !inserted.isEmpty {
                    print("\(inserted.isEmpty ? "~" : "!") \(config) [\(clip.id)] \(base)\n      → \(out)")
                }
            }
        }
        print("\nClips: \(clips.count) (\(cleanClips) with no dictionary word said, \(termClips) with one)")
        var summary: [String: Double] = ["clips": Double(clips.count)]
        for config in configs {
            let t = tallies[config]!
            print("\(config.padding(toLength: 12, withPad: " ", startingAt: 0)) false insertions \(t.falseInsertions), clean clips changed \(t.changedClean), terms fixed \(t.fixed), terms broken \(t.broken)")
            summary["\(config).falseInsertions"] = Double(t.falseInsertions)
            summary["\(config).fixed"] = Double(t.fixed)
            summary["\(config).broken"] = Double(t.broken)
        }
        try ResultFiles.write(summary, to: paths.resultsURL.appendingPathComponent("vocab-false-test-\(ResultFiles.safeName(engine.id)).json"))
    }
}

// MARK: - style-test

struct StyleTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "style-test",
        abstract: "S4 gate: cleans a few corpus sentences with the real model, applies every style offered in each category, and checks each style's mark (Formal. punctuated, Casual no final period, very casual no capitals at sentence starts, Excited! an exclamation)."
    )
    @OptionGroup var paths: CommonPaths
    @Option var provider: String = "mlx:qwen3.5-4b"

    /// A sample app per category, to show the category map at work.
    static let apps: [(AppCategory, String, URL?)] = [
        (.personal, "com.apple.MobileSMS", nil), (.work, "com.tinyspeck.slackmacgap", nil),
        (.email, "com.google.Chrome", URL(string: "https://mail.google.com/mail/u/0/")), (.other, "com.apple.TextEdit", nil),
    ]

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let sentences = ["plain-02", "plain-07", "plain-13", "levels-06", "levels-19"].compactMap { id in corpus.clips.first { $0.id == id }?.reference }
        let provider = try CleanupCatalog.make(provider)
        try await provider?.load()
        let runner = CleanupRunner(provider: provider, timeLimit: .seconds(3))
        var cleaned: [String] = []
        for sentence in sentences { cleaned.append(await runner.run(sentence, request: CleanupRequest()).text) }
        var passed = 0, total = 0
        for (category, bundle, url) in Self.apps {
            let found = AppCategory.of(bundleId: bundle, url: url)
            print("\n## \(category.rawValue) (\(url?.host ?? bundle) → \(found.rawValue))")
            total += 1
            if found == category { passed += 1 } else { print("  ✗ category map") }
            for style in category.styles {
                for text in cleaned {
                    let out = style.apply(to: text)
                    let ok: Bool = switch style {
                    case .formal: out == text
                    case .casual: !out.hasSuffix(".") && out.first?.isUppercase == true
                    case .veryCasual: !out.hasSuffix(".") && out.first?.isUppercase != true
                    case .excited: out.hasSuffix("!") || out.hasSuffix("?")
                    }
                    total += 1
                    if ok { passed += 1 }
                    print("  \(ok ? "✓" : "✗") \(style.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(out)")
                }
            }
        }
        print("\nStyle checks: \(passed)/\(total) \(passed == total ? "PASS" : "FAIL")")
        try ResultFiles.write(["passed": Double(passed), "total": Double(total)], to: paths.resultsURL.appendingPathComponent("style-test.json"))
        await provider?.unload()
    }
}

// MARK: - long-test

struct LongTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "long-test",
        abstract: "Cleanup on long dictations: joins three consecutive transcripts (60–80 words, like a 20 s dictation) and times each provider against the 800 ms limit."
    )
    @OptionGroup var paths: CommonPaths
    @Option var source: String = "parakeet-ultra"
    @Option(help: "Comma-separated cleanup providers.")
    var providers: String = "mlx:qwen3.5-4b,mlx:qwen3-4b-2507,mlx:qwen3-4b-2507+draft,mlx:smollm3-3b"

    func run() async throws {
        guard let engine = ResultFiles.read(EnginePassResult.self, from: paths.resultsURL.appendingPathComponent("engine-\(ResultFiles.safeName(source)).json")) else {
            throw ValidationError("Run the engine pass for \(source) first.")
        }
        let texts = engine.clips.filter { ["levels", "plain"].contains($0.set) }.compactMap(\.text)
        var inputs: [String] = []
        var i = 0
        while i + 2 < texts.count { inputs.append(texts[i...(i + 2)].joined(separator: " ")); i += 3 }
        let words = inputs.map { $0.split(separator: " ").count }
        print("\(inputs.count) long inputs, \(words.min() ?? 0)–\(words.max() ?? 0) words")
        for id in providers.split(separator: ",").map(String.init) {
            guard let provider = try CleanupCatalog.make(id) else { continue }
            try await provider.load()
            let runner = CleanupRunner(provider: provider)
            var ms: [Double] = [], timeouts = 0, guards = 0
            for input in inputs {
                let o = await runner.run(input, request: CleanupRequest(level: .light))
                ms.append(o.llmMs ?? 0)
                if o.fallback == .timeout { timeouts += 1 }
                if o.fallback == .guardFlagged { guards += 1 }
            }
            // Also time without the limit, to see how long the model really needs.
            let unlimited = CleanupRunner(provider: provider, timeLimit: .seconds(10))
            var full: [Double] = []
            for input in inputs.prefix(10) { full.append(await unlimited.run(input, request: CleanupRequest(level: .light)).llmMs ?? 0) }
            print(String(format: "%-26@ p50 %@  p95 %@  over 800 ms %d/%d  guard %d  | unlimited p50 %@ max %@", id as NSString,
                         Format.ms(Stats.percentile(ms, 50) ?? 0), Format.ms(Stats.percentile(ms, 95) ?? 0), timeouts, inputs.count, guards,
                         Format.ms(Stats.percentile(full, 50) ?? 0), Format.ms(full.max() ?? 0)))
            await provider.unload()
        }
    }
}

// MARK: - guard-test

/// C5 gate: every injected change to a fact is blocked. Takes each corpus sentence through the rules
/// stage, uses that as an honest model output (must pass), then injects changes the model must never make.
struct GuardTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "guard-test", abstract: "Inject number, URL, email, name and negation changes into model output and check the guard blocks every one.")
    @OptionGroup var paths: CommonPaths

    func run() async throws {
        let corpus = try Corpus.load(from: paths.corpusURL)
        let rules = RulesCleaner()
        let guardChecker = GuardChecker()
        var falsePositives: [String] = []
        var results: [String: (blocked: Int, total: Int)] = [:]
        var misses: [String] = []
        func record(_ kind: String, _ input: String, _ output: String) {
            let blocked = !guardChecker.check(input: input, output: output).isEmpty
            results[kind, default: (0, 0)].total += 1
            if blocked { results[kind]!.blocked += 1 } else { misses.append("[\(kind)] \(input)  →  \(output)") }
        }
        let names = ["Jordan", "Taylor", "Elena", "Marcus", "Priya", "Sam"]
        for clip in corpus.clips where !clip.isSilence {
            let input = rules.apply(clip.reference).text
            if !guardChecker.check(input: input, output: input).isEmpty { falsePositives.append(input) }
            // Injected values never already appear in the sentence, so a change cannot happen to equal
            // the speaker's own correction ("at 2, actually 3" -> "at 3, actually 3" means the same).
            let present = Set(input.matches(of: /\d+/).compactMap { Int(input[$0.range]) })
            func freshNumber(_ n: Int) -> Int { var v = n + 7; while present.contains(v) { v += 7 }; return v }
            func appending(_ phrase: String) -> String {
                if let last = input.last, ".?!".contains(last) { return String(input.dropLast()) + phrase + String(last) }
                return input + phrase
            }
            // 1. Change each number (digits).
            for match in input.matches(of: /\d+/) {
                let n = Int(input[match.range]) ?? 0
                record("number changed", input, input.replacingCharacters(in: match.range, with: String(freshNumber(n))))
            }
            // 2. Add a number.
            record("number added", input, appending(" by \(freshNumber(4)) pm"))
            // 3. Change a URL or email.
            for url in GuardChecker.urlsForTesting(input) {
                record("url changed", input, input.replacingOccurrences(of: url, with: url.replacingOccurrences(of: ".", with: "-", options: [], range: url.range(of: "."))), )
            }
            // 4. Swap or add a name.
            let unused = names.filter { input.range(of: $0, options: .caseInsensitive) == nil }
            if let name = GuardChecker.namesForTesting(input).first, let original = input.range(of: name, options: .caseInsensitive), let other = unused.first {
                record("name swapped", input, input.replacingCharacters(in: original, with: other))
            }
            if let other = unused.last { record("name added", input, appending(" and \(other)")) }
            // 5. Drop a negation, or add one.
            if let neg = input.range(of: #"\b(not|never|don't|doesn't|can't|isn't|wasn't|won't)\b"#, options: [.regularExpression, .caseInsensitive]) {
                let word = input[neg].lowercased()
                let positive = ["not": "", "never": "always", "don't": "do", "doesn't": "does", "can't": "can", "isn't": "is", "wasn't": "was", "won't": "will"][word] ?? ""
                record("negation flipped", input, input.replacingCharacters(in: neg, with: positive).replacingOccurrences(of: "  ", with: " "))
            } else if let verb = input.range(of: #"\b(is|will|should|can|was)\b"#, options: .regularExpression) {
                record("negation added", input, input.replacingCharacters(in: verb, with: input[verb] + " not"))
            }
        }
        var total = (0, 0)
        for (kind, r) in results.sorted(by: { $0.key < $1.key }) {
            print(String(format: "%-18@ %3d / %3d blocked", kind as NSString, r.blocked, r.total))
            total.0 += r.blocked; total.1 += r.total
        }
        print("All injected changes: \(total.0) / \(total.1) blocked. Honest outputs wrongly blocked: \(falsePositives.count).")
        for m in misses.prefix(20) { print("  missed: \(m)") }
        for f in falsePositives.prefix(5) { print("  false positive: \(f)") }
        try ResultFiles.write(["blocked": Double(total.0), "total": Double(total.1), "falsePositives": Double(falsePositives.count)],
                              to: paths.resultsURL.appendingPathComponent("guard-test.json"))
    }
}

// MARK: - punctuation-test

/// C4: spoken punctuation and layout, 10 synthetic-voice clips per command, through the engine and the
/// rules stage (the model is not needed; rules own these).
struct PunctuationTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "punctuation-test", abstract: "C4: say 'comma', 'question mark', 'new line', 'new paragraph' in 10 synthetic clips each and check the marks appear.")
    @OptionGroup var paths: CommonPaths
    @Option var engine: String = "parakeet-ultra"

    static let sentences: [(command: String, spoken: String, mark: String)] = {
        let comma = ["send it to Sam comma Priya and Marcus", "first the docs comma then the code", "yes comma I can do that", "on Monday comma we ship", "well comma that changes things",
                     "after lunch comma call me", "if it rains comma we stay in", "honestly comma it's fine", "red comma green and blue", "today comma not tomorrow"]
        let question = ["can you send the report question mark", "is the build green question mark", "what time is the meeting question mark", "did Sam reply question mark", "are we still on for Friday question mark",
                        "who owns this ticket question mark", "where should we meet question mark", "how long will it take question mark", "should I ship it question mark", "why did the test fail question mark"]
        let newLine = ["dear Sam new line thanks for the notes", "item one new line item two", "hello new line see you soon", "best new line Priya", "line one new line line two",
                       "todo new line buy milk", "regards new line Marcus", "subject new line the launch", "first new line second", "hi team new line quick update"]
        let paragraph = ["that covers the plan new paragraph next the budget", "thanks again new paragraph best wishes", "the release is ready new paragraph please test it", "intro done new paragraph now the details", "we agreed new paragraph next steps follow",
                         "summary first new paragraph then the notes", "part one ends new paragraph part two begins", "that is all new paragraph cheers", "context first new paragraph the ask", "background done new paragraph the proposal"]
        return comma.map { ("comma", $0, ",") } + question.map { ("question mark", $0, "?") } + newLine.map { ("new line", $0, "\n") } + paragraph.map { ("new paragraph", $0, "\n\n") }
    }()

    func run() async throws {
        let engine = try EngineCatalog.make(engine)
        try await engine.load()
        let rules = RulesCleaner()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-punct")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let voices = ["Samantha", "Daniel", "Karen", "Moira", "Tessa"]
        var passed: [String: Int] = [:], counts: [String: Int] = [:]
        for (i, s) in Self.sentences.enumerated() {
            let aiff = dir.appendingPathComponent("\(i).aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voices[i % voices.count], "-o", aiff.path, s.spoken]
            try say.run(); say.waitUntilExit()
            let samples = try WAV.read(aiff)
            let raw = try await engine.transcribe(samples, options: TranscribeOptions(language: "en"))
            let out = rules.apply(raw).text
            let ok: Bool
            switch s.mark {
            case "\n\n": ok = out.contains("\n\n")
            case "\n": ok = out.contains("\n") && !out.contains("\n\n")
            default: ok = out.contains(s.mark) && !out.lowercased().contains(s.command)
            }
            counts[s.command, default: 0] += 1
            if ok { passed[s.command, default: 0] += 1 } else { print("  ✗ [\(s.command)] heard: \(raw.debugDescription) → \(out.debugDescription)") }
        }
        for command in ["comma", "question mark", "new line", "new paragraph"] {
            print("\(command): \(passed[command] ?? 0) / \(counts[command] ?? 0)")
        }
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
