import AppKit
import SwiftUI

/// The Flow Bar's live-tunable tokens (SPEC rule 5, UI_REDESIGN.md v2 §3.5, §5.1, §6). Defaults come
/// from the static tokens (`FlowGeometry`, `FlowBarColors`, `MotionTokens`, `WaveTokens`), so there is
/// one source of truth; the debug panel overrides them at runtime through `LiveTokens`. Colors are
/// `#RRGGBBAA` pairs picked by the **system** appearance (the bar ignores the Hub's Appearance setting).
public struct Tokens: Codable, Equatable, Sendable {
    /// Saved overrides laid over the current defaults, so a token added later keeps its default
    /// instead of making the whole saved set unreadable.
    public static func merged(over data: Data) -> Tokens? {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Tokens.defaults)) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new }) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: merged)
    }

    // MARK: Pill geometry (points)

    public var idleWidth: Double = FlowGeometry.idleSize.width
    public var idleHeight: Double = FlowGeometry.idleSize.height
    public var idleDashWidth: Double = FlowGeometry.idleDash.width
    public var idleDashHeight: Double = FlowGeometry.idleDash.height
    public var hoverWidth: Double = FlowGeometry.hoverSize.width
    public var hoverHeight: Double = FlowGeometry.hoverSize.height
    /// Every active state shares one height (listening, processing, inserted, toasts).
    public var activeHeight: Double = FlowGeometry.activeHeight
    public var holdPadding: Double = FlowGeometry.holdPaddingH
    public var handsFreePadding: Double = FlowGeometry.handsFreePaddingH
    public var contentGap: Double = FlowGeometry.contentGap
    public var waveHoldWidth: Double = FlowGeometry.waveHold.width
    public var waveHandsFreeWidth: Double = FlowGeometry.waveHandsFree.width
    public var waveHeight: Double = FlowGeometry.waveHold.height
    public var liveDot: Double = FlowGeometry.liveDot
    public var roundButton: Double = FlowGeometry.roundButton
    public var processingWidth: Double = FlowGeometry.processingSize.width
    public var dotSize: Double = FlowGeometry.dot
    public var dotGap: Double = FlowGeometry.dotGap
    public var cardRadius: Double = FlowGeometry.cardRadius
    public var ringWidth: Double = FlowGeometry.ring1pt
    public var tooltipHeight: Double = FlowGeometry.tooltipHeight
    public var tooltipGap: Double = FlowGeometry.tooltipGap
    public var noAudioWidth: Double = FlowGeometry.noAudioWidth
    /// Gap between the bar and the Dock (or the bottom of the visible frame).
    public var bottomMargin: Double = FlowGeometry.bottomMargin
    /// Extra lift in a full-screen app's Space, where the Dock is hidden.
    public var fullScreenLift: Double = 6 // source: assumed // MEASURE
    /// Offset when the Dock sits on the left or right edge.
    public var dockSideOffset: Double = 0 // source: assumed // MEASURE

    // MARK: Waveform

    /// Level (dBFS) that maps to silence and to a full wave.
    public var waveformFloorDb: Double = -55 // source: assumed // MEASURE
    public var waveformCeilingDb: Double = -12 // source: assumed // MEASURE
    /// One-pole smoothing time constants toward a rising and a falling level, seconds.
    public var waveformAttack: Double = MotionTokens.waveAttack
    public var waveformRelease: Double = MotionTokens.waveRelease
    /// The smoothed level is multiplied by this, then capped at 1.
    public var waveformGain: Double = WaveTokens.gain

    // MARK: Color (light appearance, dark appearance)

    public var fillLight: String = FlowBarColors.light.flowFill.hex
    public var fillDark: String = FlowBarColors.dark.flowFill.hex
    public var ringLight: String = FlowBarColors.light.flowRing.hex
    public var ringDark: String = FlowBarColors.dark.flowRing.hex
    public var textLight: String = FlowBarColors.light.flowText.hex
    public var textDark: String = FlowBarColors.dark.flowText.hex
    public var secondaryTextLight: String = FlowBarColors.light.flowTextSecondary.hex
    public var secondaryTextDark: String = FlowBarColors.dark.flowTextSecondary.hex
    public var idleMarkLight: String = FlowBarColors.light.flowIdleMark.hex
    public var idleMarkDark: String = FlowBarColors.dark.flowIdleMark.hex
    public var liveLight: String = FlowBarColors.light.flowLive.hex
    public var liveDark: String = FlowBarColors.dark.flowLive.hex
    public var stopGlyphLight: String = FlowBarColors.light.flowStopGlyph.hex
    public var stopGlyphDark: String = FlowBarColors.dark.flowStopGlyph.hex
    public var cancelLight: String = FlowBarColors.light.flowCancel.hex
    public var cancelDark: String = FlowBarColors.dark.flowCancel.hex
    public var buttonLight: String = FlowBarColors.light.flowButton.hex
    public var buttonDark: String = FlowBarColors.dark.flowButton.hex
    public var buttonTextLight: String = FlowBarColors.light.flowButtonText.hex
    public var buttonTextDark: String = FlowBarColors.dark.flowButtonText.hex
    public var buttonRingLight: String = FlowBarColors.light.flowButtonRing.hex
    public var buttonRingDark: String = FlowBarColors.dark.flowButtonRing.hex
    public var keyRingLight: String = FlowBarColors.light.flowKeyRing.hex
    public var keyRingDark: String = FlowBarColors.dark.flowKeyRing.hex
    public var keyBottomLight: String = FlowBarColors.light.flowKeyBottom.hex
    public var keyBottomDark: String = FlowBarColors.dark.flowKeyBottom.hex
    public var timerLight: String = FlowBarColors.light.flowTimer.hex
    public var timerDark: String = FlowBarColors.dark.flowTimer.hex
    public var stillWaveLight: String = FlowBarColors.light.flowStillWave.hex
    public var stillWaveDark: String = FlowBarColors.dark.flowStillWave.hex

    // MARK: Motion (seconds; spring response and damping)

    public var springResponse: Double = MotionTokens.barWidth.response
    public var springDamping: Double = MotionTokens.barWidth.damping
    public var idleFadeDelay: Double = MotionTokens.barIdleFadeDelay
    public var idleFadeDuration: Double = MotionTokens.barIdleFade
    public var idleFadedOpacity: Double = OpacityTokens.idleFaded
    public var tooltipDelay: Double = MotionTokens.tooltipDelay
    public var timerDelay: Double = MotionTokens.barTimerDelay
    public var nudgeAt: Double = MotionTokens.barNudgeAt
    public var dotsPeriod: Double = MotionTokens.dotsPeriod
    public var checkDraw: Double = MotionTokens.insertedCheck
    public var insertedHold: Double = MotionTokens.insertedHold
    public var pasteToastDuration: Double = MotionTokens.toastPaste
    public var cancelledToastDuration: Double = MotionTokens.toastCancel
    public var alertSticky: Double = MotionTokens.alertSticky
    public var toastIn: Double = MotionTokens.toastIn
    public var toastOut: Double = MotionTokens.toastOut
    public var toastRise: Double = MotionTokens.toastRise
    public var shakeAmplitude: Double = MotionTokens.alertShake
    public var shakeDuration: Double = MotionTokens.alertShakeDuration

    public init() {}

    /// The board values. Replace assumed ones with measured ones.
    public static let defaults = Tokens()
}

