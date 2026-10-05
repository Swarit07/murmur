import AppKit
import SwiftUI

// TEMPORARY (v2 U1): the v1 token values under V1* names, so the v1 components and the v1 Flow Bar keep
// building and looking as they did while v2 replaces them. U2 removes the component uses and U3 the
// Flow Bar uses; this file is deleted when nothing references it. Not part of the v2 design system.


public struct V1ThemeColors: Sendable {
    public var bgWindow, bgPanel, bgCard, bgField, bgHover, bgChip, bgFeature: ColorToken
    public var borderPanel, borderFeature, borderDivider, borderControl: ColorToken
    public var textTitle, textPrimary, textBody, textSecondary, textDisabled, textPlaceholder: ColorToken
    public var accentClay, accentClayHover, accentClayPressed, accentClayText, accentClayTint: ColorToken
    public var buttonText, focusRing, dangerText, scrim: ColorToken

    public static let light = V1ThemeColors(
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

    public static let dark = V1ThemeColors(
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
    public var increasedContrast: V1ThemeColors {
        var c = self
        c.borderPanel = borderControl
        c.borderDivider = borderControl
        c.textSecondary = textBody
        c.accentClayTint = bgHover
        return c
    }
}

public struct V1FlowBarColors: Sendable {
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

    public static let standard = V1FlowBarColors()
}

public enum V1Opacity {
    /// Sidebar row hover: `bg-hover` at half strength (§4).
    public static let hoverHalf: Double = 0.5 // source: ui_redesign §4
    /// Disabled controls that are not text (tracks, borders, icons).
    public static let disabled: Double = 0.45 // source: assumed // MEASURE
    /// The dimmed half of a gallery comparison, and backdrops behind floating previews.
    public static let subtle: Double = 0.25 // source: assumed // MEASURE
}

public enum V1Spacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 28
    public static let x3: CGFloat = 32
    public static let x4: CGFloat = 40
    public static let x5: CGFloat = 48
    public static let x6: CGFloat = 64
}

public enum V1Hub {
    public static let referenceWindow = CGSize(width: 1280, height: 700) // source: wis
    public static let defaultWindow = CGSize(width: 1100, height: 700) // source: assumed // MEASURE
    public static let minimumWindow = CGSize(width: 880, height: 560) // source: assumed // MEASURE

    public static let sidebarWidth: CGFloat = 230 // source: wis
    public static let sidebarItemWidth: CGFloat = 208 // source: wis
    public static let sidebarItemHeight: CGFloat = 38 // source: wis
    public static let sidebarItemPitch: CGFloat = 44 // source: wis
    public static let sidebarItemInset: CGFloat = 10 // source: wis
    public static let sidebarItemRadius: CGFloat = 8 // source: wis (estimated) // MEASURE
    public static let sidebarIcon: CGFloat = 16 // source: wis
    public static let sidebarIconGap: CGFloat = 13 // source: wis
    public static let sidebarCollapsedWidth: CGFloat = 0 // source: assumed // MEASURE

    /// Title bar zone: traffic lights, sidebar toggle and bell share one centre line.
    public static let titleBarHeight: CGFloat = 46 // source: wis
    public static let titleBarCenterLine: CGFloat = 20 // source: wis
    public static let sidebarToggleX: CGFloat = 124 // source: wis

    /// The content panel floats inside the window, flush against the sidebar.
    public static let panelInsetTop: CGFloat = 46 // source: wis
    public static let panelInsetTrailing: CGFloat = 9 // source: wis
    public static let panelInsetBottom: CGFloat = 9 // source: wis
    public static let panelRadius: CGFloat = 12 // source: wis (estimated) // MEASURE
    public static let hairline: CGFloat = 1 // source: wis

    public static let contentMaxWidth: CGFloat = 850 // source: wis
    public static let contentMinSidePadding: CGFloat = 32 // source: wis
    public static let titleTop: CGFloat = 66 // source: wis (re-check after the serif swap) // MEASURE
    public static let titleToFeatureGap: CGFloat = 29 // source: wis

