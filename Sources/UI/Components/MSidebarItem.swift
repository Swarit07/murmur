import SwiftUI

/// A sidebar row (§4): 38 high, radius 8, 16-point icon with a 13-point gap, nav type. Selected: the
/// hover fill; hover: the hover fill at half strength. Text color never changes.
public struct MSidebarItem: View {
    let icon: Icon
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ title: String, icon: Icon, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: HubGeometry.sidebarItemRadius, style: .continuous)
        let ink = state == .disabled ? c.textDisabled.color : c.textPrimary.color
        Button(action: action) {
            HStack(spacing: HubGeometry.sidebarIconGap) {
                IconView(icon, size: HubGeometry.sidebarIcon, color: ink)
                Text(title).textStyle(TypeTokens.nav).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, HubGeometry.sidebarItemInset)
            .frame(height: HubGeometry.sidebarItemHeight)
            .background(shape.fill(selected ? c.bgHover.color : (state == .hover ? c.bgHover.color.opacity(OpacityTokens.hoverHalf) : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: HubGeometry.sidebarItemRadius)
        .animation(theme.motion.easeOut(MotionTokens.hover), value: state)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
