import AppKit
import SwiftUI

/// Every number the Flow Bar uses (spec rule 5). These are runnable placeholders, not measurements:
/// the owner replaces them with values measured from recordings of the reference app. Nothing in the
/// UI hard-codes a size, color, duration, spring or sound value; it reads `LiveTokens`, which starts
/// from these defaults and can be tuned at runtime from the debug panel.
public struct Tokens: Codable, Equatable, Sendable {
    // MARK: Bar geometry (points)

    /// Pill size while idle and visible.
    public var idleWidth: Double = 44
    public var idleHeight: Double = 10
    /// Pill size while listening or processing.
    public var activeWidth: Double = 120
    public var activeHeight: Double = 34
    /// Pill size while hands-free (room for the stop and cancel buttons).
    public var handsFreeWidth: Double = 168
    /// Card size for notices (errors, cancelled, no text box).
    public var noticeWidth: Double = 360
    public var noticeHeight: Double = 52
    public var cornerRadius: Double = 17
    /// Gap between the bar and the Dock (or the bottom of the visible frame).
    public var bottomMargin: Double = 10
    /// Extra lift in a full-screen app's Space, where the Dock is hidden.
    public var fullScreenLift: Double = 6
    /// Offsets when the Dock sits on the left or right edge.
    public var dockSideOffset: Double = 0

    // MARK: Waveform

    public var waveformBars: Int = 9
    public var waveformBarWidth: Double = 3
    public var waveformBarGap: Double = 3
    public var waveformMinHeight: Double = 3
    public var waveformMaxHeight: Double = 20
    /// Level (dBFS) that maps to a silent and to a full bar.
    public var waveformFloorDb: Double = -55
    public var waveformCeilingDb: Double = -12
    /// Smoothing toward a rising and a falling level, per update (0…1).
    public var waveformAttack: Double = 0.55
    public var waveformRelease: Double = 0.18

    // MARK: Color (light, dark), as hex RGBA

    public var surfaceLight: String = "#1C1C1EF2"
    public var surfaceDark: String = "#2C2C2EF2"
    public var waveformLight: String = "#FFFFFFFF"
    public var waveformDark: String = "#FFFFFFFF"
    public var idleLight: String = "#3A3A3CCC"
    public var idleDark: String = "#636366CC"
    public var stopLight: String = "#FF453AFF"
    public var stopDark: String = "#FF453AFF"
    public var cancelLight: String = "#FFFFFF99"
    public var cancelDark: String = "#FFFFFF99"
    public var errorLight: String = "#FF9F0AFF"
    public var errorDark: String = "#FF9F0AFF"
    public var successLight: String = "#30D158FF"
    public var successDark: String = "#30D158FF"
    public var textLight: String = "#FFFFFFFF"
    public var textDark: String = "#FFFFFFFF"
    public var secondaryTextLight: String = "#FFFFFFA6"
    public var secondaryTextDark: String = "#FFFFFFA6"

    // MARK: Material

    /// Background blur (vibrancy) under the surface color.
    public var useBlur: Bool = true
    public var borderWidth: Double = 0.5
    public var borderLight: String = "#FFFFFF26"
    public var borderDark: String = "#FFFFFF1F"
    public var shadowRadius: Double = 10
    public var shadowOpacity: Double = 0.28
    public var shadowY: Double = -2

    // MARK: Motion (seconds, spring response and damping)

    public var appearDuration: Double = 0.18
    public var disappearDuration: Double = 0.14
    public var springResponse: Double = 0.32
    public var springDamping: Double = 0.78
    /// One cycle of the processing indicator.
    public var processingLoopPeriod: Double = 1.1
    /// How long the inserted confirmation stays.
    public var confirmationHold: Double = 0.7
    /// How long the cancelled toast stays (spec: about 3 s).
    public var cancelledToastDuration: Double = 3.0
    /// How long the no-text-box notice counts down.
    public var noticeDuration: Double = 6.0
    /// Waveform redraw rate (Hz).
    public var waveformFrameRate: Double = 30

    // MARK: Type

    public var labelSize: Double = 12.5
    public var labelWeight: String = "medium"
    public var buttonSize: Double = 12
    public var hubTypeface: String = "system"

    // MARK: Sound

    public var soundStartPitchLow: Double = 660
    public var soundStartPitchHigh: Double = 990
    public var soundStartLength: Double = 0.16
    public var soundStopPitchHigh: Double = 990
    public var soundStopPitchLow: Double = 660
    public var soundStopLength: Double = 0.15
    public var soundErrorPitchHigh: Double = 330
    public var soundErrorPitchLow: Double = 262
    public var soundErrorLength: Double = 0.27
    public var soundVolume: Double = 0.35

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
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Tokens.self, from: data) {
            value = saved
        } else {
            value = .defaults
        }
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
