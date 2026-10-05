import SwiftUI

/// The five states every interactive component draws (§4).
public enum InteractionState: String, CaseIterable, Sendable {
    case normal, hover, pressed, focused, disabled
}

extension EnvironmentValues {
    /// Forces a component into one state, for the Design Gallery and snapshots.
    @Entry public var forcedInteraction: InteractionState? = nil
}

/// The one place focus is drawn: a ring in `focus-ring`, outside the shape with a gap (§4).
public struct FocusRing: ViewModifier {
    @Environment(\.theme) private var theme
    let visible: Bool
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content.overlay {
            if visible {
                let outset = HubGeometry.focusRingGap + HubGeometry.focusRingWidth / 2
                RoundedRectangle(cornerRadius: radius + outset, style: .continuous)
                    .stroke(theme.colors.focusRing.color, lineWidth: HubGeometry.focusRingWidth)
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    public func focusRing(_ visible: Bool, radius: CGFloat) -> some View { modifier(FocusRing(visible: visible, radius: radius)) }
}

/// Resolves the state to draw from the forced state, enablement, press, focus and hover.
func resolvedState(forced: InteractionState?, enabled: Bool, pressed: Bool, focused: Bool, hovering: Bool) -> InteractionState {
    if let forced { return forced }
    if !enabled { return .disabled }
    if pressed { return .pressed }
    if focused { return .focused }
    if hovering { return .hover }
    return .normal
}

/// Scales the label while pressed (80 ms to 0.98) unless Reduce Motion is on.
struct PressScale: ViewModifier {
    @Environment(\.theme) private var theme
    let pressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? theme.motion.scale(HubGeometry.pressScale) : 1)
            .animation(theme.motion.easeOut(MotionTokens.press), value: pressed)
    }
}

/// A title in the display serif with one word in italic: "Welcome back, *Swarit*".
public struct SerifTitle: View {
    @Environment(\.theme) private var theme
    let lead: String
    let italic: String
    let trail: String
    let style: TextStyleToken

    public init(_ lead: String, italic: String, trail: String = "", style: TextStyleToken = TypeTokens.pageTitle) {
        self.lead = lead
        self.italic = italic
        self.trail = trail
        self.style = style
    }

    public var body: some View {
        (Text(lead).font(theme.font(style)) + Text(italic).font(theme.font(style.italicized)) + Text(trail).font(theme.font(style)))
            .foregroundStyle(theme.colors.textTitle.color)
            .lineSpacing(max(0, style.lineHeight - style.size) * theme.textScale)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(lead + italic + trail)
    }
}

/// "TODAY": a small uppercase caption above a list.
public struct MSectionCaption: View {
    @Environment(\.theme) private var theme
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .textStyle(TypeTokens.section)
            .foregroundStyle(theme.colors.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A 1 pt horizontal or vertical rule.
public struct Hairline: View {
    @Environment(\.theme) private var theme
    let color: KeyPath<ThemeColors, ColorToken>
    let vertical: Bool

    public init(_ color: KeyPath<ThemeColors, ColorToken> = \.borderDivider, vertical: Bool = false) {
        self.color = color
        self.vertical = vertical
    }

    public var body: some View {
        Rectangle()
            .fill(theme.colors[keyPath: color].color)
            .frame(width: vertical ? HubGeometry.hairline : nil, height: vertical ? nil : HubGeometry.hairline)
    }
}
