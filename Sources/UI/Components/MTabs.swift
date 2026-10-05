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
        let c = theme.v1
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: false)
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let selected = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .textStyle(selected ? V1Type.button : V1Type.button.weight(400))
                        .foregroundStyle(state == .disabled ? c.textDisabled.color : (selected ? c.textPrimary.color : c.textSecondary.color))
                        .lineLimit(1)
                        .padding(.horizontal, V1Spacing.md)
                        .frame(maxWidth: .infinity)
                        .frame(height: V1Hub.tabHeight - V1Hub.tabInset * 2)
                        .background {
                            if selected {
                                Capsule(style: .circular)
                                    .fill(c.bgPanel.color)
                                    .overlay(Capsule(style: .circular).strokeBorder(c.borderPanel.color, lineWidth: V1Hub.hairline))
                                    // The pill slides between tabs; under Reduce Motion it cross-fades in place.
                                    .matchedGeometryEffect(id: theme.motion.reduce ? "selection-\(i)" : "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(V1Hub.tabInset)
        .background(Capsule(style: .circular).fill(c.bgChip.color))
        .animation(theme.motion.spring(V1Motion.tabsSelect), value: selection)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(state == .focused, radius: V1Hub.tabHeight / 2)
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
