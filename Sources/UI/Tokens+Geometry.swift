import CoreGraphics

// Geometry tokens (UI_REDESIGN.md §3.4, §3.5). Hub sizes were measured from the reference screenshots
// at 1.333 px per pt (macOS traffic lights as the anchor). The Flow Bar's proportions are measured,
// its absolute sizes assume a 28 pt pill (no OS anchor in those screenshots), so they carry MEASURE.

/// The spacing scale, in points.
public enum Spacing {
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

/// The Hub window.
public enum HubGeometry {
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

/// The Flow Bar. H is the pill height; every absolute size assumes H = 28 (§3.5).
public enum FlowGeometry {
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
