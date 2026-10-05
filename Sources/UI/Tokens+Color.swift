import AppKit
import SwiftUI

// Color tokens (UI_REDESIGN.md v2 §3.2, `Design/tokens.json`). Every value carries its source: board =
// read from the owner's "Murmur UI Kit" boards, logo = sampled from the logo, derived = computed for a
// contrast target or a pressed state, assumed = on no board. Derived and assumed values carry `// MEASURE`.
// Translucent tokens are ink (#1F1E1D) or ivory (#F6EEE4) at an opacity, as the boards write them.
// No app geometry lives in this file, so a web token file can be generated from it later (§11).

/// An sRGB color with alpha, written "#RRGGBB", "#RRGGBBAA", or as ink or ivory at an opacity.
public struct ColorToken: Sendable, Hashable {
    public let r, g, b, a: Double

    public init(_ hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0xFF00_FFFF
        r = Double((v >> 24) & 0xFF) / 255
        g = Double((v >> 16) & 0xFF) / 255
        b = Double((v >> 8) & 0xFF) / 255
        a = Double(v & 0xFF) / 255
    }

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// This color at another opacity.
    public func opacity(_ alpha: Double) -> ColorToken { ColorToken(r: r, g: g, b: b, a: alpha) }

    /// Ink (`#1F1E1D`) at an opacity, as the boards write "ink n%".
    public static func ink(_ alpha: Double) -> ColorToken { Palette.ink.opacity(alpha) }
    /// Ivory (`#F6EEE4`) at an opacity, as the boards write "ivory n%".
    public static func ivory(_ alpha: Double) -> ColorToken { Palette.ivory.opacity(alpha) }

    /// Red, green, blue and alpha, 0…1.
    public var components: (r: Double, g: Double, b: Double, a: Double) { (r, g, b, a) }

    /// "#RRGGBB", or "#RRGGBBAA" when translucent.
    public var hex: String {
        func h(_ v: Double) -> String { String(format: "%02X", Int((v * 255).rounded())) }
        return "#" + h(r) + h(g) + h(b) + (a < 1 ? h(a) : "")
    }

    public var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public var color: Color { Color(nsColor: nsColor) }

    /// This color composited over an opaque background (how a translucent token is seen).
    public func over(_ background: ColorToken) -> ColorToken {
        ColorToken(r: r * a + background.r * (1 - a), g: g * a + background.g * (1 - a), b: b * a + background.b * (1 - a))
    }

