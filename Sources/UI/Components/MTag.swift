import SwiftUI

/// A tag (§4): 20 high, radius 5, padding 0 × 7, mono 10. Outline ("added"): a 1 pt ink ring. Filled
/// ("learned"): the sunken fill.
public struct MTag: View {
    public enum Kind: Sendable { case outline, filled }
    let text: String
    let kind: Kind

    @Environment(\.theme) private var theme

    public init(_ text: String, kind: Kind = .outline) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.keycapSmall, style: .continuous)
        Text(text)
            .textStyle(TypeTokens.tag)
            .foregroundStyle(c.textSecondary.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, HubGeometry.tagPaddingH)
            .frame(height: HubGeometry.tagHeight)
            .background(shape.fill(kind == .filled ? c.bgSunken.color : .clear))
            .overlay { if kind == .outline { shape.strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline) } }
    }
}

/// The Home stat strip (§4): a 32 pt pill on the chip fill, mono stats divided by short ink lines. A
/// stat that can't be computed is left out.
public struct MStatStrip: View {
    let stats: [String]

    @Environment(\.theme) private var theme

    public init(_ stats: [String?]) {
        self.stats = stats.compactMap { $0 }
    }

    public var body: some View {
        let c = theme.colors
        if !stats.isEmpty {
            HStack(spacing: 0) {
                ForEach(stats.indices, id: \.self) { i in
                    if i > 0 {
                        Rectangle().fill(c.edgeToast.color).frame(width: HubGeometry.statDivider.width, height: HubGeometry.statDivider.height)
                    }
                    Text(stats[i])
                        .textStyle(TypeTokens.stat)
                        .foregroundStyle(c.textPrimary.color)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, HubGeometry.statGroupPaddingH)
                }
            }
            .frame(height: HubGeometry.statHeight)
            .background(Capsule(style: .circular).fill(c.fillChip.color))
            .accessibilityElement(children: .combine)
        }
    }
}

/// The app a dictation went into (§4): a 24 pt tile, radius 6, a 1 pt ink ring, a 13 pt icon.
public struct MAppTile: View {
    let icon: Icon
    let faint: Bool

    @Environment(\.theme) private var theme

    /// `faint`: the silent-audio row's mic tile, ring at 12% (`edgePanel`) and a tertiary glyph.
    public init(_ icon: Icon, faint: Bool = false) {
        self.icon = icon
        self.faint = faint
    }

    public var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.appTile, style: .continuous)
        IconView(icon, size: HubGeometry.appTileIcon, color: faint ? c.textTertiary.color : c.textPrimary.color, gridStroke: Stroke.appTileIcon)
            .frame(width: HubGeometry.appTile, height: HubGeometry.appTile)
            .overlay(shape.strokeBorder(faint ? c.edgePanel.color : c.edgeStrong.color, lineWidth: Stroke.hairline))
            .accessibilityHidden(true)
    }
}
