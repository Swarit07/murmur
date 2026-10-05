import CoreGraphics

// Geometry tokens (UI_REDESIGN.md v2 §3.4, §3.5, §4, §5). The boards are drawn at 1 CSS px = 1 pt, so
// board values are exact. Values on no board are tagged assumed and carry `// MEASURE`.

/// The spacing scale, in points (`space-1` … `space-12` in `Design/tokens.json`).
public enum Spacing {
    public static let s4: CGFloat = 4 // source: board
    public static let s8: CGFloat = 8 // source: board
    public static let s10: CGFloat = 10 // source: board
    public static let s12: CGFloat = 12 // source: board
    public static let s14: CGFloat = 14 // source: board
    public static let s16: CGFloat = 16 // source: board
    public static let s20: CGFloat = 20 // source: board
    public static let s24: CGFloat = 24 // source: board
    public static let s28: CGFloat = 28 // source: board
    public static let s32: CGFloat = 32 // source: board
    public static let s44: CGFloat = 44 // source: board
    public static let s56: CGFloat = 56 // source: board
}

/// Corner radii (`radius-*` in `Design/tokens.json`).
public enum Radius {
    public static let keycapSmall: CGFloat = 5 // source: board
    public static let keycap: CGFloat = 7 // source: board
    public static let control: CGFloat = 8 // source: board
    public static let button: CGFloat = 10 // source: board
    public static let card: CGFloat = 12 // source: board
    public static let cardLarge: CGFloat = 14 // source: board
    public static let feature: CGFloat = 16 // source: board
    public static let appTile: CGFloat = 6 // source: board
}

/// Borders and strokes.
public enum Stroke {
    public static let hairline: CGFloat = 1 // source: board
    public static let selected: CGFloat = 1.5 // source: board
    /// Increase Contrast thickens the selected-card ring (§6.3).
    public static let selectedIncreased: CGFloat = 2 // source: board
    public static let focusRing: CGFloat = 2 // source: board
    public static let focusGap: CGFloat = 2 // source: board
    public static let fieldHalo: CGFloat = 3 // source: board
    public static let keycapBottom: CGFloat = 2 // source: board
    public static let icon: CGFloat = 1.6 // source: board
    public static let appTileIcon: CGFloat = 1.8 // source: board
    public static let selectChevron: CGFloat = 2.4 // source: board
    public static let dash: CGFloat = 4 // source: assumed (dashed snippet box) // MEASURE
}

/// `shadow-float`: paper toasts and popovers only (§3.4). SwiftUI shadows have no spread, so the
/// −14 spread is approximated by a smaller blur radius.
public enum ShadowTokens {
    public static let floatY: CGFloat = 12 // source: board
    public static let floatBlur: CGFloat = 32 // source: board
    public static let floatSpread: CGFloat = -14 // source: board
    /// What SwiftUI gets: blur and spread folded into one radius.
    public static let floatRadius: CGFloat = (floatBlur + floatSpread) / 2 // source: derived // MEASURE
}

/// The Hub window and its pages (§3.4, §5.3).
public enum HubGeometry {
    public static let defaultWindow = CGSize(width: 1180, height: 740) // source: assumed // MEASURE
    public static let minimumWindow = CGSize(width: 880, height: 560) // source: assumed // MEASURE

    // Sidebar
    public static let sidebarWidth: CGFloat = 232 // source: board
    public static let sidebarPaddingTop: CGFloat = 14 // source: board
    public static let sidebarPaddingSide: CGFloat = 12 // source: board
    public static let sidebarItemGap: CGFloat = 2 // source: board
    /// The traffic lights' row: 16 pt high plus 2 pt padding above and below (the board's CSS box).
    public static let trafficLightsZone: CGFloat = 20 // source: board
    public static let brandMarkHeight: CGFloat = 22 // source: board
    public static let brandMarkInset: CGFloat = 22 // source: board (top and bottom)
    public static let brandMarkLeft: CGFloat = 10 // source: board
    public static let sidebarItemHeight: CGFloat = 36 // source: board
    public static let sidebarItemPaddingH: CGFloat = 10 // source: board
    public static let sidebarIcon: CGFloat = 18 // source: board
    public static let statusCardPadding: CGFloat = 12 // source: board

