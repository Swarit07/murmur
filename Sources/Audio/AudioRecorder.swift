@preconcurrency import AVFoundation
import Core
import Foundation
import ObjCSupport

/// Runs an AVAudioEngine call, turning a raised Objective-C exception into a thrown error.
func catchingAudio(_ what: String, _ body: () -> Void) throws {
    var error: NSError?
    if !MurmurCatchException(body, &error) {
        throw AudioError.engine("\(what): \(error?.localizedDescription ?? "unknown")")
    }
}

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
    private var engine = AVAudioEngine()
    /// Core Audio UID of the input to use, or nil for the system default.
    private var deviceUID: String?
    private var needsRebuild = false
    private var configObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var resampler: Resampler?
    private var startedAt: UInt64 = 0
    private var firstBufferAt: UInt64?
    private var lastBufferAt: UInt64?
    private var running = false
    private let onLevel: (@Sendable (Float) -> Void)?

    public init(onLevel: (@Sendable (Float) -> Void)? = nil) {
        self.onLevel = onLevel
        observeConfiguration()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    public var deviceName: String {
        if let deviceUID, let device = AudioDevices.inputs().first(where: { $0.uid == deviceUID }) { return device.name }
        return AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
    }

    /// Throws the engine away so the next `start` builds a fresh one (D9 retry after a device problem).
    public func forceRebuild() {
        lock.withLock { needsRebuild = true }
    }

    /// Chooses the input device; nil follows the system default. Takes effect at the next `start`.
    public func setDevice(uid: String?) {
        lock.withLock {
            guard uid != deviceUID else { return }
            deviceUID = uid
            needsRebuild = true
        }
    }

    /// A device change or Bluetooth route switch reconfigures the engine; rebuild it before the next
    /// recording instead of failing (D9).
    private func observeConfiguration() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.lock.withLock { self?.needsRebuild = true }
        }
    }

    /// Replaces the engine after a device or route change. Never prepares an engine without its input
    /// node: AVAudioEngine raises on an empty graph. `start()` prepares after installing the tap.
    private func rebuildIfNeeded() {
        let (rebuild, uid) = lock.withLock { (needsRebuild, deviceUID) }
        guard rebuild else { return }
        engine.stop()
        engine = AVAudioEngine()
        observeConfiguration()
        let input = engine.inputNode
        if let uid, var id = AudioDevices.deviceID(forUID: uid), let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        lock.withLock { needsRebuild = false }
    }

    /// Milliseconds from `start()` to the first audio buffer, once one has arrived.
    public var firstAudioMs: Double? {
        lock.withLock { firstBufferAt.map { Clock.ms(from: startedAt, to: $0) } }
    }

    public var isRunning: Bool { lock.withLock { running } }

    /// When the newest audio buffer arrived (nil before the first). D7 stops a recording whose
    /// microphone has stopped sending audio.
    public var lastAudioAt: UInt64? { lock.withLock { lastBufferAt } }

    /// Touches the input so the first `start()` is faster. Failures surface at `start()` instead.
    public func prepare() {
        _ = engine.inputNode.outputFormat(forBus: 0)
    }

    public func start() throws {
        rebuildIfNeeded()
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
            lastBufferAt = nil
            running = true
        }
        do {
            try catchingAudio("install tap") {
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
                    self?.append(buffer)
                }
            }
            try catchingAudio("prepare") { self.engine.prepare() }
            var startError: Error?
            try catchingAudio("start") {
                do { try self.engine.start() } catch { startError = error }
            }
            if let startError { throw AudioError.engine(startError.localizedDescription) }
        } catch {
            try? catchingAudio("remove tap") { input.removeTap(onBus: 0) }
            lock.withLock {
                running = false
                needsRebuild = true
            }
            throw error
        }
    }

    /// Stops capture and returns everything recorded since `start`.
    public func stop() -> [Float] {
        try? catchingAudio("stop") {
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
        return lock.withLock {
            running = false
            return samples
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        let now = Clock.now()
        guard let resampler = lock.withLock({ () -> Resampler? in
            if firstBufferAt == nil { firstBufferAt = now }
            lastBufferAt = now
            return running ? self.resampler : nil
        }) else { return }
        guard let converted = try? resampler.convert(buffer, endOfStream: false), !converted.isEmpty else { return }
        lock.withLock { samples.append(contentsOf: converted) }
        onLevel?(Levels.dbfs(converted[...]))
    }
}
