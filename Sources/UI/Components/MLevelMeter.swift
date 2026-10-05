import SwiftUI

/// The mic-test level meter (§5.4, `MurmurLevels` in the motion reference): 18 bars, 8 wide, gap 4,
/// 64 high, heights ramping from 30% to 100%. Lit bars are ink, and clay in the last third (the target
/// zone); unlit bars are ink at 12%.
public struct MLevelMeter: View {
    @Environment(\.theme) private var theme
    let level: Double

    /// `level` is 0…1, already smoothed by the caller.
    public init(level: Double) {
        self.level = level
    }

    public var body: some View {
        let c = theme.colors
        let count = OnboardingGeometry.meterBars
        let lit = level * Double(count)
        let unlit = theme.scheme == .dark ? ColorToken.ivory(MeterTokens.unlit) : ColorToken.ink(MeterTokens.unlit)
        HStack(alignment: .bottom, spacing: OnboardingGeometry.meterBarGap) {
            ForEach(0..<count, id: \.self) { i in
                let ramp = OnboardingGeometry.meterLowest + (1 - OnboardingGeometry.meterLowest)
                    * CGFloat(pow(Double(i) / Double(max(1, count - 1)), MeterTokens.rampExponent))
                let on = Double(i) < lit
                let target = Double(i) >= Double(count) * OnboardingGeometry.meterClayFrom
                RoundedRectangle(cornerRadius: min(OnboardingGeometry.meterBarRadius, OnboardingGeometry.meterBarWidth / 2), style: .continuous)
                    .fill(on ? (target ? c.accentClay.color : c.textPrimary.color) : unlit.color)
                    .frame(width: OnboardingGeometry.meterBarWidth, height: OnboardingGeometry.meterHeight * ramp)
            }
        }
        .frame(height: OnboardingGeometry.meterHeight, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
