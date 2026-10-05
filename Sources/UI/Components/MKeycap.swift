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
        let c = theme.v1
        let shape = RoundedRectangle(cornerRadius: V1Hub.keycapRadius, style: .continuous)
        Text(text)
            .textStyle(V1Type.keycap)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isEnabled ? c.textPrimary.color : c.textDisabled.color)
            .padding(.horizontal, V1Spacing.xs)
            .frame(minWidth: V1Hub.keycapMin, minHeight: V1Hub.keycapMin)
            .background(shape.fill(c.bgCard.color))
            .overlay(shape.strokeBorder(c.borderControl.color, lineWidth: V1Hub.hairline))
    }
}

/// A shortcut shown as key caps: "fn" "Space".
public struct MShortcut: View {
    let keys: [String]

    public init(_ keys: [String]) {
        self.keys = keys
    }

    public var body: some View {
        HStack(spacing: V1Spacing.xxs) {
            ForEach(keys.indices, id: \.self) { MKeycap(keys[$0]) }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
