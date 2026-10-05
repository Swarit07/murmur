import Foundation

/// The latest microphone level. The audio thread writes it on every buffer; the UI reads it once per
/// displayed frame. Nothing is dispatched to the main thread per buffer (UI_REDESIGN.md U3).
public final class MicLevelSource: @unchecked Sendable {
    private let lock = NSLock()
    private var dbfs: Float = -160
    private var updated: TimeInterval = -.infinity

    public init() {}

    /// Called from the audio thread: one lock, two stores.
    public func write(_ level: Float) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            dbfs = level
            updated = now
        }
    }

    /// The level in dBFS, or nil when no buffer has arrived for `staleAfter` seconds (not recording).
    public func read(staleAfter: TimeInterval = 0.25) -> Float? {
        let (level, at) = lock.withLock { (dbfs, updated) }
        return ProcessInfo.processInfo.systemUptime - at <= staleAfter ? level : nil
    }
}
