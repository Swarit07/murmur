import SwiftUI

/// A sheet over the Hub (Help & setup, confirmations): paper, radius 14, a 1 pt hairline,
/// `shadow-float`, on the scrim. Buttons sit right-aligned, the main one last.
public struct MDialog<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(title).textStyle(TypeTokens.stepTitle).foregroundStyle(theme.colors.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Spacing.s28)
        .frame(width: HubGeometry.dialogWidth, alignment: .leading)
        .background(shape.fill(theme.colors.bgPanel.color).floatShadow(theme))
        .overlay(shape.strokeBorder(theme.colors.borderHairline.color, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
    }
}

/// The paper toast (§4): paper, radius 14, padding 10 × 14, a 1 pt ink ring, `shadow-float`; a 16 pt
/// icon, a label with a tertiary detail, and a link-style action (Undo). The caller places it at the
/// bottom center of the panel, 22 pt above its edge.
public struct MPaperToast: View {
    @Environment(\.theme) private var theme
    let icon: Icon
    let text: String
    let detail: String?
    let actionTitle: String?
    let action: () -> Void

    public init(_ text: String, detail: String? = nil, icon: Icon = .check, actionTitle: String? = nil, action: @escaping () -> Void = {}) {
        self.text = text
        self.detail = detail
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous)
        HStack(spacing: Spacing.s10) {
            IconView(icon, size: HubGeometry.paperToastIcon, color: c.textPrimary.color)
            (Text(text).foregroundStyle(c.textPrimary.color) + Text(detail.map { " · \($0)" } ?? "").foregroundStyle(c.textTertiary.color))
                .textStyle(TypeTokens.label)
                .lineLimit(1)
            if let actionTitle { MButton(actionTitle, kind: .link, size: .small, action: action) }
        }
        .fixedSize()
        .padding(.horizontal, HubGeometry.paperToastPadding.width)
        .padding(.vertical, HubGeometry.paperToastPadding.height)
        .background(shape.fill(c.bgPanel.color).floatShadow(theme))
        .overlay(shape.strokeBorder(c.edgeToast.color, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// A tooltip (§4) shown above the view after the tooltip delay: an ink pill with ivory text.
public struct MTooltip: ViewModifier {
    @Environment(\.theme) private var theme
    let text: String
    @State private var visible = false
    @State private var task: Task<Void, Never>?

    public func body(content: Content) -> some View {
        content
            .onHover { inside in
                task?.cancel()
                if inside {
                    let delay = theme.motion.seconds(MotionTokens.tooltipDelay)
                    task = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        if !Task.isCancelled { visible = true }
                    }
                } else {
                    visible = false
                }
            }
            .overlay(alignment: .top) {
                if visible {
                    TooltipPill(text: text)
                        .fixedSize()
                        .alignmentGuide(.top) { $0[.bottom] + FlowGeometry.tooltipGap }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(theme.motion.easeOut(MotionTokens.tooltipOut), value: visible)
            .accessibilityHint(text)
    }
}

/// The pill a tooltip draws: 28 high, ink, `hint` 12/500 in ivory (the Flow Bar's tooltip style).
public struct TooltipPill: View {
    @Environment(\.theme) private var theme
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .textStyle(TypeTokens.hint.weight(500))
            .foregroundStyle(theme.flow.flowText.color)
            .padding(.horizontal, FlowGeometry.tooltipPaddingH)
            .frame(height: FlowGeometry.tooltipHeight)
            .background(Capsule(style: .circular).fill(theme.flow.flowFill.color))
            .overlay(Capsule(style: .circular).strokeBorder(theme.flow.flowRing.color, lineWidth: Stroke.hairline))
    }
}

extension View {
    public func mTooltip(_ text: String) -> some View { modifier(MTooltip(text: text)) }
}
