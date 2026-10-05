import SwiftUI

/// One action revealed on a row's hover.
public struct RowAction: Identifiable {
    public let icon: Icon
    public let label: String
    public let action: () -> Void
    public var id: String { label }

    public init(_ icon: Icon, _ label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }
}

/// A History-style row (§4): time column, then the text column; hover reveals trailing icon buttons
/// with a 100 ms fade. A silent row (the audio had no speech) shows disabled text and an info icon
/// that says so.
public struct MListRow<Detail: View>: View {
    let time: String
    let text: String
    let silent: Bool
    let selected: Bool
    let actions: [RowAction]
    let detail: Detail

    @Environment(\.theme) private var theme
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false

    public init(time: String, text: String, silent: Bool = false, selected: Bool = false, actions: [RowAction] = [],
                @ViewBuilder detail: () -> Detail = { EmptyView() }) {
        self.time = time
        self.text = text
        self.silent = silent
        self.selected = selected
        self.actions = actions
        self.detail = detail()
    }

    public var body: some View {
        let c = theme.colors
        let showActions = hovering || forced == .hover || selected
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(time)
                .textStyle(TypeTokens.meta)
                .foregroundStyle(c.textSecondary.color)
                .monospacedDigit()
                .frame(width: HubGeometry.rowTextColumn - HubGeometry.rowTimeColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(text)
                        .textStyle(TypeTokens.row)
                        .foregroundStyle(silent ? c.textDisabled.color : c.textBody.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if silent {
                        IconView(.info, size: HubGeometry.iconGlyph, color: c.textSecondary.color)
                            .help("Audio is silent.")
                            .accessibilityLabel("Audio is silent.")
                    }
                }
                .frame(maxWidth: HubGeometry.rowTextWrap, alignment: .leading)
                detail
            }
            Spacer(minLength: Spacing.md)
            HStack(spacing: Spacing.xxs) {
                ForEach(actions) { MIconButton($0.icon, label: $0.label, action: $0.action) }
            }
            .opacity(showActions ? 1 : 0)
            .animation(theme.motion.easeOut(MotionTokens.rowActionsFade), value: showActions)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        }
        .padding(.leading, HubGeometry.rowTimeColumn)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.md)
        .frame(minHeight: HubGeometry.rowHeight)
        .background(selected ? c.bgHover.color : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// A bordered list container with dividers between rows (§3.4).
public struct MList<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubGeometry.listRadius, style: .continuous)
        VStack(spacing: 0) { content }
            .background(shape.fill(theme.colors.bgCard.color))
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.colors.borderPanel.color, lineWidth: HubGeometry.hairline))
    }
}