    public static let featureCardHeight: CGFloat = 230 // source: wis
    public static let featureCardPadding: CGFloat = 28 // source: wis
    public static let cardRadius: CGFloat = 14 // source: wis (estimated) // MEASURE
    public static let featureTitleToBody: CGFloat = 28 // source: wis
    public static let featureBodyToButton: CGFloat = 31 // source: wis

    public static let buttonHeightSmall: CGFloat = 32 // source: assumed // MEASURE
    public static let buttonHeight: CGFloat = 40 // source: wis
    public static let buttonHeightLarge: CGFloat = 48 // source: assumed // MEASURE
    public static let buttonMinWidth: CGFloat = 100 // source: wis
    public static let buttonMinWidthSmall: CGFloat = 56 // source: assumed // MEASURE
    public static let buttonRadius: CGFloat = 10 // source: ant (9.6)
    public static let buttonPaddingH: CGFloat = 15 // source: wis
    public static let iconButton: CGFloat = 32 // source: assumed // MEASURE
    public static let iconButtonRadius: CGFloat = 8 // source: assumed // MEASURE
    public static let iconGlyph: CGFloat = 16 // source: wis

    public static let sectionCaptionTop: CGFloat = 58 // source: wis
    public static let sectionCaptionBottom: CGFloat = 22 // source: wis
    public static let listRadius: CGFloat = 14 // source: wis (estimated) // MEASURE
    public static let rowHeight: CGFloat = 57 // source: wis
    public static let rowHeightTwoLine: CGFloat = 75 // source: wis
    public static let rowTimeColumn: CGFloat = 18 // source: wis
    public static let rowTextColumn: CGFloat = 124 // source: wis
    public static let rowTextWrap: CGFloat = 500 // source: wis

    public static let statChipHeight: CGFloat = 32 // source: wis
    public static let statChipWidth: CGFloat = 313 // source: wis
    public static let statChipSeparatorHeight: CGFloat = 16 // source: assumed // MEASURE
    public static let badgeHeight: CGFloat = 26 // source: wis
    public static let badgeRadius: CGFloat = 7 // source: wis (estimated) // MEASURE
    public static let notificationDot: CGFloat = 14 // source: wis

    public static let cardPadding: CGFloat = 20 // source: assumed // MEASURE
    public static let selectedBorder: CGFloat = 2 // source: assumed // MEASURE
    public static let focusRingWidth: CGFloat = 2 // source: assumed // MEASURE
    public static let focusRingGap: CGFloat = 2 // source: assumed // MEASURE
    public static let fieldHeight: CGFloat = 40 // source: assumed // MEASURE
    public static let fieldRadius: CGFloat = 10 // source: assumed // MEASURE
    public static let toggleSize = CGSize(width: 40, height: 24) // source: assumed // MEASURE
    public static let toggleKnobInset: CGFloat = 3 // source: assumed // MEASURE
    public static let checkbox: CGFloat = 18 // source: assumed // MEASURE
    public static let checkboxRadius: CGFloat = 5 // source: assumed // MEASURE
    public static let checkGlyph: CGFloat = 14 // source: assumed // MEASURE
    public static let keycapMin: CGFloat = 26 // source: assumed // MEASURE
    public static let keycapRadius: CGFloat = 6 // source: assumed // MEASURE
    public static let tabHeight: CGFloat = 32 // source: assumed // MEASURE
    public static let tabInset: CGFloat = 3 // source: assumed // MEASURE
    public static let dialogWidth: CGFloat = 440 // source: assumed // MEASURE
    public static let toastMaxWidth: CGFloat = 420 // source: assumed // MEASURE
    public static let tooltipOffset: CGFloat = 6 // source: assumed // MEASURE
    public static let menuMinWidth: CGFloat = 200 // source: assumed // MEASURE
    public static let settingsRowMinHeight: CGFloat = 56 // source: assumed // MEASURE
    public static let emptyStateMaxWidth: CGFloat = 380 // source: assumed // MEASURE
    public static let onboardingColumn: CGFloat = 560 // source: assumed // MEASURE
    public static let brandMarkSidebar: CGFloat = 22 // source: assumed // MEASURE
    public static let brandMarkLarge: CGFloat = 56 // source: assumed // MEASURE
    public static let brandMarkAspect: CGFloat = 1002.0 / 378.0 // source: logo
    public static let pressScale: CGFloat = 0.98 // source: assumed // MEASURE
    public static let pageRise: CGFloat = 6 // source: assumed // MEASURE
}

public enum V1Flow {
    public static let pillHeight: CGFloat = 28 // source: assumed (scale) // MEASURE
    public static let idleSize = CGSize(width: 36, height: 6) // source: assumed // MEASURE
    public static let hoverWidth: CGFloat = 68 // source: wis (2.33 H), absolute assumed // MEASURE
    public static let activeWidth: CGFloat = 102 // source: wis (3.54 H), absolute assumed // MEASURE
    public static let buttonDiameter: CGFloat = 18 // source: wis (0.60 H), absolute assumed // MEASURE
    public static let buttonPadding: CGFloat = 5 // source: wis (0.19 H), absolute assumed // MEASURE
    public static let border: CGFloat = 1 // source: wis
    public static let tooltipHeight: CGFloat = 30 // source: wis (1.07 H), absolute assumed // MEASURE
    public static let tooltipGap: CGFloat = 4 // source: wis (0.14 H), absolute assumed // MEASURE
    public static let tooltipPaddingH: CGFloat = 12 // source: assumed // MEASURE

