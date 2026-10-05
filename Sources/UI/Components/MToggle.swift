import SwiftUI

/// A 40 × 24 switch (§4). Off: hover-fill track with a control border. On: clay track. White knob that
/// springs across. Use inside a row whose whole width toggles it (`MSettingsRow`).
public struct MToggle: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(isOn: Binding<Bool>, label: String) {
        _isOn = isOn
        self.label = label
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let size = HubGeometry.toggleSize
        let knob = size.height - HubGeometry.toggleKnobInset * 2
        let track = Capsule(style: .continuous)
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                track.fill(isOn ? c.accentClay.color : c.bgHover.color)
                    .overlay { if !isOn { track.strokeBorder(c.borderControl.color, lineWidth: HubGeometry.hairline) } }
                Circle()
                    .fill(c.buttonText.color)
                    .frame(width: knob, height: knob)
                    .padding(HubGeometry.toggleKnobInset)
            }
            .frame(width: size.width, height: size.height)
            .opacity(state == .disabled ? OpacityTokens.disabled : 1)
            // Reduce Motion: the knob jumps and only the track color fades.
            .animation(theme.motion.reduce ? theme.motion.easeInOut(MotionTokens.reducedFade) : theme.motion.spring(MotionTokens.toggleKnob), value: isOn)
            .transaction { if theme.motion.reduce { $0.disablesAnimations = false } }
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: size.height / 2)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
