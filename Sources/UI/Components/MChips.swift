import SwiftUI

/// A pill of up to three stats separated by hairlines (§4): "🔥 3 days · 🚀 1,204 words · 👋 143 wpm".
/// The three glyphs are the only emoji in the UI (rule 10).
public struct MStatChip: View {
    @Environment(\.theme) private var theme
    let items: [(glyph: String, text: String)]

    public init(_ items: [(glyph: String, text: String)]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 {
                    Hairline(\.borderDivider, vertical: true).frame(height: HubGeometry.statChipSeparatorHeight)
                }
                HStack(spacing: Spacing.xs) {
                    Text(items[i].glyph).textStyle(TypeTokens.chip)
                    Text(items[i].text).textStyle(TypeTokens.chip).foregroundStyle(theme.colors.textPrimary.color).monospacedDigit()
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Spacing.sm)
            }
        }
        .fixedSize()
        .frame(height: HubGeometry.statChipHeight)
        .background(Capsule().fill(theme.colors.bgChip.color))
        .accessibilityElement(children: .combine)
    }
}

/// A badge (§4): `.plan` clay with white text ("Personal"), `.neutral`, `.soft` clay tint.
public struct MBadge: View {
    public enum Kind: Sendable { case plan, neutral, soft }
    @Environment(\.theme) private var theme
    let text: String
    let kind: Kind

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        let c = theme.colors
        let (fill, ink): (Color, Color) = switch kind {
        case .plan: (c.accentClay.color, c.buttonText.color)
        case .neutral: (c.bgHover.color, c.textBody.color)
        case .soft: (c.accentClayTint.color, c.accentClayText.color)
        }
        Text(text)
            .textStyle(TypeTokens.badge)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, Spacing.xs)
            .frame(height: HubGeometry.badgeHeight)
            .background(RoundedRectangle(cornerRadius: HubGeometry.badgeRadius, style: .continuous).fill(fill))
            .overlay {
                if kind == .soft && theme.increaseContrast {
                    RoundedRectangle(cornerRadius: HubGeometry.badgeRadius, style: .continuous)
                        .strokeBorder(c.accentClay.color, lineWidth: HubGeometry.selectedBorder)
                }
            }
    }
}
