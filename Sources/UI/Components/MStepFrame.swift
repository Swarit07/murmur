import SwiftUI

/// One onboarding step (§5.4): `bg-window`, padding 28, gap 20. A mono header ("02 / 12 · Permissions")
/// with a 120 × 2 progress bar, an optional sunken illustration well, the step title and body, any
/// extra content, then a footer with "Back" on the left and one primary button on the right.
public struct MStepFrame<Illustration: View, Extra: View>: View {
    @Environment(\.theme) private var theme
    let index: Int
    let count: Int
    let section: String?
    let title: String
    let message: String
    let primary: String
    let back: String?
    let primaryEnabled: Bool
    let onPrimary: () -> Void
    let onBack: () -> Void
    let illustration: Illustration
    let extra: Extra

    public init(index: Int, count: Int, section: String?, title: String, message: String, primary: String,
                back: String? = "Back", primaryEnabled: Bool = true, onPrimary: @escaping () -> Void, onBack: @escaping () -> Void = {},
                @ViewBuilder illustration: () -> Illustration, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.index = index
        self.count = count
        self.section = section
        self.title = title
        self.message = message
        self.primary = primary
        self.back = back
        self.primaryEnabled = primaryEnabled
        self.onPrimary = onPrimary
        self.onBack = onBack
        self.illustration = illustration()
        self.extra = extra()
    }

    public var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: OnboardingGeometry.gap) {
            HStack {
                Text(String(format: "%02d / %02d", index, count) + (section.map { " · \($0)" } ?? ""))
                    .textStyle(TypeTokens.keycapSmall)
                    .foregroundStyle(c.textTertiary.color)
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule(style: .circular).fill(c.edgePanel.color)
                    Capsule(style: .circular).fill(c.inkFill.color)
                        .frame(width: OnboardingGeometry.progress.width * CGFloat(index) / CGFloat(max(1, count)))
                }
                .frame(width: OnboardingGeometry.progress.width, height: OnboardingGeometry.progress.height)
                .accessibilityElement()
                .accessibilityLabel("Step \(index) of \(count)")
            }
            illustration
            VStack(alignment: .leading, spacing: OnboardingGeometry.titleGap) {
                Text(title).textStyle(TypeTokens.stepTitle).foregroundStyle(c.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message).textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            extra
            Spacer(minLength: 0)
            HStack {
                if let back {
                    Button(action: onBack) {
                        Text(back).textStyle(TypeTokens.label.weight(400)).foregroundStyle(c.textTertiary.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(back)
                }
                Spacer()
                MButton(primary, kind: .primary, action: onPrimary).disabled(!primaryEnabled)
            }
        }
        .padding(OnboardingGeometry.padding)
        .frame(width: OnboardingGeometry.step.width, height: OnboardingGeometry.step.height, alignment: .topLeading)
        .background(c.bgWindow.color)
    }
}

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