    // Content panel
    public static let panelInset: CGFloat = 8 // source: board (top, right, bottom)
    public static let topBarHeight: CGFloat = 48 // source: board
    public static let iconButton: CGFloat = 32 // source: board
    public static let iconButtonSmall: CGFloat = 28 // source: board
    public static let iconGlyph: CGFloat = 16 // source: board
    public static let bellDot: CGFloat = 7 // source: board
    public static let bellDotRing: CGFloat = 2 // source: board
    public static let pagePaddingTop: CGFloat = 44 // source: board
    public static let pagePaddingTopHome: CGFloat = 8 // source: board
    public static let pagePaddingSide: CGFloat = 56 // source: board
    public static let sectionGapHome: CGFloat = 28 // source: board
    public static let sectionGap: CGFloat = 22 // source: board
    public static let titleToSubtitle: CGFloat = 8 // source: board
    public static let subtitleMaxWidth: CGFloat = 520 // source: board
    public static let styleSubtitleMaxWidth: CGFloat = 560 // source: board
    public static let snippetsSectionGap: CGFloat = 24 // source: board
    public static let contentMaxWidth: CGFloat = 1000 // source: assumed (wide windows) // MEASURE

    // Buttons
    public static let buttonHeight: CGFloat = 40 // source: board
    public static let buttonPaddingH: CGFloat = 18 // source: board
    public static let buttonIcon: CGFloat = 15 // source: board
    /// A button with a leading icon is padded 12 on the icon's side and 16 on the other.
    public static let buttonPaddingIconLeading: CGFloat = 12 // source: board
    public static let buttonPaddingIconTrailing: CGFloat = 16 // source: board
    public static let buttonHeightSmall: CGFloat = 28 // source: board
    public static let buttonPaddingHSmall: CGFloat = 12 // source: board
    public static let linkUnderlineOffset: CGFloat = 4 // source: board

    // Controls
    public static let toggleSize = CGSize(width: 40, height: 24) // source: board
    public static let toggleSizeSmall = CGSize(width: 34, height: 20) // source: board
    public static let toggleKnobInset: CGFloat = 3 // source: board
    public static let segmentedPadding: CGFloat = 2 // source: board
    public static let segmentHeight: CGFloat = 30 // source: board
    public static let segmentPaddingH: CGFloat = 14 // source: board
    public static let segmentHeightSmall: CGFloat = 26 // source: board
    public static let segmentPaddingHSmall: CGFloat = 10 // source: board
    public static let fieldHeight: CGFloat = 36 // source: board
    public static let fieldPaddingH: CGFloat = 12 // source: assumed // MEASURE
    public static let searchIcon: CGFloat = 14 // source: board
    public static let selectHeight: CGFloat = 30 // source: board
    public static let selectChevron: CGFloat = 10 // source: board
    public static let keycapInlineHeight: CGFloat = 20 // source: board (18-22)
    public static let keycapHeight: CGFloat = 30 // source: board (28-32)
    public static let keycapPaddingH: CGFloat = 10 // source: board
    public static let keycapPaddingHInline: CGFloat = 6 // source: assumed // MEASURE
    public static let radio: CGFloat = 14 // source: board
    public static let radioSelectedRing: CGFloat = 4.5 // source: board
    public static let tagHeight: CGFloat = 20 // source: board
    public static let tagPaddingH: CGFloat = 7 // source: board
    public static let statHeight: CGFloat = 32 // source: board
    public static let statGroupPaddingH: CGFloat = 14 // source: board
    public static let statDivider = CGSize(width: 1, height: 14) // source: board
    public static let appTile: CGFloat = 24 // source: board
    public static let appTileIcon: CGFloat = 13 // source: board
    public static let chipHeight: CGFloat = 32 // source: board (onboarding language chips)
    public static let chipPaddingH: CGFloat = 12 // source: assumed // MEASURE
    public static let chipCheck: CGFloat = 12 // source: assumed // MEASURE

    // Cards
    public static let featurePadding: CGFloat = 28 // source: board
    public static let featureGap: CGFloat = 32 // source: board
    public static let featureSamplesWidth: CGFloat = 320 // source: board
    public static let featureSamplesGap: CGFloat = 8 // source: board
    public static let featureTextGap: CGFloat = 12 // source: board (title, paragraph, buttons; buttons add 8)
    public static let featureParagraphWidth: CGFloat = 400 // source: board
    public static let samplePadding = CGSize(width: 12, height: 10) // source: board
    public static let paperToastPadding = CGSize(width: 14, height: 10) // source: board
    public static let paperToastIcon: CGFloat = 16 // source: board
    public static let paperToastBottom: CGFloat = 22 // source: board
    public static let emptyStateMaxWidth: CGFloat = 380 // source: assumed // MEASURE
    public static let dialogWidth: CGFloat = 440 // source: assumed (Help & setup sheet) // MEASURE
    public static let popoverWidth: CGFloat = 300 // source: assumed (bell popover) // MEASURE
    public static let menuMinWidth: CGFloat = 200 // source: assumed // MEASURE

