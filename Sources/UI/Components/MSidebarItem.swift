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
        let c = theme.v1
        let shape = RoundedRectangle(cornerRadius: V1Hub.sidebarItemRadius, style: .continuous)
        let ink = state == .disabled ? c.textDisabled.color : c.textPrimary.color
        Button(action: action) {
            HStack(spacing: V1Hub.sidebarIconGap) {
                IconView(icon, size: V1Hub.sidebarIcon, color: ink)
                Text(title).textStyle(V1Type.nav).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, V1Hub.sidebarItemInset)
            .frame(height: V1Hub.sidebarItemHeight)
            .background(shape.fill(selected ? c.bgHover.color : (state == .hover ? c.bgHover.color.opacity(V1Opacity.hoverHalf) : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: V1Hub.sidebarItemRadius)
        .animation(theme.motion.easeOut(V1Motion.hover), value: state)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
