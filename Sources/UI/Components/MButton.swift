import SwiftUI

/// Buttons (§4). **primary:** clay fill, `on-clay` text, the one main action on a surface. **ink:** solid
/// ink (Add word, New snippet, Save). **outline:** a 1 pt ring (`text-primary` at regular size, `border-
/// control` small). **link:** text with a soft underline (Not now, Skip, Undo). Hover changes the fill
/// only; pressed moves down 1 pt with the pressed fill; keyboard focus draws the focus ring.
public struct MButton: View {
    public enum Kind: Sendable { case primary, ink, outline, link }
    public enum Size: Sendable { case regular, small }

    let title: String
    let icon: Icon?
    let kind: Kind
    let size: Size
    let fullWidth: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ title: String, icon: Icon? = nil, kind: Kind = .ink, size: Size = .regular, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(MButtonStyle(title: title, icon: icon, kind: kind, size: size, fullWidth: fullWidth, theme: theme,
                                      hovering: hovering, focused: focused, enabled: isEnabled, forced: forced))
            .focusable(isEnabled, interactions: .activate)
            .focused($focused)
            .focusEffectDisabled()
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
    }
}

struct MButtonStyle: ButtonStyle {
    let title: String
    let icon: Icon?
    let kind: MButton.Kind
    let size: MButton.Size
    let fullWidth: Bool
    let theme: Theme
    let hovering: Bool
    let focused: Bool
    let enabled: Bool
    let forced: InteractionState?

    func makeBody(configuration: Configuration) -> some View {
        let state = resolvedState(forced: forced, enabled: enabled, pressed: configuration.isPressed, focused: focused, hovering: hovering)
        let c = theme.colors
        let small = size == .small
        let radius = small ? Radius.control : Radius.button
        let height = small ? HubGeometry.buttonHeightSmall : HubGeometry.buttonHeight
        let disabled = state == .disabled
        let active = state == .hover || state == .pressed
        let fill: Color = switch kind {
        case .primary:
            disabled ? c.fillSelected.color : state == .pressed ? c.accentClayPressed.color : state == .hover ? c.accentClayHover.color : c.accentClay.color
        case .ink:
            disabled ? c.fillSelected.color : state == .pressed ? c.inkFillPressed.color : state == .hover ? c.inkFillHover.color : c.inkFill.color
        case .outline:
            disabled ? c.fillSelected.color : active ? c.fillHover.color : .clear
        case .link:
            .clear
        }
        let foreground: Color = switch kind {
        case _ where disabled: c.textTertiary.color
        case .primary: c.onClay.color
        case .ink: c.onInk.color
        case .outline, .link: c.textPrimary.color
        }
        let ring: Color? = switch kind {
        case .outline where !disabled: small ? c.borderControl.color : c.textPrimary.color
        default: nil
        }
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let label = HStack(spacing: Spacing.s8) {
            if let icon { IconView(icon, size: HubGeometry.buttonIcon, color: foreground) }
            Text(title)
                .textStyle(small ? TypeTokens.hint.weight(500) : TypeTokens.button)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(foreground)
        return Group {
            if kind == .link {
                label
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(active ? c.textPrimary.color : c.underline.color)
                            .frame(height: Stroke.hairline)
                            .offset(y: HubGeometry.linkUnderlineOffset - Spacing.s4 / 2)
                    }
                    .frame(height: height)
                    .contentShape(Rectangle())
            } else {
                label
                    .padding(.horizontal, small ? HubGeometry.buttonPaddingHSmall : HubGeometry.buttonPaddingH)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .frame(height: height)
                    .background(shape.fill(fill))
                    .overlay { if let ring { shape.strokeBorder(ring, lineWidth: Stroke.hairline) } }
                    .contentShape(shape)
            }
        }
        .modifier(PressDrop(pressed: state == .pressed))
        .focusRing(state == .focused, radius: kind == .link ? Radius.keycapSmall : radius)
        .animation(theme.motion.easeOut(MotionTokens.hover), value: state)
    }
}

/// A square icon button, 32 (or 28) pt, radius 8 (or 7), filled only on hover (§4).
public struct MIconButton: View {
    public enum Size: Sendable { case regular, small }
    let icon: Icon
    let label: String
    let size: Size
    let selected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ icon: Icon, label: String, size: Size = .regular, selected: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(MIconButtonStyle(icon: icon, size: size, selected: selected, theme: theme, hovering: hovering, focused: focused,
                                          enabled: isEnabled, forced: forced))
            .focusable(isEnabled, interactions: .activate)
            .focused($focused)
            .focusEffectDisabled()
            .onHover { hovering = $0 }
            .mTooltip(label)
            .accessibilityLabel(label)
    }
}

struct MIconButtonStyle: ButtonStyle {
    let icon: Icon
    let size: MIconButton.Size
    let selected: Bool
    let theme: Theme
    let hovering: Bool
    let focused: Bool
    let enabled: Bool
    let forced: InteractionState?

    func makeBody(configuration: Configuration) -> some View {
        let state = resolvedState(forced: forced, enabled: enabled, pressed: configuration.isPressed, focused: focused, hovering: hovering)
        let c = theme.colors
        let small = size == .small
        let side = small ? HubGeometry.iconButtonSmall : HubGeometry.iconButton
        let radius = small ? Radius.keycap : Radius.control
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let fill = state == .pressed || selected ? c.fillSelected.color : state == .hover ? c.fillHover.color : Color.clear
        return IconView(icon, size: small ? HubGeometry.buttonIcon : HubGeometry.iconGlyph, color: state == .disabled ? c.textTertiary.color : c.textPrimary.color)
            .frame(width: side, height: side)
            .background(shape.fill(fill))
            .contentShape(shape)
            .modifier(PressDrop(pressed: state == .pressed))
            .focusRing(state == .focused, radius: radius)
            .animation(theme.motion.easeOut(MotionTokens.hover), value: state)
    }
}
