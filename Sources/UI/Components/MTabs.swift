import SwiftUI

/// A pill row of tabs on the chip fill (§4). The selected pill (panel fill, hairline border) slides to
/// the selection; arrow keys move it.
public struct MTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, label: String)]

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @Namespace private var namespace
    @FocusState private var focused: Bool

    public init(selection: Binding<Value>, items: [(value: Value, label: String)]) {
        _selection = selection
        self.items = items
    }

    public var body: some View {
        let c = theme.colors
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: false)
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let selected = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .textStyle(selected ? TypeTokens.button : TypeTokens.button.weight(400))
                        .foregroundStyle(state == .disabled ? c.textDisabled.color : (selected ? c.textPrimary.color : c.textSecondary.color))
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.md)
                        .frame(maxWidth: .infinity)
                        .frame(height: HubGeometry.tabHeight - HubGeometry.tabInset * 2)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(c.bgPanel.color)
                                    .overlay(Capsule(style: .continuous).strokeBorder(c.borderPanel.color, lineWidth: HubGeometry.hairline))
                                    // The pill slides between tabs; under Reduce Motion it cross-fades in place.
                                    .matchedGeometryEffect(id: theme.motion.reduce ? "selection-\(i)" : "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(HubGeometry.tabInset)
        .background(Capsule(style: .continuous).fill(c.bgChip.color))
        .animation(theme.motion.spring(MotionTokens.tabsSelect), value: selection)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(state == .focused, radius: HubGeometry.tabHeight / 2)
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
    }

    func move(_ delta: Int) -> KeyPress.Result {
        guard let i = items.firstIndex(where: { $0.value == selection }) else { return .ignored }
        let next = min(max(0, i + delta), items.count - 1)
        selection = items[next].value
        return .handled
    }
}