    public static let idleSquares = 14 // source: wis
    public static let squareSide: CGFloat = 1.75 // source: wis
    public static let squarePitch: CGFloat = 2.7 // source: wis
    public static let bars = 10 // source: wis
    public static let barWidth: CGFloat = 1.75 // source: wis
    public static let barPitch: CGFloat = 3.9 // source: wis
    public static let barMaxHeight: CGFloat = 11 // source: wis
    public static let glyphStroke: CGFloat = 1.5 // source: assumed // MEASURE

    public static let alertSize = CGSize(width: 378, height: 139) // source: wis, absolute assumed // MEASURE
    public static let alertRadius: CGFloat = 28 // source: wis (estimated) // MEASURE
    public static let alertPadding: CGFloat = 28 // source: wis, absolute assumed // MEASURE
    public static let alertIcon: CGFloat = 17 // source: wis, absolute assumed // MEASURE
    public static let alertButtonHeight: CGFloat = 32 // source: wis, absolute assumed // MEASURE
    public static let alertButtonRadius: CGFloat = 10 // source: wis, absolute assumed // MEASURE
    public static let alertButtonGap: CGFloat = 9.5 // source: wis, absolute assumed // MEASURE
    public static let alertButtonWidths: [CGFloat] = [135, 100] // source: wis, absolute assumed // MEASURE

    public static let toastSize = CGSize(width: 273, height: 47) // source: wis, absolute assumed // MEASURE
    public static let toastRadius: CGFloat = 14 // source: wis (estimated) // MEASURE
    public static let toastPaddingV: CGFloat = 9 // source: wis, absolute assumed // MEASURE
    public static let toastPaddingH: CGFloat = 25 // source: wis, absolute assumed // MEASURE
    public static let toastButtonSize = CGSize(width: 50, height: 30) // source: wis, absolute assumed // MEASURE
    public static let countdownRing: CGFloat = 16 // source: assumed // MEASURE
    public static let countdownStroke: CGFloat = 2 // source: assumed // MEASURE

