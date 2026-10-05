import SwiftUI

// Motion tokens (UI_REDESIGN.md §6.1). All assumed until tuned against recordings with the slow-motion
// time scale. Reduce Motion (§6.2) turns springs into short fades and drops scale and position changes.

public struct SpringToken: Sendable {
    public let response: Double
    public let damping: Double
}

public enum MotionTokens {
    public static let barAppear = SpringToken(response: 0.30, damping: 0.78) // source: assumed // MEASURE
    public static let barAppearScale: CGFloat = 0.86 // source: assumed // MEASURE
    public static let barDisappear: Double = 0.140 // source: assumed // MEASURE
    public static let barExpand = SpringToken(response: 0.34, damping: 0.82) // source: assumed // MEASURE
    public static let barButtonsIn: Double = 0.120 // source: assumed // MEASURE
    public static let barButtonsAt: Double = 0.8 // source: assumed // MEASURE
    public static let waveAttack: Double = 0.045 // source: assumed // MEASURE
    public static let waveRelease: Double = 0.140 // source: assumed // MEASURE
    public static let processingPeriod: Double = 1.1 // source: assumed // MEASURE
    public static let processingPeriodReduced: Double = 1.6 // source: assumed // MEASURE
    public static let insertedCheck: Double = 0.220 // source: assumed // MEASURE
    public static let insertedHold: Double = 0.600 // source: assumed // MEASURE
    public static let toastIn: Double = 0.200 // source: assumed // MEASURE
    public static let toastRise: CGFloat = 12 // source: assumed // MEASURE
    public static let toastOut: Double = 0.140 // source: assumed // MEASURE
    public static let tooltipDelay: Double = 0.400 // source: assumed // MEASURE
    public static let tooltipOut: Double = 0.100 // source: assumed // MEASURE
    public static let pageSwitch: Double = 0.160 // source: assumed // MEASURE
    public static let hover: Double = 0.100 // source: assumed // MEASURE
    public static let press: Double = 0.080 // source: assumed // MEASURE
    public static let toggleKnob = SpringToken(response: 0.22, damping: 0.80) // source: assumed // MEASURE
    public static let tabsSelect = SpringToken(response: 0.28, damping: 0.85) // source: assumed // MEASURE
    public static let sidebarCollapse: Double = 0.160 // source: assumed // MEASURE
    public static let reducedFade: Double = 0.120 // source: assumed // MEASURE
    public static let rowActionsFade: Double = 0.100 // source: assumed // MEASURE
}

/// Animations that honor Reduce Motion and the debug time scale.
public struct Motion: Sendable {
    public var reduce: Bool
    public var timeScale: Double

    public init(reduce: Bool, timeScale: Double = 1) {
        self.reduce = reduce
        self.timeScale = max(0.05, timeScale)
    }

    /// A spring, or a short fade under Reduce Motion.
    public func spring(_ token: SpringToken) -> Animation {
        reduce ? .easeInOut(duration: MotionTokens.reducedFade / timeScale)
            : .spring(response: token.response / timeScale, dampingFraction: token.damping)
    }

    public func easeOut(_ duration: Double) -> Animation {
        .easeOut(duration: (reduce ? min(duration, MotionTokens.reducedFade) : duration) / timeScale)
    }

    public func easeIn(_ duration: Double) -> Animation {
        .easeIn(duration: (reduce ? min(duration, MotionTokens.reducedFade) : duration) / timeScale)
    }

    public func easeInOut(_ duration: Double) -> Animation {
        .easeInOut(duration: (reduce ? min(duration, MotionTokens.reducedFade) : duration) / timeScale)
    }

    /// A scale to apply, or 1 under Reduce Motion.
    public func scale(_ value: CGFloat) -> CGFloat { reduce ? 1 : value }

    /// An offset to apply, or 0 under Reduce Motion.
    public func offset(_ value: CGFloat) -> CGFloat { reduce ? 0 : value }

    /// A duration in seconds, scaled for slow motion.
    public func seconds(_ value: Double) -> Double { value / timeScale }
}
