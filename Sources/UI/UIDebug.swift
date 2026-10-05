import AppKit
import SwiftUI

/// Debug-only overrides for checking the design (U0): appearance, Reduce Motion, a global animation
/// time scale for slow motion, and a text-size scale. Set from the token panel; nothing persists.
@MainActor
@Observable
public final class UIDebug {
    public static let shared = UIDebug()

    public enum AppearanceOverride: String, CaseIterable, Sendable {
        case system, light, dark
    }

    /// Forces light or dark for every Murmur window (the Flow Bar looks the same in both).
    public var appearance: AppearanceOverride = .system {
        didSet { AppearanceController.refresh() }
    }

    /// nil follows the system setting.
    public var reduceMotion: Bool?
    /// Multiplies every animation duration; 0.2 is slow motion.
    public var timeScale: Double = 1
    /// nil follows the Text size setting.
    public var textScale: Double?
    /// nil follows the system's Increase Contrast setting.
    public var increaseContrast: Bool?

    private init() {}
}
