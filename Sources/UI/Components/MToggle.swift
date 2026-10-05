import SwiftUI

/// A switch (§4): 40 × 24 (small 34 × 20). On: ink track with an `on-ink` knob. Off: no fill, a 1 pt
/// `border-control` ring and a stone knob. The knob moves on a spring; the whole row can be the target.
public struct MToggle: View {
    public enum Size: Sendable { case regular, small }
    @Binding var isOn: Bool
    let label: String
    let size: Size

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(isOn: Binding<Bool>, label: String, size: Size = .regular) {
        _isOn = isOn
        self.label = label
        self.size = size
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let track = size == .small ? HubGeometry.toggleSizeSmall : HubGeometry.toggleSize
        let knob = track.height - HubGeometry.toggleKnobInset * 2
        let disabled = state == .disabled
        let shape = Capsule(style: .circular)
        ZStack(alignment: isOn ? .trailing : .leading) {
            shape.fill(isOn ? (disabled ? c.fillSelected.color : state == .hover ? c.inkFillHover.color : c.inkFill.color) : (state == .hover ? c.fillHover.color : .clear))
            if !isOn { shape.strokeBorder(disabled ? c.borderDivider.color : c.borderControl.color, lineWidth: Stroke.hairline) }
            Circle()
                .fill(isOn ? (disabled ? c.textTertiary.color : c.onInk.color) : (disabled ? c.fillSelected.color : c.stone.color))
                .frame(width: knob, height: knob)
                .padding(HubGeometry.toggleKnobInset)
        }
        .frame(width: track.width, height: track.height)
        .contentShape(shape)
        .onTapGesture { if isEnabled { isOn.toggle() } }
        .animation(theme.motion.spring(MotionTokens.toggleKnob), value: isOn)
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { isOn.toggle(); return .handled }
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: track.height / 2)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOn.toggle() }
    }
}
