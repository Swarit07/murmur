import SwiftUI

/// A segmented control (§4), used for tabs and for value pickers: a `fill-selected` track (radius 10,
/// padding 2); the selected segment is paper with a 1 pt ink ring and slides to the selection
/// (`matchedGeometryEffect`); arrow keys move it. Small: 26 high, 12 pt.
public struct MSegmented<Value: Hashable>: View {
    public enum Size: Sendable { case regular, small }
    @Binding var selection: Value
    let items: [(value: Value, label: String)]
    let size: Size
    let label: String

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @Namespace private var namespace
    @FocusState private var focused: Bool

    public init(_ label: String = "", selection: Binding<Value>, items: [(value: Value, label: String)], size: Size = .regular) {
        self.label = label
        _selection = selection
        self.items = items
        self.size = size
    }

    public var body: some View {
        let c = theme.colors
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: false)
        let small = size == .small
        let segmentRadius = small ? Radius.keycap : Radius.control
        let segment = RoundedRectangle(cornerRadius: segmentRadius, style: .continuous)
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let selected = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .textStyle(small ? TypeTokens.controlSmall : TypeTokens.control)
                        .foregroundStyle(state == .disabled ? c.textTertiary.color : (selected ? c.textPrimary.color : c.textSecondary.color))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, small ? HubGeometry.segmentPaddingHSmall : HubGeometry.segmentPaddingH)
                        .frame(height: small ? HubGeometry.segmentHeightSmall : HubGeometry.segmentHeight)
                        .background {
                            if selected {
                                segment
                                    .fill(c.bgPanel.color)
                                    .insetRing(c.edgeList.color, radius: segmentRadius)
                                    // The segment slides between items; under Reduce Motion it cross-fades in place.
                                    .matchedGeometryEffect(id: theme.motion.reduce ? "selection-\(i)" : "selection", in: namespace)
                            }
                        }
                        .contentShape(segment)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(HubGeometry.segmentedPadding)
        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(c.fillSelected.color))
        .animation(theme.motion.spring(MotionTokens.segmentedSelect), value: selection)
        .fixedSize()
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(state == .focused, radius: Radius.button)
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    func move(_ delta: Int) -> KeyPress.Result {
        guard let i = items.firstIndex(where: { $0.value == selection }) else { return .ignored }
        selection = items[min(max(0, i + delta), items.count - 1)].value
        return .handled
    }
}
