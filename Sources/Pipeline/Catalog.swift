import Cleanup
import Foundation
#if canImport(CleanupMLX)
import CleanupMLX
#endif

/// Builds cleanup providers from the short ids used by the CLI and the bench.
public enum CleanupCatalog {
    public static let mlxNames = ["qwen3.5-0.8b", "qwen3.5-2b", "qwen3.5-4b", "qwen3-4b-2507"]
    public static let ids: [String] = ["rules", "apple-foundation", "groq"] + mlxNames.map { "mlx:\($0)" }

    public static var mlxAvailable: Bool {
        #if canImport(CleanupMLX)
        true
        #else
        false
        #endif
    }

    /// `nil` means rules only.
    public static func make(_ id: String) throws -> (any CleanupProvider)? {
        switch id {
        case "rules", "none": return nil
        case "apple-foundation", "apple": return AppleFoundationCleanupProvider()
        case "groq": return GroqCleanupProvider()
        case "stalled": return StalledCleanupProvider()
        default:
            if id.hasPrefix("groq:") { return GroqCleanupProvider(model: String(id.dropFirst(5))) }
            let name = id.hasPrefix("mlx:") ? String(id.dropFirst(4)) : id
            if id.hasPrefix("mlx:") || mlxNames.contains(name) {
                #if canImport(CleanupMLX)
                return MLXCleanupProvider(name: name)
                #else
                throw CleanupError.unavailable("this build has no MLX (built with MURMUR_NO_MLX=1)")
                #endif
            }
            throw CleanupError.unavailable("unknown cleanup provider \(id). Known: \(ids.joined(separator: ", "))")
        }
    }
}
