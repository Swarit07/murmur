@preconcurrency import AVFoundation
import Foundation

public enum AudioFormat {
    public static let sampleRate: Double = 16_000

    /// 16 kHz mono Float32, the format every engine takes.
    public static let mono16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
}

public enum AudioError: Error, CustomStringConvertible {
    case noInputDevice
    case converterFailed
    case microphoneDenied
    case engine(String)

    public var description: String {
        switch self {
        case .noInputDevice: "no microphone input device"
        case .converterFailed: "could not create an audio converter"
        case .microphoneDenied: "microphone access is denied"
        case .engine(let s): "audio engine: \(s)"
        }
    }
}

public enum WAV {
    /// Writes 16-bit PCM, 16 kHz mono.
    public static func write(_ samples: [Float], to url: URL, sampleRate: Double = AudioFormat.sampleRate) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw AudioError.converterFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }

    /// Reads any audio file AVFoundation understands and converts it to 16 kHz mono Float32.
    public static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        // A key tapped faster than the microphone starts gives an empty file. That is a valid clip
        // (it must insert nothing), not an error.
        guard file.length > 0 else { return [] }
        let inFormat = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioError.converterFailed
        }
        try file.read(into: input)
        return try Resampler(from: inFormat).convert(input)
    }
}

/// Converts arbitrary PCM buffers to 16 kHz mono Float32.
public final class Resampler: @unchecked Sendable {
    let converter: AVAudioConverter
    let inFormat: AVAudioFormat

    public init(from inFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inFormat, to: AudioFormat.mono16k) else { throw AudioError.converterFailed }
        // Microphones deliver one channel; for multichannel input take the first.
        if inFormat.channelCount > 1 {
            converter.channelMap = [0]
        }
        self.converter = converter
        self.inFormat = inFormat
    }

    public func convert(_ buffer: AVAudioPCMBuffer, endOfStream: Bool = true) throws -> [Float] {
        if buffer.format.sampleRate == AudioFormat.sampleRate, buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32, let data = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        let ratio = AudioFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: AudioFormat.mono16k, frameCapacity: capacity) else { throw AudioError.converterFailed }
        let source = SingleBuffer(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if let b = source.take() {
                inputStatus.pointee = .haveData
                return b
            }
            inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
            return nil
        }
        if status == .error { throw error ?? AudioError.converterFailed }
        guard let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    /// Resets converter state between independent clips.
    public func reset() { converter.reset() }
}

/// Hands one buffer to an AVAudioConverter input block, then reports no more data.
final class SingleBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
