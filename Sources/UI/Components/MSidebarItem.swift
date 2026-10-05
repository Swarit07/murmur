import SwiftUI

/// A sidebar row (§3.4): 36 high, radius 8, padding 0 × 10, an 18 pt icon, 10 gap, `nav` type.
/// Selected: `fill-selected` and weight 500. Hover: `fill-hover`.
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
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let ink = state == .disabled ? c.textTertiary.color : c.textPrimary.color
        Button(action: action) {
            HStack(spacing: Spacing.s10) {
                IconView(icon, size: HubGeometry.sidebarIcon, color: ink)
                Text(title).textStyle(selected ? TypeTokens.nav.weight(500) : TypeTokens.nav).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HubGeometry.sidebarItemPaddingH)
            .frame(height: HubGeometry.sidebarItemHeight)
            .background(shape.fill(selected ? c.fillSelected.color : (state == .hover || state == .pressed ? c.fillHover.color : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: Radius.control)
        .animation(theme.motion.easeOut(MotionTokens.hover), value: state)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The status card at the foot of the sidebar (§3.4): radius 12, padding 12, paper, a 1 pt ink ring.
/// "Ready" with an "on-device" tag, "Hold [key] to dictate" with an inline key cap, and the mic name.
public struct MStatusCard: View {
    @Environment(\.theme) private var theme
    let title: String
    let tag: String
    let hotkey: String
    let microphone: String
    let live: Bool

    /// `live`: a dictation is recording (the title gains the live dot).
    public init(title: String, tag: String = "on-device", hotkey: String, microphone: String, live: Bool = false) {
        self.title = title
        self.tag = tag
        self.hotkey = hotkey
        self.microphone = microphone
        self.live = live
    }

    public var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(spacing: Spacing.s8) {
                if live { Circle().fill(theme.flow.flowLive.color).frame(width: FlowGeometry.liveDot, height: FlowGeometry.liveDot) }
                Text(title).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                Spacer(minLength: Spacing.s4)
                Text(tag).textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color)
            }
            HStack(spacing: Spacing.s8) {
                Text("Hold").textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
                MKeycap(hotkey, size: .inline)
                Text("to dictate").textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
            }
            Text(microphone).textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color).lineLimit(1)
        }
        .padding(HubGeometry.statusCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(c.bgPanel.color))
        .overlay(shape.strokeBorder(c.edgePanel.color, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .combine)
    }
}
