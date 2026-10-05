import SwiftUI

/// A settings group (§5.3): a section caption, then an `MCard` whose rows are divided by hairlines.
public struct MSettingsGroup<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: V1Spacing.xs) {
            if let title { MSectionCaption(title).padding(.leading, V1Spacing.xxs) }
            MCard(padding: 0) {
                // Each row draws the divider under it; the last one falls on the card's own border.
                VStack(alignment: .leading, spacing: 0) { content }
            }
            if let footer {
                Text(footer)
                    .textStyle(V1Type.meta)
                    .foregroundStyle(theme.v1.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, V1Spacing.xxs)
            }
        }
    }
}

/// A settings row: label and a one-line description on the left, the control on the right.
public struct MSettingsRow<Control: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let detail: String?
    let control: Control

    public init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: V1Spacing.md) {
            VStack(alignment: .leading, spacing: V1Spacing.xxs) {
                Text(title).textStyle(V1Type.body.weight(500)).foregroundStyle(theme.v1.textPrimary.color)
                if let detail {
                    Text(detail).textStyle(V1Type.meta).foregroundStyle(theme.v1.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, V1Spacing.lg)
        .padding(.vertical, V1Spacing.sm)
        .frame(minHeight: V1Hub.settingsRowMinHeight)
        .overlay(alignment: .bottom) { Hairline(\.borderDivider) }
        .accessibilityElement(children: .contain)
    }
}

/// A settings row whose whole width toggles its switch (§4).
public struct MToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    public var body: some View {
        MSettingsRow(title, detail: detail) {
            MToggle(isOn: $isOn, label: title)
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { isOn.toggle() } }
    }
}
