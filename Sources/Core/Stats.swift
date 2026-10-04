import Foundation

public enum Stats {
    /// Nearest-rank percentile. `p` is in 0...100. Returns nil for an empty sample.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// Process memory from `proc_pid_rusage`. CoreML work on the Neural Engine runs partly in system
/// daemons and is not counted here.
public enum ProcessMemory {
    public struct Snapshot: Sendable, Codable {
        public var footprint: UInt64
        public var peakFootprint: UInt64
    }

    public static func snapshot() -> Snapshot? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return Snapshot(footprint: info.ri_phys_footprint, peakFootprint: info.ri_lifetime_max_phys_footprint)
    }
}
