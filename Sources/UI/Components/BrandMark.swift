import SwiftUI

/// Murmur's mark: an "M" whose right stroke flows into a waveform (`Design/murmur-mark-tidied.svg`,
/// traced from the owner's logo, with the left leg's end smoothed). One filled path, aspect 2.65 : 1.
/// Clay on light surfaces, clay-text on dark; never stretched, never recolored outside the palette.
public struct BrandMarkShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let unit = Self.unitPath
        // Fit the 1002 × 378 artwork into the rect without stretching, centered.
        let scale = min(rect.width / Self.viewBox.width, rect.height / Self.viewBox.height)
        let size = CGSize(width: Self.viewBox.width * scale, height: Self.viewBox.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        return unit.applying(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale))
    }

    static let viewBox = CGSize(width: 1002, height: 378)

    /// The SVG path data (absolute M, C, L, Z only).
    static let data = "M777.3,370.1C768.6,364.7 762.4,344.6 751.5,286.0C744.9,250.3 743.5,245.7 738.8,245.2C736.4,244.9 735.7,245.6 733.0,250.3C725.2,264.2 719.6,264.7 711.5,252.0C702.9,238.6 700.5,240.4 691.2,267.0C681.1,295.7 676.3,304.0 669.4,304.0C660.8,304.0 655.4,295.5 646.6,267.9C639.6,246.1 636.0,241.3 631.2,247.5C627.9,251.7 625.4,259.5 618.0,288.0C604.4,340.4 597.2,354.0 584.3,351.5C573.3,349.5 566.0,334.7 553.6,289.4C544.2,255.2 541.0,246.0 536.7,241.2C531.3,235.3 527.0,240.2 518.5,262.0C511.1,280.7 507.7,286.4 502.3,288.7C494.7,291.8 489.6,288.7 481.2,275.8C472.2,261.9 467.4,258.0 459.4,258.0C451.9,258.0 447.3,262.4 432.1,284.5C404.9,323.7 398.3,331.3 385.3,337.7C375.0,342.8 361.3,343.3 351.8,338.8C340.5,333.5 332.4,322.8 330.0,310.1C329.4,306.8 329.0,271.5 329.0,216.9L329.0,129.2L326.4,126.1C323.5,122.6 318.1,121.9 314.3,124.5C313.1,125.3 303.9,136.7 293.7,149.8C245.1,212.4 224.8,229.1 199.3,227.8C182.8,226.9 171.5,220.6 154.2,202.5C144.0,191.9 137.0,183.2 105.7,142.8C98.1,133.0 91.0,124.5 89.8,123.9C85.0,121.3 79.7,123.2 76.7,128.5C75.8,130.0 75.4,156.0 75.0,224.5L74.6,312.0C74.6,328.9 59.3,342.6 40.45,342.6C21.6,342.6 6.3,328.9 6.3,312.0L6.2,183.6C6.0,64.1 6.1,50.1 7.6,45.1C17.3,11.7 51.8,-3.6 82.4,12.1C99.3,20.8 112.5,35.5 159.2,97.5C193.7,143.2 194.4,144.0 202.4,144.0C210.4,144.0 213.5,140.8 242.5,103.0C285.1,47.6 301.6,28.7 315.5,19.3C350.6,-4.3 388.3,4.1 401.3,38.7C403.5,44.5 403.5,44.8 404.0,132.5C404.4,198.3 404.9,221.4 405.8,224.1C409.0,233.7 415.1,237.9 422.6,235.8C432.7,233.1 448.0,210.3 461.4,178.0C476.6,141.8 481.5,134.1 490.5,132.4C501.4,130.4 508.7,141.1 517.9,173.0C526.6,203.3 529.1,208.3 534.4,205.9C539.5,203.6 543.5,190.6 552.5,148.0C564.4,91.2 571.2,74.5 583.4,71.4C588.9,70.1 596.3,74.7 599.9,81.9C604.9,91.7 611.7,119.4 619.0,160.0C623.2,183.1 628.3,203.2 631.0,207.0C636.1,214.1 639.2,210.1 646.9,186.5C655.3,160.7 659.9,152.1 666.4,150.4C676.0,148.0 681.7,156.0 692.0,186.7C701.0,213.6 704.4,216.0 712.0,201.0C718.5,188.2 725.4,188.1 731.5,200.8C736.4,210.9 739.5,212.6 742.4,206.6C744.7,201.7 746.3,194.1 752.9,155.3C763.5,93.5 767.1,80.3 775.0,73.6C782.3,67.5 788.8,72.4 794.1,87.7C797.8,98.6 801.0,113.4 809.5,160.0C817.2,202.4 821.7,214.2 828.0,208.5C829.9,206.8 832.0,201.2 840.0,176.3C845.4,159.4 849.0,152.7 853.6,151.0C861.7,147.9 866.9,155.0 875.8,181.0C887.1,214.0 891.2,217.7 902.1,204.8C911.4,193.7 918.0,193.0 927.3,201.8C945.4,218.9 958.1,224.0 982.4,224.0C992.8,224.0 995.2,225.1 995.2,229.5C995.2,234.0 993.2,234.7 977.7,235.3C956.0,236.2 944.0,240.5 932.5,251.8C918.5,265.5 912.2,265.7 901.9,252.7C895.6,244.8 891.9,242.9 888.3,245.6C884.8,248.2 881.0,255.7 876.9,268.0C869.5,289.9 865.5,297.0 859.5,299.0C851.4,301.7 846.7,295.3 837.4,268.9C830.7,249.7 828.7,245.7 825.2,245.2C820.5,244.5 817.4,253.9 809.0,294.1C799.2,341.2 795.5,355.0 790.6,363.4C786.1,371.1 782.2,373.0 777.3,370.1Z"

    /// Parsed once.
    static let unitPath: Path = {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "L" where numbers.count >= 2:
                path.addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "C" where numbers.count >= 6:
                path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                              control1: CGPoint(x: numbers[0], y: numbers[1]), control2: CGPoint(x: numbers[2], y: numbers[3]))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            numbers.removeAll()
        }
        var token = ""
        for ch in data {
            if "MCLZ".contains(ch) {
                if !token.isEmpty { numbers.append(CGFloat(Double(token) ?? 0)); token = "" }
                flush()
                command = ch
            } else if ch == "," || ch == " " {
                if !token.isEmpty { numbers.append(CGFloat(Double(token) ?? 0)); token = "" }
            } else if ch == "-" && !token.isEmpty {
                numbers.append(CGFloat(Double(token) ?? 0))
                token = "-"
            } else {
                token.append(ch)
            }
            // A curve or line can repeat its parameters without repeating the letter.
            if command == "C", numbers.count == 6 { flush() }
            if command == "L", numbers.count == 2 { flush() }
        }
        if !token.isEmpty { numbers.append(CGFloat(Double(token) ?? 0)) }
        flush()
        if command != "Z" { path.closeSubpath() }
        return path
    }()
}

/// The mark at a height, in the theme's clay (clay-text in dark mode).
public struct BrandMark: View {
    @Environment(\.theme) private var theme
    let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    public var body: some View {
        BrandMarkShape()
            .fill(theme.scheme == .dark ? theme.v1.accentClayText.color : theme.v1.accentClay.color)
            .frame(width: height * V1Hub.brandMarkAspect, height: height)
            .accessibilityLabel("Murmur")
    }
}
