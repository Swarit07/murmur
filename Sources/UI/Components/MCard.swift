import SwiftUI

/// A plain card (§4): card fill, hairline border, 14-point radius, 20-point padding.
public struct MCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = HubGeometry.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubGeometry.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(theme.colors.bgCard.color))
            .overlay(shape.strokeBorder(theme.colors.borderPanel.color, lineWidth: HubGeometry.hairline))
    }
}

/// A selectable card (§4): when selected, a 2-point clay border and the clay tint. Under Increase
/// Contrast the tint becomes the hover fill (the border stays).
public struct MSelectableCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    let label: String
    let content: Content

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(selected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.label = label
        self.action = action
        self.content = content()
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: HubGeometry.cardRadius, style: .continuous)
        Button(action: action) {
            content
                .padding(HubGeometry.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(shape.fill(selected ? c.accentClayTint.color : (state == .hover ? c.bgHover.color : c.bgCard.color)))
                .overlay(shape.strokeBorder(selected ? c.accentClay.color : c.borderPanel.color,
                                            lineWidth: selected ? HubGeometry.selectedBorder : HubGeometry.hairline))
                .opacity(state == .disabled ? OpacityTokens.disabled : 1)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: HubGeometry.cardRadius)
        .animation(theme.motion.easeOut(MotionTokens.hover), value: state)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The warm feature card (§4): the logo's cream, a serif title with one italic word, a paragraph and an
/// optional primary button. At most one per page.
public struct MFeatureCard<Body: View>: View {
    @Environment(\.theme) private var theme
    let title: SerifTitle
    let paragraph: Body
    let buttonTitle: String?
    let action: () -> Void
    let onDismiss: (() -> Void)?

    public init(title: SerifTitle, buttonTitle: String? = nil, action: @escaping () -> Void = {}, onDismiss: (() -> Void)? = nil,
                @ViewBuilder paragraph: () -> Body) {
        self.title = title
        self.buttonTitle = buttonTitle
        self.action = action
        self.onDismiss = onDismiss
        self.paragraph = paragraph()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubGeometry.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            title
            paragraph
                .textStyle(TypeTokens.body)
                .foregroundStyle(theme.colors.textBody.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, HubGeometry.featureTitleToBody)
            if let buttonTitle {
                MButton(buttonTitle, kind: .primary, action: action)
                    .padding(.top, HubGeometry.featureBodyToButton)
            }
        }
        .padding(HubGeometry.featureCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(theme.colors.bgFeature.color))
        .overlay(shape.strokeBorder(theme.colors.borderFeature.color, lineWidth: HubGeometry.hairline))
        .overlay(alignment: .topTrailing) {
            if let onDismiss {
                MIconButton(.close, label: "Dismiss", action: onDismiss).padding(Spacing.sm)
            }
        }
    }
}
