import SwiftUI

/// A key cap for shortcuts (§4): "fn", "⌃", "Space".
public struct MKeycap: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: HubGeometry.keycapRadius, style: .continuous)
        Text(text)
            .textStyle(TypeTokens.keycap)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isEnabled ? c.textPrimary.color : c.textDisabled.color)
            .padding(.horizontal, Spacing.xs)
            .frame(minWidth: HubGeometry.keycapMin, minHeight: HubGeometry.keycapMin)
            .background(shape.fill(c.bgCard.color))
            .overlay(shape.strokeBorder(c.borderControl.color, lineWidth: HubGeometry.hairline))
    }
}

/// A shortcut shown as key caps: "fn" "Space".
public struct MShortcut: View {
    let keys: [String]

    public init(_ keys: [String]) {
        self.keys = keys
    }

    public var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(keys.indices, id: \.self) { MKeycap(keys[$0]) }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