    /// WCAG relative luminance (alpha ignored).
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio against an opaque background; a translucent color is composited first.
    public func contrast(with background: ColorToken) -> Double {
        let fg = a < 1 ? over(background) : self
        let x = fg.luminance, y = background.luminance
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// The two base inks every translucent token is made from.
public enum Palette {
    public static let ink = ColorToken("#1F1E1D") // source: board
    public static let ivory = ColorToken("#F6EEE4") // source: board / logo
}

/// The Hub's, the brand's and the controls' colors, one set per scheme.
public struct ThemeColors: Sendable {
    public var bgWindow, bgPanel, bgSunken, fillHover, fillSelected, fillChip: ColorToken
    public var textPrimary, textSecondary, textTertiary, stone: ColorToken
    public var borderHairline, borderDivider, borderControl: ColorToken
    public var accentClay, accentClayHover, accentClayPressed, onClay: ColorToken
    public var inkFill, inkFillHover, inkFillPressed, onInk, focusRing: ColorToken
    /// Edges the boards draw at other ink strengths than the hairline.
    public var edgePanel, edgeList, edgeStrong, edgeKey, edgeToast, underline, fieldHalo: ColorToken
    public var shadowFloat, scrim: ColorToken

    public static let light = ThemeColors(
        bgWindow: ColorToken("#F6EEE4"), // source: board / logo
        bgPanel: ColorToken("#FBF7F1"), // source: board
        bgSunken: ColorToken("#EDE3D6"), // source: board
        fillHover: .ink(0.035), // source: board
        fillSelected: .ink(0.07), // source: board
        fillChip: .ink(0.06), // source: board
        textPrimary: ColorToken("#1F1E1D"), // source: board
        textSecondary: ColorToken("#5E5A54"), // source: board
        textTertiary: ColorToken("#6F6A62"), // source: derived (AA replacement for the boards' stone captions) // MEASURE
        stone: ColorToken("#8A857C"), // source: board (decoration only, never text)
        borderHairline: .ink(0.16), // source: board
        borderDivider: .ink(0.08), // source: board
        borderControl: ColorToken("#8A857C"), // source: derived (3:1 control edge) // MEASURE
        accentClay: ColorToken("#B54C3C"), // source: logo
        accentClayHover: ColorToken("#A94737"), // source: derived (halfway to pressed) // MEASURE
        accentClayPressed: ColorToken("#9E4234"), // source: derived // MEASURE
        onClay: ColorToken("#F6EEE4"), // source: board
        inkFill: ColorToken("#1F1E1D"), // source: board
        inkFillHover: ColorToken("#272625"), // source: derived (halfway to pressed) // MEASURE
        inkFillPressed: ColorToken("#2F2D2C"), // source: derived // MEASURE
        onInk: ColorToken("#F6EEE4"), // source: board
        focusRing: ColorToken("#1F1E1D"), // source: board
        edgePanel: .ink(0.12), // source: board (content panel, status card, feature samples)
        edgeList: .ink(0.14), // source: board (list containers, segment ring, key cap bottom)
        edgeStrong: .ink(0.20), // source: board (app tiles, outline tags)
        edgeKey: .ink(0.25), // source: board (key cap ring, dashed snippet box)
        edgeToast: .ink(0.18), // source: board (paper toast, stat strip dividers)
        underline: .ink(0.30), // source: board (link underline)
        fieldHalo: .ink(0.08), // source: board (focused field halo)
        shadowFloat: .ink(0.30), // source: board
        scrim: .ink(0.40) // source: assumed (sheets) // MEASURE
    )

    public static let dark = ThemeColors(
        bgWindow: ColorToken("#1F1E1D"), // source: board
        bgPanel: ColorToken("#2C2A27"), // source: board
        bgSunken: ColorToken("#191817"), // source: derived // MEASURE
        fillHover: .ivory(0.05), // source: derived // MEASURE
        fillSelected: .ivory(0.08), // source: board
        fillChip: .ivory(0.07), // source: board
        textPrimary: ColorToken("#F6EEE4"), // source: board
        textSecondary: ColorToken("#A39E95"), // source: board
        textTertiary: ColorToken("#9A958C"), // source: derived // MEASURE
        stone: ColorToken("#8A857C"), // source: board (decoration only, never text)
        borderHairline: .ivory(0.14), // source: board
        borderDivider: .ivory(0.10), // source: board
        borderControl: ColorToken("#8F8A81"), // source: derived // MEASURE
        accentClay: ColorToken("#D9705F"), // source: board
        accentClayHover: ColorToken("#DC7B6B"), // source: derived (halfway to pressed) // MEASURE
        accentClayPressed: ColorToken("#DF8678"), // source: derived // MEASURE
        onClay: ColorToken("#1F1E1D"), // source: board
        inkFill: ColorToken("#F6EEE4"), // source: board
        inkFillHover: ColorToken("#EEE6DA"), // source: derived (halfway to pressed) // MEASURE
        inkFillPressed: ColorToken("#E6DDD1"), // source: derived // MEASURE
        onInk: ColorToken("#1F1E1D"), // source: board
        focusRing: ColorToken("#F6EEE4"), // source: board
        edgePanel: .ivory(0.12), // source: derived (light strengths on ivory) // MEASURE
        edgeList: .ivory(0.14), // source: derived // MEASURE
        edgeStrong: .ivory(0.20), // source: derived // MEASURE
        edgeKey: .ivory(0.25), // source: derived // MEASURE
        edgeToast: .ivory(0.18), // source: derived // MEASURE
        underline: .ivory(0.30), // source: derived // MEASURE
        fieldHalo: .ivory(0.10), // source: derived // MEASURE
        shadowFloat: ColorToken("#000000").opacity(0.50), // source: derived // MEASURE
        scrim: ColorToken("#000000").opacity(0.55) // source: assumed // MEASURE
    )

    /// Increase Contrast (§6.3): hairlines and dividers become control borders, tertiary text becomes
    /// secondary. (The selected-card ring thickening is geometry, in `HubGeometry`.)
    public var increasedContrast: ThemeColors {
        var c = self
        c.borderHairline = borderControl
        c.borderDivider = borderControl
        c.edgePanel = borderControl
        c.edgeList = borderControl
        c.edgeToast = borderControl
        c.textTertiary = textSecondary
        return c
    }
}

/// The Flow Bar's colors. They follow the **system** appearance, not the Hub's Appearance setting:
/// ink in light, raised ink in dark (§2.5). Only `flowFill` and `flowRing` differ between the two.
public struct FlowBarColors: Sendable {
    public var flowFill, flowRing, flowText, flowTextSecondary, flowIdleMark, flowLive, flowStopGlyph: ColorToken
    public var flowCancel, flowButton, flowButtonText, flowButtonRing: ColorToken
    /// The tooltip's inline key cap rings, the hands-free timer, the hover pill's still wave.
    public var flowKeyRing, flowKeyBottom, flowTimer, flowStillWave: ColorToken

    public static let light = FlowBarColors(
        flowFill: ColorToken("#1F1E1D"), // source: board
        flowRing: .ivory(0.12), // source: board
        flowText: ColorToken("#F6EEE4"), // source: board
        flowTextSecondary: .ivory(0.55), // source: board
        flowIdleMark: .ivory(0.45), // source: board
        flowLive: ColorToken("#D9705F"), // source: board
        flowStopGlyph: ColorToken("#1F1E1D"), // source: board
        flowCancel: ColorToken("#34312E"), // source: board
        flowButton: ColorToken("#F6EEE4"), // source: board
        flowButtonText: ColorToken("#1F1E1D"), // source: board
        flowButtonRing: .ivory(0.22), // source: board
        flowKeyRing: .ivory(0.30), // source: board
        flowKeyBottom: .ivory(0.20), // source: board
        flowTimer: .ivory(0.70), // source: board
        flowStillWave: .ivory(0.60) // source: board
    )

    public static let dark: FlowBarColors = {
        var c = light
        c.flowFill = ColorToken("#2C2A27") // source: board
        c.flowRing = .ivory(0.18) // source: board
        return c
    }()

    /// Increase Contrast: the ring that separates the bar from dark windows gets stronger (§6.3).
    public var increasedContrast: FlowBarColors {
        var c = self
        c.flowRing = .ivory(0.40) // source: ui_redesign §6.3
        return c
    }

    public static func forAppearance(dark: Bool) -> FlowBarColors { dark ? .dark : .light }
}

/// Opacities used on top of color tokens (decorative states only).
public enum OpacityTokens {
    /// The idle Flow Bar fades to this after `MotionTokens.barIdleFadeDelay` (§6.1).
    public static let idleFaded: Double = 0.40 // source: board
    /// The silent-audio History row's mic tile ring (§5.3).
    public static let silentTile: Double = 0.12 // source: board
    /// The processing menu bar glyph (§3.6).
    public static let processingGlyph: Double = 0.45 // source: board
    /// The countdown ring's track (§3.5).
    public static let ringTrack: Double = 0.22 // source: board
    /// A group of controls that is off because a switch above it is off (cleanup levels with AI edits off).
    public static let disabledGroup: Double = 0.5 // source: assumed // MEASURE
    /// The dimmed half of a gallery comparison, and backdrops behind floating previews.
    public static let subtle: Double = 0.25 // source: assumed // MEASURE
}
