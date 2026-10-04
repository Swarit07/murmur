import Foundation
import WhisperKit

/// OpenAI Whisper converted to CoreML by Argmax (WhisperKit).
public actor WhisperKitEngine: SpeechEngine {
    public nonisolated let id: String
    public nonisolated let isLocal = true
    let model: String
    var pipe: WhisperKit?

    public init(model: String) {
        self.model = model
        self.id = model.hasSuffix("_turbo") ? "whisper-turbo" : "whisper-\(model)"
    }

    public func load() async throws {
        guard pipe == nil else { return }
        let config = WhisperKitConfig(model: model, verbose: false, logLevel: .error, prewarm: true, load: true, download: true)
        pipe = try await WhisperKit(config)
        _ = try await transcribe([Float](repeating: 0, count: 16_000), options: TranscribeOptions())
    }

    public func transcribe(_ samples: [Float], options: TranscribeOptions) async throws -> String {
        guard let pipe else { throw SpeechError.notLoaded }
        var decode = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: options.language,
            temperature: 0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: options.language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        if !options.vocabulary.isEmpty, let tokenizer = pipe.tokenizer {
            let prompt = " " + options.vocabulary.joined(separator: ", ")
            decode.promptTokens = tokenizer.encode(text: prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: decode)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func unload() async {
        await pipe?.unloadModels()
        pipe = nil
    }
}
