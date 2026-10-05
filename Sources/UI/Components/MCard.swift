import SwiftUI

/// A plain card (§4): paper, a 1 pt ink hairline, radius 12.
public struct MCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let padding: CGFloat
    let radius: CGFloat
    let content: Content

    public init(padding: CGFloat = Spacing.s16, radius: CGFloat = Radius.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            // The 1 pt border sits outside the padding, as a CSS border does.
            .padding(padding + Stroke.hairline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(theme.colors.bgPanel.color))
            .overlay(shape.strokeBorder(theme.colors.borderHairline.color, lineWidth: Stroke.hairline))
    }
}

/// A selectable card (§4): paper, radius 14 (12 for snippets), a 1 pt hairline. Selected: a 1.5 pt
/// ink ring (2 pt under Increase Contrast) and, with `radio`, a filled radio top-right. Never clay.
public struct MSelectableCard<Content: View>: View {
    let selected: Bool
    let radius: CGFloat
    let padding: CGFloat
    let radio: Bool
    let action: () -> Void
    let label: String
    let content: Content

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(selected: Bool, label: String, radius: CGFloat = Radius.cardLarge, padding: CGFloat = HubGeometry.styleCardPadding,
                radio: Bool = true, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.label = label
        self.radius = radius
        self.padding = padding
        self.radio = radio
        self.action = action
        self.content = content()
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let ring = theme.increaseContrast ? Stroke.selectedIncreased : Stroke.selected
        Button(action: action) {
            content
                .padding(padding)
                .padding(.trailing, radio ? HubGeometry.radio + Spacing.s8 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topTrailing) {
                    if radio { MRadio(selected: selected).padding(padding).padding(.top, Spacing.s4) }
                }
                .background(shape.fill(state == .hover && !selected ? c.fillHover.color : .clear))
                .background(shape.fill(state == .disabled ? c.fillSelected.color : c.bgPanel.color))
                .overlay(shape.strokeBorder(selected ? c.inkFill.color : c.borderHairline.color, lineWidth: selected ? ring : Stroke.hairline))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: radius)
        .animation(theme.motion.easeOut(MotionTokens.hover), value: state)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The feature card (§4): the sunken fill, radius 16, padding 28, 32 between text and visual. At most
/// one per page.
public struct MFeatureCard<Text: View, Visual: View>: View {
    @Environment(\.theme) private var theme
    let text: Text
    let visual: Visual

    public init(@ViewBuilder text: () -> Text, @ViewBuilder visual: () -> Visual) {
        self.text = text()
        self.visual = visual()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: HubGeometry.featureGap) {
            text.frame(maxWidth: .infinity, alignment: .leading)
            visual
        }
        .padding(HubGeometry.featurePadding)
        .background(RoundedRectangle(cornerRadius: Radius.feature, style: .continuous).fill(theme.colors.bgSunken.color))
    }
}

/// A sunken box for samples and illustrations: radius 10 or 12, the sunken fill.
public struct MWell<Content: View>: View {
    @Environment(\.theme) private var theme
    let radius: CGFloat
    let padding: CGSize
    let content: Content

    public init(radius: CGFloat = Radius.button, padding: CGSize = HubGeometry.samplePadding, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, padding.width)
            .padding(.vertical, padding.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.colors.bgSunken.color))
    }
}
