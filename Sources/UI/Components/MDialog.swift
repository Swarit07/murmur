import SwiftUI

/// A modal dialog on the scrim (§4): panel fill, hairline border, radius 14, serif title, then buttons
/// right-aligned, secondary before primary. `destructive` styles the confirm button in danger text.
public struct MDialog<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let confirmTitle: String
    let destructive: Bool
    let confirmEnabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let content: Content

    public init(title: String, confirmTitle: String, destructive: Bool = false, confirmEnabled: Bool = true,
                onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.destructive = destructive
        self.confirmEnabled = confirmEnabled
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubGeometry.cardRadius, style: .continuous)
        ZStack {
            theme.colors.scrim.color.ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(title)
                    .textStyle(TypeTokens.heading)
                    .foregroundStyle(theme.colors.textTitle.color)
                    .accessibilityAddTraits(.isHeader)
                content
                HStack(spacing: Spacing.xs) {
                    Spacer()
                    MButton("Cancel", kind: .secondary, action: onCancel).keyboardShortcut(.cancelAction)
                    MButton(confirmTitle, kind: destructive ? .destructive : .primary, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!confirmEnabled)
                }
            }
            .padding(Spacing.xxl)
            .frame(width: HubGeometry.dialogWidth)
            .background(shape.fill(theme.colors.bgPanel.color))
            .overlay(shape.strokeBorder(theme.colors.borderPanel.color, lineWidth: HubGeometry.hairline))
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

/// A small notice inside the Hub (§4): panel fill, hairline border, an icon, text and an optional action.
public struct MToast: View {
    @Environment(\.theme) private var theme
    let icon: Icon
    let text: String
    let actionTitle: String?
    let action: () -> Void

    public init(_ text: String, icon: Icon = .info, actionTitle: String? = nil, action: @escaping () -> Void = {}) {
        self.text = text
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubGeometry.cardRadius, style: .continuous)
        HStack(spacing: Spacing.sm) {
            IconView(icon, size: HubGeometry.iconGlyph, color: theme.colors.textPrimary.color)
            Text(text).textStyle(TypeTokens.body).foregroundStyle(theme.colors.textPrimary.color).lineLimit(2)
                .frame(maxWidth: HubGeometry.toastMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle { MButton(actionTitle, kind: .ghost, size: .sm, action: action) }
        }
        .fixedSize()
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(shape.fill(theme.colors.bgPanel.color))
        .overlay(shape.strokeBorder(theme.colors.borderPanel.color, lineWidth: HubGeometry.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// A dark tooltip pill (§4) shown above the view after the tooltip delay.
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
                        .alignmentGuide(.top) { $0[.bottom] + HubGeometry.tooltipOffset }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(theme.motion.easeOut(MotionTokens.tooltipOut), value: visible)
            .accessibilityHint(text)
    }
}

/// The pill a tooltip draws (also used above the Flow Bar).
public struct TooltipPill: View {
    @Environment(\.theme) private var theme
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .textStyle(TypeTokens.flowText)
            .foregroundStyle(theme.flow.text.color)
            .padding(.horizontal, FlowGeometry.tooltipPaddingH)
            .frame(height: FlowGeometry.tooltipHeight)
            .background(Capsule(style: .continuous).fill(theme.flow.tooltip.color))
    }
}

extension View {
    public func mTooltip(_ text: String) -> some View { modifier(MTooltip(text: text)) }
}
