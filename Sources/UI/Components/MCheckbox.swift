import SwiftUI

/// A square checkbox with a clay check, for lists of choices such as languages.
public struct MCheckbox: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.v1
        let box = RoundedRectangle(cornerRadius: V1Hub.checkboxRadius, style: .continuous)
        Button { isOn.toggle() } label: {
            HStack(spacing: V1Spacing.xs) {
                ZStack {
                    box.fill(isOn ? c.accentClay.color : (state == .hover ? c.bgHover.color : c.bgCard.color))
                    if !isOn { box.strokeBorder(c.borderControl.color, lineWidth: V1Hub.hairline) }
                    if isOn { IconView(.check, size: V1Hub.checkGlyph, color: c.buttonText.color) }
                }
                .frame(width: V1Hub.checkbox, height: V1Hub.checkbox)
                .focusRing(state == .focused, radius: V1Hub.checkboxRadius)
                Text(label)
                    .textStyle(V1Type.body)
                    .foregroundStyle(state == .disabled ? c.textDisabled.color : c.textPrimary.color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Checked" : "Unchecked")
        .accessibilityAddTraits(.isToggle)
    }
}
