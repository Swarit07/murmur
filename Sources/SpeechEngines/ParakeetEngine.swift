import Audio
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT models converted to CoreML by FluidAudio, run on the Neural Engine.
public actor ParakeetEngine: SpeechEngine {
    public enum Version: String, Sendable {
        case v3, v2, ultra, phonon2

        var fluid: AsrModelVersion {
            switch self {
            case .v3: .v3
            case .v2: .v2
            case .ultra: .ultra
            case .phonon2: .phonon2
            }
        }
    }

    public nonisolated let id: String
    public nonisolated let isLocal = true
    let version: Version
    var manager: AsrManager?
    /// Dictionary biasing (T4): a separate 110M CTC encoder spots dictionary terms in the audio and
    /// rescores the TDT transcript. Loaded the first time a dictionary is in use.
    var ctcModels: CtcModels?
    var boosting: (key: String, session: VocabularyBoostingSession)?

    public init(version: Version) {
        self.version = version
        self.id = "parakeet-\(version.rawValue)"
    }

    public func load() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: version.fluid)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        // Warm-up pass so the first real clip does not pay for CoreML specialization.
        _ = try await transcribe([Float](repeating: 0, count: 16_000), options: TranscribeOptions())
    }

    public func transcribe(_ samples: [Float], options: TranscribeOptions) async throws -> String {
        guard let manager else { throw SpeechError.notLoaded }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // Parakeet needs at least one second of audio; pad short clips with silence.
        let padded = samples.count < 16_000 ? samples + [Float](repeating: 0, count: 16_000 - samples.count) : samples
        let result = try await manager.transcribe(padded, decoderState: &state)
        var text = result.text
        if !options.vocabulary.isEmpty, let timings = result.tokenTimings, !timings.isEmpty,
           let session = try? await boostingSession(options) {
            if let rescored = await session.rescore(text: text, tokenTimings: timings, audioSamples: padded), rescored.wasModified {
                text = rescored.text
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One boosting session per distinct dictionary; rebuilt when the dictionary changes.
    func boostingSession(_ options: TranscribeOptions) async throws -> VocabularyBoostingSession {
        let key = options.vocabulary.sorted().joined(separator: "\u{1F}") + "|" + options.aliases.keys.sorted().map { "\($0)=\(options.aliases[$0]!.joined(separator: ","))" }.joined(separator: ";")
        if let boosting, boosting.key == key { return boosting.session }
        if ctcModels == nil { ctcModels = try await CtcModels.downloadAndLoad() }
        let terms = options.vocabulary.map { term in
            CustomVocabularyTerm(text: term, aliases: options.aliases[term].flatMap { $0.isEmpty ? nil : $0 })
        }
        // Thresholds can be overridden for tuning sweeps (MURMUR_VOCAB_*); defaults are FluidAudio's.
        let env = ProcessInfo.processInfo.environment
        func value(_ name: String, _ fallback: Float) -> Float { env[name].flatMap(Float.init) ?? fallback }
        let context = CustomVocabularyContext(
            terms: terms,
            alpha: value("MURMUR_VOCAB_ALPHA", ContextBiasingConstants.defaultAlpha),
            minCtcScore: value("MURMUR_VOCAB_MINCTC", ContextBiasingConstants.defaultMinVocabCtcScore),
            minSimilarity: value("MURMUR_VOCAB_MINSIM", ContextBiasingConstants.defaultMinSimilarity),
            minCombinedConfidence: value("MURMUR_VOCAB_MINCONF", ContextBiasingConstants.defaultMinCombinedConfidence)
        )
        let session = try await VocabularyBoostingSession(vocabulary: context, ctcModels: ctcModels!)
        boosting = (key, session)
        return session
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
        boosting = nil
        ctcModels = nil
    }
}

/// Silero VAD from FluidAudio, as a second opinion to the energy gate.
public actor SileroSpeechGate: SpeechGate {
    public nonisolated let id = "silero"
    var vad: VadManager?
    let minVoicedChunks: Int

    public init(minVoicedChunks: Int = 1) {
        self.minVoicedChunks = minVoicedChunks
    }

    public func load() async throws {
        if vad == nil { vad = try await VadManager(config: VadConfig(defaultThreshold: 0.6)) }
    }

    public func hasSpeech(_ samples: [Float]) async -> Bool {
        guard Double(samples.count) / AudioFormat.sampleRate >= 0.3 else { return false }
        if vad == nil { try? await load() }
        guard let vad, let results = try? await vad.process(samples) else { return true }
        return results.filter(\.isVoiceActive).count >= minVoicedChunks
    }
}
