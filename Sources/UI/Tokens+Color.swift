import AppKit
import SwiftUI

// Color tokens (UI_REDESIGN.md §3.2). Every value carries its source: ant = measured from Anthropic's
// theme page, logo = sampled from the owner's logo, wis = measured from the reference screenshots,
// derived = computed by the designer to hit a contrast target, assumed = a placeholder. Derived and
// assumed values carry `// MEASURE` so the owner can replace them. No app geometry lives in this file,
// so a web design system can be generated from it later (§11).

/// An sRGB color given as "#RRGGBB" or "#RRGGBBAA".
public struct ColorToken: Sendable, Hashable {
    public let hex: String

    public init(_ hex: String) {
        self.hex = hex
    }

    /// Red, green, blue and alpha, 0…1.
    public var components: (r: Double, g: Double, b: Double, a: Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0xFF00_FFFF
        return (Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    public var nsColor: NSColor {
        let c = components
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    public var color: Color { Color(nsColor: nsColor) }

    /// WCAG relative luminance (alpha ignored).
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let c = components
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// WCAG contrast ratio against another color.
    public func contrast(with other: ColorToken) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The Hub's and the brand's colors, one set per scheme.
public struct ThemeColors: Sendable {
    public var bgWindow, bgPanel, bgCard, bgField, bgHover, bgChip, bgFeature: ColorToken
    public var borderPanel, borderFeature, borderDivider, borderControl: ColorToken
    public var textTitle, textPrimary, textBody, textSecondary, textDisabled, textPlaceholder: ColorToken
    public var accentClay, accentClayHover, accentClayPressed, accentClayText, accentClayTint: ColorToken
    public var buttonText, focusRing, dangerText, scrim: ColorToken

    public static let light = ThemeColors(
        bgWindow: ColorToken("#F4F3ED"), // source: ant
        bgPanel: ColorToken("#F9F9F6"), // source: ant
        bgCard: ColorToken("#FFFFFF"), // source: ant
        bgField: ColorToken("#FFFFFF"), // source: ant
        bgHover: ColorToken("#E8E7DD"), // source: ant
        bgChip: ColorToken("#ECEBE3"), // source: ant
        bgFeature: ColorToken("#F6EEE5"), // source: logo
        borderPanel: ColorToken("#E3E2D8"), // source: derived // MEASURE
        borderFeature: ColorToken("#E6D6C8"), // source: derived // MEASURE
        borderDivider: ColorToken("#E8E7DD"), // source: ant
        borderControl: ColorToken("#858371"), // source: derived // MEASURE
        textTitle: ColorToken("#2A2819"), // source: derived // MEASURE
        textPrimary: ColorToken("#3D3A2A"), // source: ant
        textBody: ColorToken("#4D4A39"), // source: derived // MEASURE
        textSecondary: ColorToken("#6A6755"), // source: derived // MEASURE
        textDisabled: ColorToken("#A8A596"), // source: derived // MEASURE
        textPlaceholder: ColorToken("#6A6755"), // source: derived // MEASURE
        accentClay: ColorToken("#B54B3C"), // source: logo
        accentClayHover: ColorToken("#A24133"), // source: derived // MEASURE
        accentClayPressed: ColorToken("#8F3A2E"), // source: derived // MEASURE
        accentClayText: ColorToken("#A8402F"), // source: derived // MEASURE
        accentClayTint: ColorToken("#F1DDD5"), // source: derived // MEASURE
        buttonText: ColorToken("#FFFFFF"), // source: ant
        focusRing: ColorToken("#8F3A2E"), // source: derived // MEASURE
        dangerText: ColorToken("#9B3A2E"), // source: derived // MEASURE
        scrim: ColorToken("#2A281966") // source: derived // MEASURE
    )

    public static let dark = ThemeColors(
        bgWindow: ColorToken("#181713"), // source: derived // MEASURE
        bgPanel: ColorToken("#1F1E19"), // source: derived // MEASURE
        bgCard: ColorToken("#26241E"), // source: derived // MEASURE
        bgField: ColorToken("#26241E"), // source: derived // MEASURE
        bgHover: ColorToken("#302E26"), // source: derived // MEASURE
        bgChip: ColorToken("#2A2822"), // source: derived // MEASURE
        bgFeature: ColorToken("#2B211B"), // source: derived // MEASURE
        borderPanel: ColorToken("#34322A"), // source: derived // MEASURE
        borderFeature: ColorToken("#42342B"), // source: derived // MEASURE
        borderDivider: ColorToken("#2D2B24"), // source: derived // MEASURE
        borderControl: ColorToken("#75725F"), // source: derived // MEASURE
        textTitle: ColorToken("#FAF9F5"), // source: derived // MEASURE
        textPrimary: ColorToken("#EDEBE0"), // source: derived // MEASURE
        textBody: ColorToken("#D9D6C8"), // source: derived // MEASURE
        textSecondary: ColorToken("#A8A596"), // source: derived // MEASURE
        textDisabled: ColorToken("#6F6C5C"), // source: derived // MEASURE
        textPlaceholder: ColorToken("#A8A596"), // source: derived // MEASURE
        accentClay: ColorToken("#B54B3C"), // source: logo
        accentClayHover: ColorToken("#C45646"), // source: derived // MEASURE
        accentClayPressed: ColorToken("#A24133"), // source: derived // MEASURE
        accentClayText: ColorToken("#E58B77"), // source: derived // MEASURE
        accentClayTint: ColorToken("#3A241E"), // source: derived // MEASURE
        buttonText: ColorToken("#FFFFFF"), // source: derived // MEASURE
        focusRing: ColorToken("#E58B77"), // source: derived // MEASURE
        dangerText: ColorToken("#E58B77"), // source: derived // MEASURE
        scrim: ColorToken("#00000099") // source: derived // MEASURE
    )

    /// Increase Contrast (§6.2): hairlines become control borders, secondary text becomes body text,
    /// and the clay tint becomes the hover fill (selected cards then carry a 2 pt clay border).
    public var increasedContrast: ThemeColors {
        var c = self
        c.borderPanel = borderControl
        c.borderDivider = borderControl
        c.textSecondary = textBody
        c.accentClayTint = bgHover
        return c
    }
}

/// The Flow Bar's colors: one set, identical in light and dark, because the bar floats over other apps.
/// The reference's violet-cast grays are warmed to this palette (§3.2); the originals are listed there.
public struct FlowBarColors: Sendable {
    public var fill = ColorToken("#000000") // source: wis
    public var border = ColorToken("#403D35") // source: wis (warmed) // MEASURE
    public var tooltip = ColorToken("#2E2C25") // source: wis (warmed) // MEASURE
    public var text = ColorToken("#FFFFFF") // source: wis
    public var dot = ColorToken("#D9D6CC") // source: wis (warmed) // MEASURE
    public var bar = ColorToken("#FFFFFF") // source: wis
    public var xCircle = ColorToken("#77746A") // source: wis (warmed) // MEASURE
    public var xGlyph = ColorToken("#ECEAE0") // source: wis (warmed) // MEASURE
    public var stop = ColorToken("#C9503F") // source: logo (lifted 8% for legibility on black) // MEASURE
    public var alertBorder = ColorToken("#3A382F") // source: wis (warmed) // MEASURE
    public var button = ColorToken("#3E3C35") // source: wis (warmed) // MEASURE
    public var buttonHover = ColorToken("#4A4840") // source: derived (button, one step lighter) // MEASURE
    public var iconError = ColorToken("#E27A66") // source: derived // MEASURE
    public var iconInfo = ColorToken("#D3D2CA") // source: ant

    public static let standard = FlowBarColors()
}

/// Opacities used on top of color tokens.
public enum OpacityTokens {
    /// Sidebar row hover: `bg-hover` at half strength (§4).
    public static let hoverHalf: Double = 0.5 // source: ui_redesign §4
    /// Disabled controls that are not text (tracks, borders, icons).
    public static let disabled: Double = 0.45 // source: assumed // MEASURE
    /// The dimmed half of a gallery comparison, and backdrops behind floating previews.
    public static let subtle: Double = 0.25 // source: assumed // MEASURE
}
