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
        let c = theme.colors
        let box = RoundedRectangle(cornerRadius: HubGeometry.checkboxRadius, style: .continuous)
        Button { isOn.toggle() } label: {
            HStack(spacing: Spacing.xs) {
                ZStack {
                    box.fill(isOn ? c.accentClay.color : (state == .hover ? c.bgHover.color : c.bgCard.color))
                    if !isOn { box.strokeBorder(c.borderControl.color, lineWidth: HubGeometry.hairline) }
                    if isOn { IconView(.check, size: HubGeometry.checkGlyph, color: c.buttonText.color) }
                }
                .frame(width: HubGeometry.checkbox, height: HubGeometry.checkbox)
                .focusRing(state == .focused, radius: HubGeometry.checkboxRadius)
                Text(label)
                    .textStyle(TypeTokens.body)
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
