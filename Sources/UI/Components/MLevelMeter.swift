import SwiftUI

/// The mic-test level meter (§5.4, `MurmurLevels` in the motion reference): 18 bars, 8 wide, gap 4,
/// 64 high, heights ramping from 30% to 100%. Lit bars are ink, and clay in the last third (the target
/// zone); unlit bars are ink at 12%.
public struct MLevelMeter: View {
    @Environment(\.theme) private var theme
    let level: Double
    let compact: Bool

    /// `level` is 0…1, already smoothed by the caller. `compact` is the small inline meter in Settings.
    public init(level: Double, compact: Bool = false) {
        self.level = level
        self.compact = compact
    }

    public var body: some View {
        let c = theme.colors
        let count = OnboardingGeometry.meterBars
        let lit = level * Double(count)
        let unlit = theme.scheme == .dark ? ColorToken.ivory(MeterTokens.unlit) : ColorToken.ink(MeterTokens.unlit)
        let barWidth = compact ? HubGeometry.meterCompact.width : OnboardingGeometry.meterBarWidth
        let height = compact ? HubGeometry.meterCompact.height : OnboardingGeometry.meterHeight
        HStack(alignment: .bottom, spacing: compact ? HubGeometry.meterCompactGap : OnboardingGeometry.meterBarGap) {
            ForEach(0..<count, id: \.self) { i in
                let ramp = OnboardingGeometry.meterLowest + (1 - OnboardingGeometry.meterLowest)
                    * CGFloat(pow(Double(i) / Double(max(1, count - 1)), MeterTokens.rampExponent))
                let on = Double(i) < lit
                let target = Double(i) >= Double(count) * OnboardingGeometry.meterClayFrom
                RoundedRectangle(cornerRadius: min(OnboardingGeometry.meterBarRadius, barWidth / 2), style: .continuous)
                    .fill(on ? (target ? c.accentClay.color : c.textPrimary.color) : unlit.color)
                    .frame(width: barWidth, height: height * ramp)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
