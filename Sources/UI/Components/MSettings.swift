import SwiftUI

/// A settings group (§5.3): a mono caption, then a list container (radius 12) of rows.
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
        VStack(alignment: .leading, spacing: Spacing.s10) {
            if let title { MCaption(title) }
            // Each row draws the divider under it; the last one falls on the container's own ring.
            MListContainer { content }
            if let footer {
                Text(footer)
                    .textStyle(TypeTokens.hint)
                    .foregroundStyle(theme.colors.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A settings row (§5.3): `label` and a `hint` on the left, the control on the right, padding 12 × 14.
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
        let c = theme.colors
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.s16) {
                VStack(alignment: .leading, spacing: Spacing.s4 / 2) {
                    Text(title).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                    if let detail {
                        Text(detail).textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            .padding(.horizontal, HubGeometry.settingsRowPadding.width)
            .padding(.vertical, HubGeometry.settingsRowPadding.height)
            Hairline()
        }
        .accessibilityElement(children: .contain)
    }
}

/// A settings row whose control is a switch; the whole row toggles it.
public struct MToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    public init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    public var body: some View {
        MSettingsRow(title, detail: detail) { MToggle(isOn: $isOn, label: title) }
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
    }
}

/// The info card under a settings column (§5.3): sunken, radius 12, padding 14, an icon, a label and a
/// hint.
public struct MInfoCard: View {
    @Environment(\.theme) private var theme
    let icon: Icon
    let title: String
    let detail: String

    public init(_ title: String, detail: String, icon: Icon = .shield) {
        self.title = title
        self.detail = detail
        self.icon = icon
    }

    public var body: some View {
        let c = theme.colors
        HStack(alignment: .top, spacing: Spacing.s12) {
            IconView(icon, size: HubGeometry.iconGlyph, color: c.textPrimary.color)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(title).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                Text(detail).textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(HubGeometry.infoCardPadding)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(c.bgSunken.color))
        .accessibilityElement(children: .combine)
    }
}
