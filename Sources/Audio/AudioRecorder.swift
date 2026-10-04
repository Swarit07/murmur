@preconcurrency import AVFoundation
import Core
import Foundation

public enum MicrophonePermission {
    public static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    /// Asks once if undetermined. Returns whether recording is allowed.
    public static func ensure() async -> Bool {
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

/// Captures the default input device, converts to 16 kHz mono Float32 as buffers arrive, and reports
/// levels for a waveform. The engine is prepared up front so `start` is as fast as the device allows.
public final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var resampler: Resampler?
    private var startedAt: UInt64 = 0
    private var firstBufferAt: UInt64?
    private var running = false
    private let onLevel: (@Sendable (Float) -> Void)?

    public init(onLevel: (@Sendable (Float) -> Void)? = nil) {
        self.onLevel = onLevel
    }

    public var deviceName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
    }

    /// Milliseconds from `start()` to the first audio buffer, once one has arrived.
    public var firstAudioMs: Double? {
        lock.withLock { firstBufferAt.map { Clock.ms(from: startedAt, to: $0) } }
    }

    public var isRunning: Bool { lock.withLock { running } }

    public func prepare() {
        _ = engine.inputNode.outputFormat(forBus: 0)
        engine.prepare()
    }

    public func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.noInputDevice }
        let resampler = try Resampler(from: format)
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(16_000 * 30)
            self.resampler = resampler
            startedAt = Clock.now()
            firstBufferAt = nil
            running = true
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.withLock { running = false }
            throw AudioError.engine(error.localizedDescription)
        }
    }

    /// Stops capture and returns everything recorded since `start`.
    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock {
            running = false
            return samples
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        let now = Clock.now()
        guard let resampler = lock.withLock({ () -> Resampler? in
            if firstBufferAt == nil { firstBufferAt = now }
            return running ? self.resampler : nil
        }) else { return }
        guard let converted = try? resampler.convert(buffer, endOfStream: false), !converted.isEmpty else { return }
        lock.withLock { samples.append(contentsOf: converted) }
        onLevel?(Levels.dbfs(converted[...]))
    }
}