    /// Room around the drawn shapes inside the fixed panel.
    public static let canvasMargin: CGFloat = 16 // source: assumed // MEASURE
    /// An alert grows past 139 for a long body; the panel reserves this much.
    public static let alertMaxHeight: CGFloat = 175 // source: assumed (139 plus two body lines) // MEASURE
    public static let alertTitleGap: CGFloat = 4 // source: assumed // MEASURE
    public static let alertBodyGap: CGFloat = 13 // source: assumed // MEASURE
    public static let alertClose: CGFloat = 12 // source: assumed // MEASURE
    public static let iconGap: CGFloat = 10 // source: assumed // MEASURE
    public static let toastMaxWidth: CGFloat = 420 // source: assumed // MEASURE
    public static let toastGap: CGFloat = 12 // source: assumed // MEASURE
    public static let keycap: CGFloat = 20 // source: assumed // MEASURE
    public static let keycapRadius: CGFloat = 5 // source: assumed // MEASURE
    public static let keycapPaddingH: CGFloat = 5 // source: assumed // MEASURE
    public static let keycapGap: CGFloat = 3 // source: assumed // MEASURE
    /// The white rounded square in the stop circle, and the X in the cancel circle.
    public static let stopGlyph: CGFloat = 7 // source: assumed // MEASURE
    public static let stopGlyphRadius: CGFloat = 1.5 // source: assumed // MEASURE
    public static let cancelGlyph: CGFloat = 7 // source: assumed // MEASURE
    public static let checkGlyph: CGFloat = 14 // source: assumed // MEASURE
    /// The idle pill's hover target: the hover pill's size, so the tiny pill is easy to reach.
    public static let hoverTargetSlop: CGFloat = 2 // source: assumed // MEASURE
}

public enum V1Motion {
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

public enum V1Type {
    public static let pageTitle = TextStyleToken(.serif, 500, size: 34, lineHeight: 40) // source: assumed // MEASURE
    public static let featureTitle = TextStyleToken(.serif, 500, size: 30, lineHeight: 36) // source: assumed // MEASURE
    public static let heading = TextStyleToken(.serif, 500, size: 22, lineHeight: 28) // source: assumed // MEASURE
    public static let body = TextStyleToken(.sans, 400, size: 16, lineHeight: 24) // source: wis (+1)
    public static let nav = TextStyleToken(.sans, 500, size: 16, lineHeight: 20) // source: wis (+1)
    public static let row = TextStyleToken(.sans, 400, size: 17, lineHeight: 24) // source: wis (+1)
    public static let meta = TextStyleToken(.sans, 400, size: 15, lineHeight: 20) // source: wis (+1)
    public static let section = TextStyleToken(.sans, 600, size: 12, lineHeight: 16, uppercase: true, tracking: 0.06) // source: assumed // MEASURE
    public static let button = TextStyleToken(.sans, 500, size: 16, lineHeight: 20) // source: wis (+1)
    public static let chip = TextStyleToken(.sans, 500, size: 16, lineHeight: 20) // source: wis (+1)
    public static let badge = TextStyleToken(.sans, 600, size: 14, lineHeight: 18) // source: assumed // MEASURE
    public static let keycap = TextStyleToken(.sans, 600, size: 13, lineHeight: 16) // source: assumed // MEASURE
    public static let flowText = TextStyleToken(.sans, 500, size: 13, lineHeight: 16) // source: assumed (scale) // MEASURE
    public static let flowAlert = TextStyleToken(.sans, 500, size: 14, lineHeight: 18) // source: assumed (scale) // MEASURE
    public static let minimumSize: Double = 11
    public static let scaleDefault = TypeTokens.scaleDefault
    public static let scaleLarge = TypeTokens.scaleLarge
    public static func nsFont(_ style: TextStyleToken, scale: Double = 1) -> NSFont { TypeTokens.nsFont(style, scale: scale) }
    public static func font(_ style: TextStyleToken, scale: Double = 1) -> Font { TypeTokens.font(style, scale: scale) }
}

extension Theme {
    /// v1 colors for the v1 components until U2 rebuilds them.
    public var v1: V1ThemeColors { increaseContrast ? (scheme == .dark ? V1ThemeColors.dark : V1ThemeColors.light).increasedContrast : (scheme == .dark ? V1ThemeColors.dark : V1ThemeColors.light) }
    public var v1flow: V1FlowBarColors { .standard }
}
