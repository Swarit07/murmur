import SwiftUI

/// A choice chip (onboarding languages, §5.4): a 32 pt pill. Unselected: a 1 pt ink ring. Selected:
/// solid ink with an `on-ink` check.
public struct MChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let shape = Capsule(style: .circular)
        let ink = selected ? c.onInk.color : c.textPrimary.color
        Button(action: action) {
            HStack(spacing: Spacing.s4 + Spacing.s4 / 2) {
                if selected { IconView(.check, size: HubGeometry.chipCheck, color: ink, gridStroke: IconTokens.strokeSmall) }
                Text(title).textStyle(TypeTokens.hint.weight(500)).foregroundStyle(ink).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, HubGeometry.chipPaddingH)
            .frame(height: HubGeometry.chipHeight)
            .background(shape.fill(selected ? (state == .hover ? c.inkFillHover.color : c.inkFill.color) : (state == .hover ? c.fillHover.color : .clear)))
            .overlay { if !selected { shape.strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: HubGeometry.chipHeight / 2)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
