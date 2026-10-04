import Audio
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT models converted to CoreML by FluidAudio, run on the Neural Engine.
public actor ParakeetEngine: SpeechEngine {
    public enum Version: String, Sendable {
        case v3, v2, ultra

        var fluid: AsrModelVersion {
            switch self {
            case .v3: .v3
            case .v2: .v2
            case .ultra: .ultra
            }
        }
    }

    public nonisolated let id: String
    public nonisolated let isLocal = true
    let version: Version
    var manager: AsrManager?

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
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
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
