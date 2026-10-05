import SwiftUI

/// A dropdown: a secondary-button-shaped control showing the current choice and a chevron. The list
/// that opens is the system menu (menus stay native, like the menu bar's).
public struct MSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    let label: String

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ label: String, selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.label = label
        _selection = selection
        self.options = options
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.v1
        let shape = RoundedRectangle(cornerRadius: V1Hub.buttonRadius, style: .continuous)
        let current = options.first { $0.value == selection }?.label ?? ""
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].label) { selection = options[i].value }
            }
        } label: {
            HStack(spacing: V1Spacing.xs) {
                Text(current).textStyle(V1Type.button.weight(400)).lineLimit(1)
                Spacer(minLength: V1Spacing.xs)
                IconView(.chevronDown, size: V1Hub.checkGlyph, color: c.textSecondary.color)
            }
            .foregroundStyle(state == .disabled ? c.textDisabled.color : c.textPrimary.color)
            .padding(.horizontal, V1Spacing.sm)
            .frame(minWidth: V1Hub.menuMinWidth)
            .frame(height: V1Hub.buttonHeight)
            .background(shape.fill(state == .hover ? c.bgHover.color : c.bgCard.color))
            .overlay(shape.strokeBorder(c.borderControl.color, lineWidth: V1Hub.hairline))
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: V1Hub.buttonRadius)
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }
}
