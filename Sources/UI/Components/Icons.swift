import SwiftUI

/// Murmur's own line icons (UI_REDESIGN.md §3.6): drawn on a 24 pt grid, stroked at a constant width
/// with round caps and joins, colored by the caller. Any icon can be swapped by changing its case's
/// drawing; an icon not drawn yet maps to an SF Symbol and is listed in docs/ui-todo.md.
public enum Icon: String, CaseIterable, Sendable {
    case home, dictionary, snippets, style, settings, help, bell, user, sidebar, info, mic, stop, close
    case copy, paste, check, warning, clock, plus, search, trash, chevronRight, chevronLeft, chevronDown
    case keyboard, globe, lock, play, retry, edit
}

/// Stroke width for the icon set, in points at any size.
public enum IconTokens {
    public static let stroke: CGFloat = 1.5 // source: assumed (§3.6) // MEASURE
    public static let grid: CGFloat = 24
}

/// The icon's outline on a 24 × 24 grid, scaled into the rect.
public struct IconShape: Shape {
    let icon: Icon

    public init(_ icon: Icon) {
        self.icon = icon
    }

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / IconTokens.grid
        let ox = rect.midX - IconTokens.grid * s / 2, oy = rect.midY - IconTokens.grid * s / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s) }
        func line(_ path: inout Path, _ pts: [(CGFloat, CGFloat)]) {
            guard let first = pts.first else { return }
            path.move(to: p(first.0, first.1))
            for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
        }
        func dot(_ path: inout Path, _ x: CGFloat, _ y: CGFloat) {
            path.move(to: p(x, y))
            path.addLine(to: p(x, y + 0.01))
        }
        func circle(_ path: inout Path, _ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) {
            path.addEllipse(in: r(cx - radius, cy - radius, radius * 2, radius * 2))
        }
        func arc(_ path: inout Path, _ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, _ from: Double, _ to: Double, clockwise: Bool = false) {
            path.addArc(center: p(cx, cy), radius: radius * s, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: clockwise)
        }
        var path = Path()
        switch icon {
        case .home:
            for (x, y) in [(3.75, 3.75), (13.25, 3.75), (3.75, 13.25), (13.25, 13.25)] {
                path.addRoundedRect(in: r(x, y, 7, 7), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            }
        case .dictionary:
            path.addRoundedRect(in: r(5, 3.5, 14, 17), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            line(&path, [(8.5, 3.5), (8.5, 20.5)])
            line(&path, [(11.5, 8), (16, 8)])
        case .snippets:
            line(&path, [(13.5, 20.5), (6, 20.5)])
            path.addQuadCurve(to: p(3.5, 18), control: p(3.5, 20.5))
            line(&path, [(3.5, 18), (3.5, 6)])
            path.addQuadCurve(to: p(6, 3.5), control: p(3.5, 3.5))
            line(&path, [(6, 3.5), (18, 3.5)])
            path.addQuadCurve(to: p(20.5, 6), control: p(20.5, 3.5))
            line(&path, [(20.5, 6), (20.5, 13.5), (13.5, 20.5), (13.5, 15.5)])
            path.addQuadCurve(to: p(15.5, 13.5), control: p(13.5, 13.5))
            line(&path, [(15.5, 13.5), (20.5, 13.5)])
        case .style:
            line(&path, [(5, 7.5), (5, 4.5), (19, 4.5), (19, 7.5)])
            line(&path, [(12, 4.5), (12, 19.5)])
            line(&path, [(9, 19.5), (15, 19.5)])
        case .settings:
            let teeth = 8
            for i in 0..<(teeth * 2) {
                let outer = i % 2 == 0
                let a0 = Double(i) / Double(teeth * 2) * 2 * .pi - .pi / Double(teeth * 2)
                let a1 = a0 + 2 * .pi / Double(teeth * 2)
                let rad: CGFloat = outer ? 9 : 7.2
                let start = p(12 + rad * CGFloat(cos(a0)), 12 + rad * CGFloat(sin(a0)))
                let end = p(12 + rad * CGFloat(cos(a1)), 12 + rad * CGFloat(sin(a1)))
                if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
                path.addLine(to: end)
            }
            path.closeSubpath()
            circle(&path, 12, 12, 3)
        case .help:
            circle(&path, 12, 12, 9)
            path.move(to: p(9.5, 9.6))
            path.addCurve(to: p(14.5, 9.6), control1: p(9.6, 6.6), control2: p(14.4, 6.6))
            path.addCurve(to: p(12, 13.2), control1: p(14.6, 11.6), control2: p(12, 11.6))
            line(&path, [(12, 13.2), (12, 14)])
            dot(&path, 12, 16.9)
        case .bell:
            path.move(to: p(5.5, 16.5))
            path.addLine(to: p(18.5, 16.5))
            path.addLine(to: p(17, 14.5))
            path.addLine(to: p(17, 10.5))
            arc(&path, 12, 10.5, 5, 0, 180, clockwise: true)
            path.addLine(to: p(7, 14.5))
            path.closeSubpath()
            arc(&path, 12, 18.6, 2, 0, 180)
        case .user:
            circle(&path, 12, 12, 9)
            circle(&path, 12, 10, 3.2)
            path.move(to: p(6.4, 18.3))
            path.addCurve(to: p(17.6, 18.3), control1: p(8, 14.7), control2: p(16, 14.7))
        case .sidebar:
            path.addRoundedRect(in: r(3.5, 5, 17, 14), cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s))
            line(&path, [(9.5, 5), (9.5, 19)])
        case .info:
            circle(&path, 12, 12, 9)
            line(&path, [(12, 11), (12, 16.5)])
            dot(&path, 12, 7.8)
        case .warning:
            circle(&path, 12, 12, 9)
            line(&path, [(12, 7.5), (12, 13)])
            dot(&path, 12, 16.3)
        case .mic:
            path.addRoundedRect(in: r(9, 3.5, 6, 11), cornerSize: CGSize(width: 3 * s, height: 3 * s))
            arc(&path, 12, 11, 6, 0, 180)
            line(&path, [(12, 17), (12, 20.5)])
        case .stop:
            path.addRoundedRect(in: r(7, 7, 10, 10), cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s))
        case .close:
            line(&path, [(6.5, 6.5), (17.5, 17.5)])
            line(&path, [(17.5, 6.5), (6.5, 17.5)])
        case .copy:
            path.addRoundedRect(in: r(9, 9, 11, 11), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            line(&path, [(15, 9), (15, 6)])
            path.addQuadCurve(to: p(13, 4), control: p(15, 4))
            line(&path, [(13, 4), (6, 4)])
            path.addQuadCurve(to: p(4, 6), control: p(4, 4))
            line(&path, [(4, 6), (4, 13)])
            path.addQuadCurve(to: p(6, 15), control: p(4, 15))
            line(&path, [(6, 15), (9, 15)])
        case .paste:
            path.addRoundedRect(in: r(5.5, 5, 13, 16), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            path.addRoundedRect(in: r(9, 3, 6, 4), cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
        case .check:
            line(&path, [(5, 12.5), (10, 17.5), (19, 7)])
        case .clock:
            circle(&path, 12, 12, 9)
            line(&path, [(12, 7), (12, 12), (15.5, 14)])
        case .plus:
            line(&path, [(12, 5), (12, 19)])
            line(&path, [(5, 12), (19, 12)])
        case .search:
            circle(&path, 10.5, 10.5, 6)
            line(&path, [(15, 15), (20, 20)])
        case .trash:
            line(&path, [(4.5, 7), (19.5, 7)])
            line(&path, [(9.5, 7), (9.5, 4.5), (14.5, 4.5), (14.5, 7)])
            line(&path, [(6.5, 7), (7.5, 19)])
            path.addQuadCurve(to: p(9, 20.5), control: p(7.6, 20.5))
            line(&path, [(9, 20.5), (15, 20.5)])
            path.addQuadCurve(to: p(16.5, 19), control: p(16.4, 20.5))
            line(&path, [(16.5, 19), (17.5, 7)])
        case .chevronRight:
            line(&path, [(9.5, 6), (15.5, 12), (9.5, 18)])
        case .chevronLeft:
            line(&path, [(14.5, 6), (8.5, 12), (14.5, 18)])
        case .chevronDown:
            line(&path, [(6, 9.5), (12, 15.5), (18, 9.5)])
        case .keyboard:
            path.addRoundedRect(in: r(3, 6.5, 18, 11), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            for x in [7, 10, 13, 16] as [CGFloat] { dot(&path, x, 10) }
            line(&path, [(8.5, 14), (15.5, 14)])
        case .globe:
            circle(&path, 12, 12, 9)
            path.addEllipse(in: r(8, 3, 8, 18))
            line(&path, [(3, 12), (21, 12)])
        case .lock:
            path.addRoundedRect(in: r(6, 10.5, 12, 10), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            line(&path, [(8.5, 10.5), (8.5, 8)])
            arc(&path, 12, 8, 3.5, 180, 0)
            line(&path, [(15.5, 8), (15.5, 10.5)])
        case .play:
            line(&path, [(8, 5.5), (18.5, 12), (8, 18.5)])
            path.closeSubpath()
        case .retry:
            arc(&path, 12, 12, 7.5, -150, 160)
            line(&path, [(4.6, 4.5), (5.4, 8.3), (9.2, 7.6)])
        case .edit:
            line(&path, [(4.5, 19.5), (5.5, 15), (15.5, 5), (19, 8.5), (9, 18.5)])
            path.closeSubpath()
            line(&path, [(13, 7.5), (16.5, 11)])
        }
        return path
    }
}

/// An icon at a size, in a color, stroked at the set's constant width.
public struct IconView: View {
    let icon: Icon
    let size: CGFloat
    let color: Color
    let filled: Bool

    public init(_ icon: Icon, size: CGFloat = V1Hub.iconGlyph, color: Color, filled: Bool = false) {
        self.icon = icon
        self.size = size
        self.color = color
        self.filled = filled
    }

    public var body: some View {
        Group {
            if filled {
                IconShape(icon).fill(color)
            } else {
                IconShape(icon).stroke(color, style: StrokeStyle(lineWidth: IconTokens.stroke, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
