import AppKit
import SwiftUI

/// Everything a view needs to draw: colors for the current scheme (and contrast), the Flow Bar's
/// fixed colors, the text scale and motion settings. Views read it from `\.theme`; they never look
/// colors up through `NSAppearance` themselves (rule 5).
public struct Theme: Sendable {
    public var scheme: ColorScheme
    public var colors: ThemeColors
    public var flow: FlowBarColors
    public var textScale: Double
    public var motion: Motion
    public var increaseContrast: Bool
    public var reduceTransparency: Bool

    public static func make(scheme: ColorScheme, increaseContrast: Bool = false, reduceMotion: Bool = false,
                            reduceTransparency: Bool = false, textScale: Double = TypeTokens.scaleDefault, timeScale: Double = 1) -> Theme {
        let base = scheme == .dark ? ThemeColors.dark : ThemeColors.light
        let flow = FlowBarColors.forAppearance(dark: scheme == .dark)
        return Theme(scheme: scheme, colors: increaseContrast ? base.increasedContrast : base, flow: increaseContrast ? flow.increasedContrast : flow,
                     textScale: textScale, motion: Motion(reduce: reduceMotion, timeScale: timeScale),
                     increaseContrast: increaseContrast, reduceTransparency: reduceTransparency)
    }

    public static let light = Theme.make(scheme: .light)
    public static let dark = Theme.make(scheme: .dark)

    public func font(_ style: TextStyleToken) -> Font { TypeTokens.font(style, scale: textScale) }
}

extension EnvironmentValues {
    @Entry public var theme: Theme = .light
}

/// Builds the theme from the environment (color scheme, Increase Contrast, Reduce Motion, Reduce
/// Transparency), the Text size setting and the debug overrides, and injects it as `\.theme`.
public struct ThemeProvider<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let textScale: Double
    private let content: Content

    public init(textScale: Double = TypeTokens.scaleDefault, @ViewBuilder content: () -> Content) {
        self.textScale = textScale
        self.content = content()
    }

    public var body: some View {
        let debug = UIDebug.shared
        content.environment(\.theme, Theme.make(
            scheme: scheme, increaseContrast: contrast == .increased, reduceMotion: debug.reduceMotion ?? reduceMotion,
            reduceTransparency: reduceTransparency, textScale: debug.textScale ?? textScale, timeScale: debug.timeScale))
    }
}

/// Applies a text style token: font, line height, tracking and case, at the theme's text scale.
public struct TextStyleModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let style: TextStyleToken

    public func body(content: Content) -> some View {
        let font = TypeTokens.nsFont(style, scale: theme.textScale)
        let natural = font.ascender - font.descender + font.leading
        let lineHeight = max(TypeTokens.minimumSize, style.lineHeight * theme.textScale)
        content
            .font(Font(font))
            .lineSpacing(max(0, lineHeight - natural))
            .tracking(style.tracking * font.pointSize)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

extension View {
    public func textStyle(_ style: TextStyleToken) -> some View { modifier(TextStyleModifier(style: style)) }
}

/// The Appearance setting (System, Light, Dark), applied to every Murmur window. The debug override
/// wins while it is set.
@MainActor
public enum AppearanceController {
    public enum Setting: String, CaseIterable, Sendable { case system, light, dark }

    private static var setting: Setting = .system

    public static func apply(_ value: String) {
        setting = Setting(rawValue: value) ?? .system
        refresh()
    }

    public static func refresh() {
        let debug = UIDebug.shared.appearance
        let effective: Setting = debug == .system ? setting : (debug == .dark ? .dark : .light)
        NSApp?.appearance = effective == .system ? nil : NSAppearance(named: effective == .dark ? .darkAqua : .aqua)
    }
}
