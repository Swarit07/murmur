import SwiftUI

/// The idle Flow Bar pill: 52 × 12 of flow ink with a centered 20 × 1.5 dash. The empty-state motif,
/// and the pill in onboarding's last step.
public struct FlowIdlePill: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        let f = theme.flow
        Capsule(style: .circular)
            .fill(f.flowFill.color)
            .overlay(Capsule(style: .circular).strokeBorder(f.flowRing.color, lineWidth: Stroke.hairline))
            .overlay {
                RoundedRectangle(cornerRadius: FlowGeometry.idleDashRadius, style: .continuous)
                    .fill(f.flowIdleMark.color)
                    .frame(width: FlowGeometry.idleDash.width, height: FlowGeometry.idleDash.height)
            }
            .frame(width: FlowGeometry.idleSize.width, height: FlowGeometry.idleSize.height)
            .accessibilityHidden(true)
    }
}

/// An empty state [ASSUMED]: a sunken well with the idle Flow Bar pill, one `body` line, an optional
/// primary button.
public struct MEmptyState: View {
    @Environment(\.theme) private var theme
    let text: String
    let buttonTitle: String?
    let action: () -> Void

    public init(_ text: String, buttonTitle: String? = nil, action: @escaping () -> Void = {}) {
        self.text = text
        self.buttonTitle = buttonTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.s16) {
            FlowIdlePill()
            Text(text)
                .textStyle(TypeTokens.body)
                .foregroundStyle(theme.colors.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: HubGeometry.emptyStateMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle { MButton(buttonTitle, kind: .primary, action: action) }
        }
        .padding(Spacing.s32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(theme.colors.bgSunken.color))
        .accessibilityElement(children: .contain)
    }
}
