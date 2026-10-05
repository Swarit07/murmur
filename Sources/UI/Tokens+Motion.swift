import SwiftUI

// Motion tokens (UI_REDESIGN.md v2 §6.1). Board values come from the boards and the motion reference
// (`Design/motion/murmur-motion.js`); assumed ones are tuned later with the slow-motion time scale.
// Reduce Motion (§6.3) turns springs into 120 ms fades and drops scale and position changes.

public struct SpringToken: Sendable {
    public let response: Double
    public let damping: Double
}

public enum MotionTokens {
    /// The Flow Bar's width: one spring, about 240 ms to settle.
    public static let barWidth = SpringToken(response: 0.24, damping: 0.82) // source: board
    /// The idle pill fades to `OpacityTokens.idleFaded` after this long, over `barIdleFade`.
    public static let barIdleFadeDelay: Double = 10 // source: board
    public static let barIdleFade: Double = 0.400 // source: board
    public static let tooltipDelay: Double = 0.400 // source: board
    public static let tooltipOut: Double = 0.100 // source: board
    /// The hands-free timer appears after this long.
    public static let barTimerDelay: Double = 3 // source: board
    /// At five minutes of hands-free, the pill nudges once.
    public static let barNudgeAt: Double = 300 // source: assumed // MEASURE
    public static let barNudgeScale: CGFloat = 1.04 // source: assumed // MEASURE
    public static let barNudge: Double = 0.300 // source: assumed // MEASURE
    /// One-pole smoothing time constants on the mic level (0.30 and 0.09 per frame at 60 fps).
    public static let waveAttack: Double = 0.050 // source: board
    public static let waveRelease: Double = 0.180 // source: board
    /// The waveform's lobes travel at this phase speed, radians per second.
    public static let waveTravel: Double = 2.4 // source: board
    /// Processing dots: one ripple period, the phase step between dots, lift and opacity range.
    public static let dotsPeriod: Double = 1.1 // source: board
    public static let dotsPhaseStep: Double = 0.62 // source: board
    public static let dotsLift: Double = 0.9 // source: board (times the dot size)
    public static let dotsOpacityLow: Double = 0.4 // source: board
    public static let dotsPulseReduced: Double = 1.6 // source: board
    public static let insertedCheck: Double = 0.180 // source: board
    public static let insertedHold: Double = 1.200 // source: board
    public static let toastPaste: Double = 4 // source: board
    public static let toastRise: CGFloat = 8 // source: board
    public static let toastIn: Double = 0.200 // source: assumed // MEASURE
    public static let toastOut: Double = 0.140 // source: assumed // MEASURE
    public static let toastCancel: Double = 5 // source: board
    public static let alertSticky: Double = 8 // source: board
    public static let alertShake: CGFloat = 2 // source: board
    public static let alertShakeCycles: Double = 3 // source: board
    public static let alertShakeDuration: Double = 0.240 // source: assumed // MEASURE
    public static let onboardingStep: Double = 0.220 // source: assumed // MEASURE
    public static let onboardingDrift: CGFloat = 12 // source: board
    public static let pageSwitch: Double = 0.160 // source: assumed // MEASURE
    public static let pageRise: CGFloat = 6 // source: assumed // MEASURE
    public static let hover: Double = 0.100 // source: assumed // MEASURE
    public static let press: Double = 0.080 // source: board
    public static let pressDrop: CGFloat = 1 // source: board
    public static let toggleKnob = SpringToken(response: 0.22, damping: 0.80) // source: assumed // MEASURE
    public static let segmentedSelect = SpringToken(response: 0.28, damping: 0.85) // source: assumed // MEASURE
    public static let rowActionsFade: Double = 0.100 // source: board
    /// What every spring and longer fade becomes under Reduce Motion.
    public static let reducedFade: Double = 0.120 // source: board
}

/// The live waveform's shape (§6.2), ported from `drawWave` in `Design/motion/murmur-motion.js`: the
/// logo's tail, a filled shape between a top and a bottom contour that tapers to a hairline.
public enum WaveTokens {
    /// Half the silence hairline (0.7 pt total).
    public static let hairline: Double = 0.35 // source: board
    /// Kept clear between the tallest lobe and the frame edge.
    public static let edgeMargin: Double = 0.75 // source: board
    /// One lobe per this many points of width, and never fewer than `minimumLobes`.
    public static let lobeWidth: Double = 15 // source: board
    public static let minimumLobes: Double = 4 // source: board
    /// Contour samples per point of width, and never fewer than `minimumSamples`.
    public static let samplesPerPoint: Double = 1.5 // source: board
    public static let minimumSamples: Double = 48 // source: board
    /// The envelope rises over the first 14%, holds to 42%, then falls with this exponent.
    public static let rise: Double = 0.14 // source: board
    public static let fallFrom: Double = 0.42 // source: board
    public static let fallExponent: Double = 1.35 // source: board
    public static let lobeExponent: Double = 1.2 // source: board
    /// The bottom contour is this share of the top (top 100%, bottom 82%).
    public static let bottomShare: Double = 0.82 // source: board
    /// Each lobe's height drifts between `lobeLow` and 1 at a speed of `lobeSpeed` + r × `lobeSpeedSpread`.
    public static let lobeLow: Double = 0.3 // source: board
    public static let lobeSpeed: Double = 1.6 // source: board
    public static let lobeSpeedSpread: Double = 2.2 // source: board
    /// The smoothed mic level is multiplied by this, then capped at 1.
    public static let gain: Double = 2.1 // source: board
}

/// The processing dots, countdown ring and onboarding level meter (§6.2: `MurmurDots`, `MurmurRing`,
/// `MurmurLevels` in the motion reference).
public enum MeterTokens {
    /// The level meter's bars ramp in height with this exponent.
    public static let rampExponent: Double = 0.85 // source: board
    /// Unlit meter bars are ink at this opacity.
    public static let unlit: Double = 0.12 // source: board
    /// Meter smoothing toward a rising and a falling level, per frame at 60 fps.
    public static let attackPerFrame: Double = 0.35 // source: board
    public static let releasePerFrame: Double = 0.08 // source: board
    /// The countdown digit is this share of the ring's size.
    public static let ringDigitShare: Double = 0.42 // source: board
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
