import AppKit
import SwiftUI

/// The Flow Bar's live-tunable tokens (spec rule 5, UI_REDESIGN.md §3.5 and §5.1). Defaults come from
/// the redesign's static tokens (`FlowGeometry`, `FlowBarColors`, `MotionTokens`, `TypeTokens`), so
/// there is one source of truth; the debug panel overrides them at runtime through `LiveTokens`.
/// Names from before the redesign are kept (saved overrides keep decoding); the bar is identical in
/// light and dark, so each light/dark color pair defaults to the same value.
public struct Tokens: Codable, Equatable, Sendable {
    /// Saved overrides laid over the current defaults, so a token added later keeps its default
    /// instead of making the whole saved set unreadable.
    public static func merged(over data: Data) -> Tokens? {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Tokens.defaults)) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new }) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: merged)
    }

    // MARK: Pill geometry (points). H = activeHeight.

    /// The resting pill (not hovered).
    public var idleWidth: Double = FlowGeometry.idleSize.width
    public var idleHeight: Double = FlowGeometry.idleSize.height
    /// Hovered idle pill, showing the idle squares.
    public var hoverWidth: Double = FlowGeometry.hoverWidth
    /// Hold-to-talk, processing and inserted pill width (assumed: the hover size).
    public var activeWidth: Double = FlowGeometry.hoverWidth
    public var activeHeight: Double = FlowGeometry.pillHeight
    /// Hands-free pill: cancel circle, waveform, stop circle.
    public var handsFreeWidth: Double = FlowGeometry.activeWidth
    /// Round buttons on the hands-free pill, and the padding around them.
    public var buttonDiameter: Double = FlowGeometry.buttonDiameter
    public var buttonPadding: Double = FlowGeometry.buttonPadding
    /// Pill corner radius (half the height: a capsule).
    public var cornerRadius: Double = FlowGeometry.pillHeight / 2
    public var borderWidth: Double = FlowGeometry.border
    /// Gap between the bar and the Dock (or the bottom of the visible frame).
    public var bottomMargin: Double = 10 // source: assumed // MEASURE
    /// Extra lift in a full-screen app's Space, where the Dock is hidden.
    public var fullScreenLift: Double = 6 // source: assumed // MEASURE
    /// Offsets when the Dock sits on the left or right edge.
    public var dockSideOffset: Double = 0 // source: assumed // MEASURE

    // MARK: Tooltip, alert and toast

    public var tooltipHeight: Double = FlowGeometry.tooltipHeight
    /// Gap between the pill and the tooltip, alert or toast above it.
    public var tooltipGap: Double = FlowGeometry.tooltipGap
    /// Alert (transcription error, no audio).
    public var noticeWidth: Double = FlowGeometry.alertSize.width
    public var noticeHeight: Double = FlowGeometry.alertSize.height
    public var alertRadius: Double = FlowGeometry.alertRadius
    public var alertPadding: Double = FlowGeometry.alertPadding
    /// Toast (paste error, cancelled, no text box, info).
    public var toastWidth: Double = FlowGeometry.toastSize.width
    public var toastHeight: Double = FlowGeometry.toastSize.height
    public var toastRadius: Double = FlowGeometry.toastRadius

    // MARK: Waveform and idle squares

    public var waveformBars: Int = FlowGeometry.bars
    public var waveformBarWidth: Double = FlowGeometry.barWidth
    public var waveformBarGap: Double = FlowGeometry.barPitch - FlowGeometry.barWidth
    /// A silent bar is a square (as tall as it is wide), so silence looks like the idle squares.
    public var waveformMinHeight: Double = FlowGeometry.barWidth
    public var waveformMaxHeight: Double = FlowGeometry.barMaxHeight
    public var idleSquares: Int = FlowGeometry.idleSquares
    public var squareSide: Double = FlowGeometry.squareSide
    public var squarePitch: Double = FlowGeometry.squarePitch
    /// Level (dBFS) that maps to a silent and to a full bar.
    public var waveformFloorDb: Double = -55 // source: assumed // MEASURE
    public var waveformCeilingDb: Double = -12 // source: assumed // MEASURE
    /// One-pole smoothing time constants toward a rising and a falling level, seconds.
    public var waveformAttack: Double = MotionTokens.waveAttack
    public var waveformRelease: Double = MotionTokens.waveRelease
    /// How often the bars scroll one step (the newest level enters on the right), per second.
    public var waveformSampleRate: Double = 30 // source: assumed // MEASURE
    /// How much shorter the outer bars are than the middle ones (0 = all equal), so it reads as a voice.
    public var waveformCenterBias: Double = 0.45 // source: assumed // MEASURE
    /// The level at which a bar has turned fully from a `flow-dot` square to a white bar.
    public var waveformWhiteLevel: Double = 0.15 // source: assumed // MEASURE
    /// Width of the processing shimmer's bright band, as a share of the row.
    public var shimmerWidth: Double = 0.3 // source: assumed // MEASURE

    // MARK: Color (light, dark), as hex RGBA; identical pairs

    public var surfaceLight: String = FlowBarColors.standard.fill.hex
    public var surfaceDark: String = FlowBarColors.standard.fill.hex
    public var waveformLight: String = FlowBarColors.standard.bar.hex
    public var waveformDark: String = FlowBarColors.standard.bar.hex
    public var idleLight: String = FlowBarColors.standard.fill.hex
    public var idleDark: String = FlowBarColors.standard.fill.hex
    public var dotLight: String = FlowBarColors.standard.dot.hex
    public var dotDark: String = FlowBarColors.standard.dot.hex
    public var stopLight: String = FlowBarColors.standard.stop.hex
    public var stopDark: String = FlowBarColors.standard.stop.hex
    public var cancelLight: String = FlowBarColors.standard.xCircle.hex
    public var cancelDark: String = FlowBarColors.standard.xCircle.hex
    public var cancelGlyphLight: String = FlowBarColors.standard.xGlyph.hex
    public var cancelGlyphDark: String = FlowBarColors.standard.xGlyph.hex
    public var errorLight: String = FlowBarColors.standard.iconError.hex
    public var errorDark: String = FlowBarColors.standard.iconError.hex
    public var infoLight: String = FlowBarColors.standard.iconInfo.hex
    public var infoDark: String = FlowBarColors.standard.iconInfo.hex
    /// The inserted check.
    public var successLight: String = FlowBarColors.standard.bar.hex
    public var successDark: String = FlowBarColors.standard.bar.hex
    /// Command Mode's mark on the bar: the clay (rule 11, one accent).
    public var commandLight: String = FlowBarColors.standard.stop.hex
    public var commandDark: String = FlowBarColors.standard.stop.hex
    public var textLight: String = FlowBarColors.standard.text.hex
    public var textDark: String = FlowBarColors.standard.text.hex
    public var secondaryTextLight: String = FlowBarColors.standard.dot.hex
    public var secondaryTextDark: String = FlowBarColors.standard.dot.hex
    public var borderLight: String = FlowBarColors.standard.border.hex
    public var borderDark: String = FlowBarColors.standard.border.hex
    public var tooltipLight: String = FlowBarColors.standard.tooltip.hex
    public var tooltipDark: String = FlowBarColors.standard.tooltip.hex
    public var alertBorderLight: String = FlowBarColors.standard.alertBorder.hex
    public var alertBorderDark: String = FlowBarColors.standard.alertBorder.hex
    public var alertButtonLight: String = FlowBarColors.standard.button.hex
    public var alertButtonDark: String = FlowBarColors.standard.button.hex
    public var alertButtonHoverLight: String = FlowBarColors.standard.buttonHover.hex
    public var alertButtonHoverDark: String = FlowBarColors.standard.buttonHover.hex

    // MARK: Material (flat: no blur, shadow off by default; rule 7)

    public var useBlur: Bool = false
    public var shadowEnabled: Bool = false
    public var shadowRadius: Double = 10 // source: assumed // MEASURE
    public var shadowOpacity: Double = 0.28 // source: assumed // MEASURE
    public var shadowY: Double = -2 // source: assumed // MEASURE

    // MARK: Motion (seconds, spring response and damping)

    public var appearResponse: Double = MotionTokens.barAppear.response
    public var appearDamping: Double = MotionTokens.barAppear.damping
    public var appearScale: Double = MotionTokens.barAppearScale
    public var disappearDuration: Double = MotionTokens.barDisappear
    /// Idle ↔ hover ↔ hands-free.
    public var springResponse: Double = MotionTokens.barExpand.response
    public var springDamping: Double = MotionTokens.barExpand.damping
    public var buttonsIn: Double = MotionTokens.barButtonsIn
    /// One cycle of the processing shimmer.
    public var processingLoopPeriod: Double = MotionTokens.processingPeriod
    public var checkDraw: Double = MotionTokens.insertedCheck
    /// How long the inserted check stays.
    public var confirmationHold: Double = MotionTokens.insertedHold
    /// How long the cancelled toast stays (spec: about 3 s).
    public var cancelledToastDuration: Double = 3.0 // source: assumed // MEASURE
    /// How long other toasts count down.
    public var noticeDuration: Double = 6.0 // source: assumed // MEASURE
    public var toastIn: Double = MotionTokens.toastIn
    public var toastRise: Double = MotionTokens.toastRise
    public var toastOut: Double = MotionTokens.toastOut
    public var tooltipDelay: Double = MotionTokens.tooltipDelay

    // MARK: Type

    public var labelSize: Double = TypeTokens.flowText.size
    public var alertTextSize: Double = TypeTokens.flowAlert.size

    public init() {}

    /// The placeholder set. Replace these values with measured ones.
    public static let defaults = Tokens()
}

/// Tokens the UI reads, observable so the debug panel can tune them live. Overrides persist in
/// UserDefaults until reset; `swiftSource` prints them for pasting into this file.
@MainActor
@Observable
public final class LiveTokens {
    public static let shared = LiveTokens()
    static let key = "murmur.tokenOverrides"

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
