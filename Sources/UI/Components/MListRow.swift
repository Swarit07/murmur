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

/// A list row (§4): its content, then trailing action buttons that fade in over 100 ms on hover, on a
/// `fill-hover` background. `trailing` shows when the actions don't (a word count, "48 uses").
public struct MListRow<Content: View, Trailing: View>: View {
    let actions: [RowAction]
    let selected: Bool
    let padding: CGSize
    let minHeight: CGFloat?
    let content: Content
    let trailing: Trailing

    @Environment(\.theme) private var theme
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false

    public init(actions: [RowAction] = [], selected: Bool = false, padding: CGSize = HubGeometry.historyRowPadding, minHeight: CGFloat? = nil,
                @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.actions = actions
        self.selected = selected
        self.padding = padding
        self.minHeight = minHeight
        self.content = content()
        self.trailing = trailing()
    }

    public var body: some View {
        let c = theme.colors
        let active = hovering || forced == .hover || selected
        HStack(alignment: .center, spacing: HubGeometry.historyColumnGap) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                trailing.opacity(active && !actions.isEmpty ? 0 : 1)
                HStack(spacing: Spacing.s4) {
                    ForEach(actions) { MIconButton($0.icon, label: $0.label, size: .small, action: $0.action) }
                }
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
            }
            .animation(theme.motion.easeOut(MotionTokens.rowActionsFade), value: active)
        }
        .padding(.horizontal, padding.width)
        .padding(.vertical, padding.height)
        .frame(minHeight: minHeight)
        .background(active ? c.fillHover.color : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// A bordered list (§4): radius 12, a 1 pt ink ring, rows divided by `border-divider`.
public struct MList<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    @Environment(\.theme) private var theme
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let row: (Data.Element) -> Row

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.id = id
        self.row = row
    }

    public var body: some View {
        let first = data.first.map { $0[keyPath: id] }
        MListContainer {
            ForEach(data, id: id) { element in
                if element[keyPath: id] != first { Hairline() }
                row(element)
            }
        }
    }
}

/// The list's container alone, for rows laid out by hand (put a `Hairline()` between them).
public struct MListContainer<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(spacing: 0) { content }
            .background(shape.fill(theme.colors.bgPanel.color))
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.colors.edgeList.color, lineWidth: Stroke.hairline))
    }
}
