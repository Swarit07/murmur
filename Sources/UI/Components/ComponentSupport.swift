import SwiftUI

/// The five states every interactive component draws (§4).
public enum InteractionState: String, CaseIterable, Sendable {
    case normal, hover, pressed, focused, disabled
}

extension EnvironmentValues {
    /// Forces a component into one state, for the Design Gallery and snapshots.
    @Entry public var forcedInteraction: InteractionState? = nil
}

/// The one place focus is drawn: a 2 pt `focus-ring` outside the shape with a 2 pt gap (§4).
public struct FocusRing: ViewModifier {
    @Environment(\.theme) private var theme
    let visible: Bool
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content.overlay {
            if visible {
                let outset = Stroke.focusGap + Stroke.focusRing / 2
                RoundedRectangle(cornerRadius: radius + outset, style: .continuous)
                    .stroke(theme.colors.focusRing.color, lineWidth: Stroke.focusRing)
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    public func focusRing(_ visible: Bool, radius: CGFloat) -> some View { modifier(FocusRing(visible: visible, radius: radius)) }

    /// A 1 pt ring drawn inside the shape's edge (the boards' `box-shadow: inset 0 0 0 1px`).
    public func insetRing(_ color: Color, radius: CGFloat, width: CGFloat = Stroke.hairline) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: width).allowsHitTesting(false))
    }

    /// `shadow-float`: paper toasts and popovers only (§3.4).
    public func floatShadow(_ theme: Theme) -> some View {
        shadow(color: theme.colors.shadowFloat.color, radius: ShadowTokens.floatRadius, y: ShadowTokens.floatY)
    }
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

/// Pressed moves the control down 1 pt for 80 ms (§4), unless Reduce Motion is on.
struct PressDrop: ViewModifier {
    @Environment(\.theme) private var theme
    let pressed: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: pressed ? theme.motion.offset(MotionTokens.pressDrop) : 0)
            .animation(theme.motion.easeOut(MotionTokens.press), value: pressed)
    }
}

/// A title in Newsreader with one word in italic: "Welcome back, *Swarit*".
public struct SerifTitle: View {
    @Environment(\.theme) private var theme
    let lead: String
    let italic: String
    let trail: String
    let style: TextStyleToken

    public init(_ lead: String, italic: String = "", trail: String = "", style: TextStyleToken = TypeTokens.pageTitle) {
        self.lead = lead
        self.italic = italic
        self.trail = trail
        self.style = style
    }

    public var body: some View {
        let scale = theme.textScale
        let font = TypeTokens.nsFont(style, scale: scale)
        (Text(lead).font(Font(font)) + Text(italic).font(theme.font(style.italicized)) + Text(trail).font(Font(font)))
            .tracking(style.tracking * font.pointSize)
            .foregroundStyle(theme.colors.textPrimary.color)
            .lineSpacing(max(0, style.lineHeight * scale - (font.ascender - font.descender + font.leading)))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(lead + italic + trail)
    }
}

/// "TODAY": an uppercase Geist Mono caption above a list or settings group.
public struct MCaption: View {
    @Environment(\.theme) private var theme
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .textStyle(TypeTokens.caption)
            .foregroundStyle(theme.colors.textTertiary.color)
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
            .frame(width: vertical ? Stroke.hairline : nil, height: vertical ? nil : Stroke.hairline)
    }
}
