import SwiftUI

/// The sunken illustration well on an onboarding step: radius 12, 200-220 high.
public struct MIllustrationWell<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(minHeight: OnboardingGeometry.wellMinHeight, maxHeight: OnboardingGeometry.wellHeight)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(theme.colors.bgSunken.color))
    }
}
