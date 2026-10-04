@preconcurrency import AVFoundation
import Audio
import Foundation
import Speech

/// Apple's on-device SpeechAnalyzer with the SpeechTranscriber module (macOS 26 and later).
/// The model is an OS asset: it downloads once through the system and is shared by all apps.
public actor AppleSpeechEngine: SpeechEngine {
    public nonisolated let id = "apple-speech"
    public nonisolated let isLocal = true
    let locale: Locale
    var ready = false

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    public func load() async throws {
        guard #available(macOS 26.0, *) else { throw SpeechError.unavailable("needs macOS 26") }
        guard !ready else { return }
        guard SpeechTranscriber.isAvailable else { throw SpeechError.unavailable("SpeechTranscriber is not available on this Mac") }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechError.unavailable("locale \(locale.identifier) not supported")
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        ready = true
        _ = try await transcribe([Float](repeating: 0, count: 16_000), options: TranscribeOptions())
    }

    public func transcribe(_ samples: [Float], options: TranscribeOptions) async throws -> String {
        guard #available(macOS 26.0, *) else { throw SpeechError.unavailable("needs macOS 26") }
        guard ready else { throw SpeechError.notLoaded }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: options.language.map { Locale(identifier: $0) } ?? self.locale) ?? self.locale
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? AudioFormat.mono16k
        let buffer = try Self.buffer(samples, format: format)

        if !options.vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = options.vocabulary
            try await analyzer.setContext(context)
        }

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        try await analyzer.start(inputSequence: stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func unload() async {
        ready = false
    }

    /// Wraps samples in a buffer of the analyzer's preferred format.
    static func buffer(_ samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let source = AVAudioPCMBuffer(pcmFormat: AudioFormat.mono16k, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if format == AudioFormat.mono16k { return source }
        guard let converter = AVAudioConverter(from: AudioFormat.mono16k, to: format) else { throw SpeechError.unavailable("no converter to \(format)") }
        let ratio = format.sampleRate / AudioFormat.sampleRate
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * ratio + 1024))!
        let once = OneShot(source)
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if let b = once.take() { status.pointee = .haveData; return b }
            status.pointee = .endOfStream
            return nil
        }
        if let error { throw error }
        return out
    }
}

final class OneShot: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? { defer { buffer = nil }; return buffer }
}
