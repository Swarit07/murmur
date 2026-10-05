import SwiftUI

/// The Flow Bar's idle squares on a black pill: the motif for empty states (§4).
public struct FlowSquaresMotif: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        let width = FlowGeometry.hoverWidth, height = FlowGeometry.pillHeight
        Canvas { context, size in
            let count = FlowGeometry.idleSquares
            let total = CGFloat(count - 1) * FlowGeometry.squarePitch + FlowGeometry.squareSide
            let x0 = (size.width - total) / 2, y = (size.height - FlowGeometry.squareSide) / 2
            for i in 0..<count {
                let rect = CGRect(x: x0 + CGFloat(i) * FlowGeometry.squarePitch, y: y, width: FlowGeometry.squareSide, height: FlowGeometry.squareSide)
                context.fill(Path(rect), with: .color(theme.flow.dot.color))
            }
        }
        .frame(width: width, height: height)
        .background(Capsule(style: .circular).fill(theme.flow.fill.color))
        .overlay(Capsule(style: .circular).strokeBorder(theme.flow.border.color, lineWidth: FlowGeometry.border))
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
        VStack(spacing: Spacing.lg) {
            FlowSquaresMotif()
            Text(text)
                .textStyle(TypeTokens.body)
                .foregroundStyle(theme.colors.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: HubGeometry.emptyStateMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle { MButton(buttonTitle, kind: .primary, action: action) }
        }
        .padding(Spacing.x5)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