    // History rows (Home)
    public static let historyTimeColumn: CGFloat = 52 // source: board
    public static let historyTileColumn: CGFloat = 24 // source: board
    public static let historyMetaColumn: CGFloat = 112 // source: board
    public static let historyColumnGap: CGFloat = 14 // source: board
    public static let historyRowPadding = CGSize(width: 16, height: 13) // source: board

    // Dictionary rows
    public static let dictionaryRowHeight: CGFloat = 46 // source: board
    public static let dictionaryWordColumn: CGFloat = 200 // source: board
    public static let dictionaryTagColumn: CGFloat = 84 // source: board
    public static let dictionaryUsesColumn: CGFloat = 72 // source: board
    public static let dictionaryActionsColumn: CGFloat = 64 // source: board
    public static let dictionaryColumnGap: CGFloat = 12 // source: board
    public static let dictionaryWordField: CGFloat = 200 // source: board
    public static let dictionarySoundsField: CGFloat = 220 // source: board
    public static let editRowPadding = CGSize(width: 12, height: 10) // source: board
    public static let editFieldHeight: CGFloat = 34 // source: board
    public static let searchFieldWidth: CGFloat = 320 // source: board

    // Snippets, Style, Settings
    public static let snippetPadding: CGFloat = 16 // source: board
    public static let expansionPadding = CGSize(width: 12, height: 10) // source: board
    public static let styleCardPadding: CGFloat = 14 // source: board
    public static let styleCardGap: CGFloat = 10 // source: board
    public static let styleDividerMargin: CGFloat = 6 // source: board
    public static let snippetHeaderGap: CGFloat = 8 // source: board
    public static let snippetActionsGap: CGFloat = 2 // source: board
    public static let cleanupCardPadding = CGSize(width: 16, height: 14) // source: board
    public static let cardGap: CGFloat = 12 // source: board
    public static let settingsColumnGap: CGFloat = 24 // source: board
    public static let settingsRowPadding = CGSize(width: 14, height: 12) // source: board
    public static let infoCardPadding: CGFloat = 14 // source: board
    public static let arrowIcon: CGFloat = 14 // source: board
}

/// Onboarding (§5.4).
public enum OnboardingGeometry {
    public static let step = CGSize(width: 400, height: 560) // source: assumed // MEASURE
    public static let padding: CGFloat = 28 // source: board
    public static let gap: CGFloat = 20 // source: board
    public static let progress = CGSize(width: 120, height: 2) // source: board
    public static let wellHeight: CGFloat = 210 // source: board (200-220)
    public static let appIcon: CGFloat = 128 // source: board
    public static let holdKeyHeight: CGFloat = 56 // source: board
    public static let meterBars = 18 // source: board
    public static let meterBarWidth: CGFloat = 8 // source: board
    public static let meterBarGap: CGFloat = 4 // source: board
    public static let meterHeight: CGFloat = 64 // source: board
    public static let meterBarRadius: CGFloat = 4 // source: board
    public static let meterLowest: CGFloat = 0.30 // source: board (bar heights ramp 30-100%)
    public static let meterClayFrom: Double = 2.0 / 3 // source: board (lit bars in the last third are clay)
}