/// Tokens the UI reads, observable so the debug panel can tune them live. Overrides persist in
/// UserDefaults until reset; `swiftSource` prints them for pasting into this file.
@MainActor
@Observable
public final class LiveTokens {
    public static let shared = LiveTokens()
    /// v2 values live under a new key, so overrides tuned for v1 are not applied to v2.
    static let key = "murmur.tokenOverrides.v2"

    public var value: Tokens {
        didSet { save() }
    }

    init() {
        value = UserDefaults.standard.data(forKey: Self.key).flatMap(Tokens.merged(over:)) ?? .defaults
    }

    public func reset() { value = .defaults }

    func save() {
        if value == .defaults {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Current values as `name: value` lines, for pasting into `Tokens`.
    public var swiftSource: String {
        let mirror = Mirror(reflecting: value)
        let defaults = Mirror(reflecting: Tokens.defaults).children.reduce(into: [String: String]()) { $0[$1.label ?? ""] = "\($1.value)" }
        return mirror.children.compactMap { child in
            guard let label = child.label else { return nil }
            let current = "\(child.value)"
            let marker = defaults[label] == current ? "" : "   // changed"
            let literal = child.value is String ? "\"\(current)\"" : current
            return "public var \(label) = \(literal)\(marker)"
        }.joined(separator: "\n")
    }
}

public extension Color {
    /// A color that follows light and dark appearance, from two `#RRGGBBAA` tokens.
    static func token(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0xFF00FFFF
        self.init(
            srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
            blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255
        )
    }
}

public extension Font.Weight {
    static func token(_ name: String) -> Font.Weight {
        switch name {
        case "regular": .regular
        case "semibold": .semibold
        case "bold": .bold
        default: .medium
        }
    }
}
