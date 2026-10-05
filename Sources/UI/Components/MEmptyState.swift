import SwiftUI

/// The Flow Bar's idle squares on a black pill: the motif for empty states (§4).
public struct FlowSquaresMotif: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        let width = V1Flow.hoverWidth, height = V1Flow.pillHeight
        Canvas { context, size in
            let count = V1Flow.idleSquares
            let total = CGFloat(count - 1) * V1Flow.squarePitch + V1Flow.squareSide
            let x0 = (size.width - total) / 2, y = (size.height - V1Flow.squareSide) / 2
            for i in 0..<count {
                let rect = CGRect(x: x0 + CGFloat(i) * V1Flow.squarePitch, y: y, width: V1Flow.squareSide, height: V1Flow.squareSide)
                context.fill(Path(rect), with: .color(theme.v1flow.dot.color))
            }
        }
        .frame(width: width, height: height)
        .background(Capsule(style: .circular).fill(theme.v1flow.fill.color))
        .overlay(Capsule(style: .circular).strokeBorder(theme.v1flow.border.color, lineWidth: V1Flow.border))
        .accessibilityHidden(true)
    }
}

/// What an empty page shows (§4): the motif, one line of text and an optional primary button.
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
        VStack(spacing: V1Spacing.lg) {
            FlowSquaresMotif()
            Text(text)
                .textStyle(V1Type.body)
                .foregroundStyle(theme.v1.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: V1Hub.emptyStateMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle { MButton(buttonTitle, kind: .primary, action: action) }
        }
        .padding(V1Spacing.x5)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