/// The Flow Bar (§3.5, §5.1).
public enum FlowGeometry {
    /// Gap between the bar and the Dock (or the bottom of the visible frame).
    public static let bottomMargin: CGFloat = 8 // source: board
    public static let idleSize = CGSize(width: 52, height: 12) // source: board
    public static let idleDash = CGSize(width: 20, height: 1.5) // source: board
    public static let idleDashRadius: CGFloat = 2 // source: board
    public static let hoverSize = CGSize(width: 76, height: 28) // source: board
    public static let stillWave = CGSize(width: 44, height: 12) // source: board
    public static let stillWaveLevel: Double = 0.35 // source: board
    public static let tooltipHeight: CGFloat = 28 // source: board
    public static let tooltipPaddingH: CGFloat = 10 // source: board
    public static let tooltipGap: CGFloat = 6 // source: board
    public static let tooltipKeyGap: CGFloat = 6 // source: board
    public static let inlineKeyHeight: CGFloat = 18 // source: board
    public static let inlineKeyPaddingH: CGFloat = 5 // source: board
    public static let inlineKeyBottom: CGFloat = 1.5 // source: board
    public static let pasteKeyHeight: CGFloat = 20 // source: board
    public static let pasteKeyGap: CGFloat = 3 // source: board
    public static let activeHeight: CGFloat = 36 // source: board
    public static let liveDot: CGFloat = 6 // source: board
    public static let waveHold = CGSize(width: 112, height: 22) // source: board
    public static let waveHandsFree = CGSize(width: 96, height: 22) // source: board
    public static let holdPaddingH: CGFloat = 16 // source: board
    public static let handsFreePaddingH: CGFloat = 6 // source: board
    public static let contentGap: CGFloat = 10 // source: board
    public static let roundButton: CGFloat = 24 // source: board
    public static let cancelGlyph: CGFloat = 12 // source: board
    public static let cancelStroke: CGFloat = 2.2 // source: board
    public static let stopSquare: CGFloat = 8 // source: board
    public static let stopSquareRadius: CGFloat = 2 // source: board
    public static let processingSize = CGSize(width: 144, height: 36) // source: board
    public static let dots = 5 // source: board
    public static let dot: CGFloat = 5 // source: board
    public static let dotGap: CGFloat = 3.75 // source: board
    public static let insertedPadding: CGFloat = 16 // source: board (right)
    public static let insertedPaddingLeft: CGFloat = 12 // source: board
    public static let insertedGap: CGFloat = 8 // source: board
    public static let check: CGFloat = 16 // source: board
    public static let checkStroke: CGFloat = 2 // source: board
    public static let cardRadius: CGFloat = 16 // source: board
    /// Card insets (top, trailing, bottom, leading) per state.
    public static let cancelledInsets = (top: CGFloat(8), trailing: CGFloat(8), bottom: CGFloat(8), leading: CGFloat(12)) // source: board
    public static let errorInsets = (top: CGFloat(6), trailing: CGFloat(6), bottom: CGFloat(6), leading: CGFloat(12)) // source: board
    public static let pasteHeight: CGFloat = 40 // source: board
    public static let pastePadding: CGFloat = 14 // source: board (right)
    public static let pastePaddingLeft: CGFloat = 12 // source: board
    public static let noAudioWidth: CGFloat = 276 // source: board
    public static let noAudioPadding: CGFloat = 10 // source: board
    public static let cardIcon: CGFloat = 16 // source: board
    public static let buttonHeight: CGFloat = 28 // source: board (26-28)
    public static let buttonHeightSmall: CGFloat = 26 // source: board
    public static let buttonRadius: CGFloat = 8 // source: board
    public static let buttonPaddingH: CGFloat = 10 // source: board
    public static let buttonIcon: CGFloat = 12 // source: board
    public static let buttonIconGap: CGFloat = 6 // source: board
    public static let buttonGap: CGFloat = 6 // source: board (between toast buttons in a row)
    public static let cancelledLabelTrail: CGFloat = 4 // source: board
    public static let noAudioInset: CGFloat = 2 // source: board (icon row)
    public static let timerWidth: CGFloat = 30 // source: assumed (room for "0:07" in mono 11) // MEASURE
    /// A card's text column stops here; longer SPEC messages truncate.
    public static let cardTextMaxWidth: CGFloat = 260 // source: assumed // MEASURE
    public static let textGap: CGFloat = 1 // source: assumed (title to sub-line) // MEASURE
    public static let ring: CGFloat = 22 // source: board
    public static let ringStroke: CGFloat = 2 // source: board
    public static let ring1pt: CGFloat = 1 // source: board (every surface's inset edge)
    /// Room around the drawn shapes inside the fixed panel.
    public static let canvasMargin: CGFloat = 16 // source: assumed // MEASURE
    /// The panel's fixed width and the tallest card it reserves (the no-audio alert with two lines).
    public static let canvasCardWidth: CGFloat = 420 // source: assumed // MEASURE
    public static let canvasCardHeight: CGFloat = 96 // source: assumed // MEASURE
    /// The pill's hover target extends this far past its drawn edge.
    public static let hoverTargetSlop: CGFloat = 2 // source: assumed // MEASURE
}

/// The menu bar glyph and its states (§3.6).
public enum MenuBarGeometry {
    public static let glyph: CGFloat = 18 // source: board
    public static let recordingDot: CGFloat = 5 // source: board
    public static let recordingGap: CGFloat = 4 // source: board
    public static let processingDot: CGFloat = 2.5 // source: board
    public static let processingDots = 5 // source: board
    public static let processingGap: CGFloat = 3 // source: assumed (glyph to first dot) // MEASURE
    public static let processingDotGap: CGFloat = 1.5 // source: assumed // MEASURE
    public static let badge: CGFloat = 9 // source: board
    public static let badgeCutout: CGFloat = 1.5 // source: board
    public static let badgeMarkSize: CGFloat = 7 // source: board (bold "!")
}
