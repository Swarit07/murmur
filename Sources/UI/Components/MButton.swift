import SwiftUI

/// Buttons (§4). Primary: clay fill and white text, the page's one main action. Secondary: card fill
/// with a control border. Ghost: text only. Destructive: the secondary shape in danger text, used
/// only inside a confirmation dialog. Hover changes the fill only; pressed scales to 0.98 for 80 ms;
/// keyboard focus draws the focus ring.
public struct MButton: View {
    public enum Kind: Sendable { case primary, secondary, ghost, destructive }
    public enum Size: Sendable { case sm, md, lg }

    let title: String
    let icon: Icon?
    let kind: Kind
    let size: Size
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ title: String, icon: Icon? = nil, kind: Kind = .secondary, size: Size = .md, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(MButtonStyle(title: title, icon: icon, kind: kind, size: size, theme: theme, hovering: hovering,
                                      focused: focused, enabled: isEnabled, forced: forced))
            .focusable(isEnabled)
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
    let theme: Theme
    let hovering: Bool
    let focused: Bool
    let enabled: Bool
    let forced: InteractionState?

    func makeBody(configuration: Configuration) -> some View {
        let state = resolvedState(forced: forced, enabled: enabled, pressed: configuration.isPressed, focused: focused, hovering: hovering)
        let c = theme.v1
        let height = switch size {
        case .sm: V1Hub.buttonHeightSmall
        case .md: V1Hub.buttonHeight
        case .lg: V1Hub.buttonHeightLarge
        }
        let fill: Color = switch kind {
        case .primary:
            state == .disabled ? c.accentClay.color.opacity(V1Opacity.disabled)
                : state == .pressed ? c.accentClayPressed.color : state == .hover ? c.accentClayHover.color : c.accentClay.color
        case .secondary, .destructive:
            state == .hover || state == .pressed ? c.bgHover.color : c.bgCard.color
        case .ghost:
            state == .hover || state == .pressed ? c.bgHover.color : .clear
        }
        let foreground: Color = switch kind {
        case .primary: c.buttonText.color
        case .destructive: state == .disabled ? c.textDisabled.color : c.dangerText.color
        case .secondary, .ghost: state == .disabled ? c.textDisabled.color : c.textPrimary.color
        }
        let shape = RoundedRectangle(cornerRadius: V1Hub.buttonRadius, style: .continuous)
        return HStack(spacing: V1Spacing.xs) {
            if let icon { IconView(icon, size: V1Hub.iconGlyph, color: foreground) }
            Text(title).textStyle(V1Type.button).lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, V1Hub.buttonPaddingH)
        .frame(minWidth: kind == .ghost ? nil : (size == .sm ? V1Hub.buttonMinWidthSmall : V1Hub.buttonMinWidth))
        .frame(height: height)
        .background(shape.fill(fill))
        .overlay {
            if kind == .secondary || kind == .destructive {
                shape.strokeBorder(c.borderControl.color.opacity(state == .disabled ? V1Opacity.disabled : 1), lineWidth: V1Hub.hairline)
            }
        }
        .contentShape(shape)
        .modifier(PressScale(pressed: state == .pressed))
        .focusRing(state == .focused, radius: V1Hub.buttonRadius)
        .animation(theme.motion.easeOut(V1Motion.hover), value: state)
    }
}

/// A 32-point square icon button (§4): no fill until hovered.
public struct MIconButton: View {
    let icon: Icon
    let label: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ icon: Icon, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(MIconButtonStyle(icon: icon, theme: theme, hovering: hovering, focused: focused, enabled: isEnabled, forced: forced))
            .focusable(isEnabled)
            .focused($focused)
            .focusEffectDisabled()
            .onHover { hovering = $0 }
            .help(label)
            .accessibilityLabel(label)
    }
}

struct MIconButtonStyle: ButtonStyle {
    let icon: Icon
    let theme: Theme
    let hovering: Bool
    let focused: Bool
    let enabled: Bool
    let forced: InteractionState?

    func makeBody(configuration: Configuration) -> some View {
        let state = resolvedState(forced: forced, enabled: enabled, pressed: configuration.isPressed, focused: focused, hovering: hovering)
        let c = theme.v1
        let shape = RoundedRectangle(cornerRadius: V1Hub.iconButtonRadius, style: .continuous)
        return IconView(icon, size: V1Hub.iconGlyph, color: state == .disabled ? c.textDisabled.color : c.textPrimary.color)
            .frame(width: V1Hub.iconButton, height: V1Hub.iconButton)
            .background(shape.fill(state == .hover || state == .pressed ? c.bgHover.color : .clear))
            .contentShape(shape)
            .modifier(PressScale(pressed: state == .pressed))
            .focusRing(state == .focused, radius: V1Hub.iconButtonRadius)
            .animation(theme.motion.easeOut(V1Motion.hover), value: state)
    }
}
