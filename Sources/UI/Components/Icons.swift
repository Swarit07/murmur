import SwiftUI

/// Murmur's line icons (UI_REDESIGN.md v2 §3.6): the boards' own SVG paths on a 24 pt grid, stroked
/// with round caps and joins, colored by the caller. The 24 core icons come from the Components
/// board's `ICONS` array; the Hub and Flow Bar boards add the rest inline.
public enum Icon: String, CaseIterable, Sendable {
    // Core set (Components board)
    case mic, wave, stop, cancel, check, retry, clipboard, alert, textfield, hotkey, handsFree, history
    case home, dictionary, snippet, style, settings, cleanup, local, shield, globe, branch, star, download
    // Hub and Flow Bar boards
    case search, bell, copy, trash, edit, plus, chevronRight, chevronLeft, chevronDown, chevronUpDown
    case info, help, mail, chat, lines, code, note, micOff, arrowRight
}

/// Stroke widths in grid units: the boards scale the stroke with the icon, and draw small icons with
/// a slightly heavier grid stroke so they keep their weight.
public enum IconTokens {
    public static let grid: CGFloat = 24 // source: board
    /// 18 pt and larger (sidebar).
    public static let stroke: CGFloat = 1.6 // source: board
    /// 15-17 pt (copy, paste, card icons).
    public static let strokeMedium: CGFloat = 1.7 // source: board
    /// 14 pt and smaller (search, info).
    public static let strokeSmall: CGFloat = 1.8 // source: board
    public static let mediumBelow: CGFloat = 18 // source: board
    public static let smallBelow: CGFloat = 15 // source: board

    /// The grid stroke the boards use at a drawn size.
    public static func gridStroke(for size: CGFloat) -> CGFloat {
        size < smallBelow ? strokeSmall : size < mediumBelow ? strokeMedium : stroke
    }
}

extension Icon {
    enum Element {
        case path(String)
        case circle(CGFloat, CGFloat, CGFloat)
        case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    }

    var elements: [Element] {
        switch self {
        case .mic: [.path("M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z M5 11a7 7 0 0 0 14 0 M12 18v3")]
        case .wave: [.path("M3 12h2 M7 9v6 M11 5v14 M15 8v8 M19 11v2")]
        case .stop: [.path("M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z")]
        case .cancel: [.path("M6 6l12 12 M18 6L6 18")]
        case .check: [.path("M5 12.5l4.5 4.5L19 7")]
        case .retry: [.path("M20 12a8 8 0 1 1-2.3-5.6 M20 4v5h-5")]
        case .clipboard: [.path("M9 3.5h6v3H9z M8 5H6v15.5h12V5h-2")]
        case .alert: [.path("M12 4l9 16H3z M12 10v4 M12 17v.5")]
        case .textfield: [.rect(3, 7, 18, 10, 2.5), .path("M8 10v4")]
        case .hotkey: [.path("M5 5h14v14H5z M9 15l3-6 3 6 M10 13h4")]
        case .handsFree: [.path("M12 3a3 3 0 0 0-3 3v5a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z M6 11a6 6 0 0 0 12 0 M8 20h8 M12 17v3 M3 8v4 M21 8v4")]
        case .history: [.path("M4 12a8 8 0 1 0 2.3-5.6 M4 4v4h4 M12 8v4l3 2")]
        case .home: [.path("M4 11l8-7 8 7v9h-5v-6H9v6H4z")]
        case .dictionary: [.path("M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z M5 17a3 3 0 0 1 3-3h10")]
        case .snippet: [.path("M9 4C7 4 6 5 6 7v2c0 1.5-1 3-2 3 1 0 2 1.5 2 3v2c0 2 1 3 3 3 M15 4c2 0 3 1 3 3v2c0 1.5 1 3 2 3-1 0-2 1.5-2 3v2c0 2-1 3-3 3")]
        case .style, .edit: [.path("M4 20l4-1 11-11-3-3L5 16z M14 7l3 3")]
        case .settings: [.path("M4 7h9 M17 7h3 M4 17h3 M11 17h9"), .circle(15, 7, 2), .circle(9, 17, 2)]
        case .cleanup: [.path("M4 20l7-7 M14 4l1.2 2.8L18 8l-2.8 1.2L14 12l-1.2-2.8L10 8l2.8-1.2z M19 14l.6 1.4 1.4.6-1.4.6L19 18l-.6-1.4L17 16l1.4-.6z")]
        case .local: [.path("M4 5h16v11H4z M9 20h6 M12 16v4 M10 10.5l1.5 1.5 3-3")]
        case .shield: [.path("M12 3l7 3v6c0 4-3 7.5-7 9-4-1.5-7-5-7-9V6z")]
        case .globe: [.path("M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18 M3 12h18 M12 3c3 3 3 15 0 18 M12 3c-3 3-3 15 0 18")]
        case .branch: [.path("M6 3v12 M6 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6 M18 6a3 3 0 1 0 0-.01 M18 9c0 4-6 4-12 7")]
        case .star: [.path("M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z")]
        case .download: [.path("M12 4v11 M7 10l5 5 5-5 M5 20h14")]
        case .search: [.circle(11, 11, 6.5), .path("M20 20l-4-4")]
        case .bell: [.path("M6 16v-5a6 6 0 1 1 12 0v5l1.5 2h-15z M10 20.5a2 2 0 0 0 4 0")]
        case .copy: [.rect(8, 8, 12, 12, 2.5), .path("M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2")]
        case .trash: [.path("M5 7h14 M10 7V5h4v2 M7 7l1 13h8l1-13")]
        case .plus: [.path("M12 5v14 M5 12h14")]
        case .chevronRight: [.path("M9 6l6 6-6 6")]
        case .chevronLeft: [.path("M15 6l-6 6 6 6")]
        case .chevronDown: [.path("M6 9l6 6 6-6")]
        case .chevronUpDown: [.path("M7 10l5-5 5 5 M7 14l5 5 5-5")]
        case .info: [.circle(12, 12, 8.5), .path("M12 11v5 M12 7.8v.1")]
        case .help: [.circle(12, 12, 8.5), .path("M9.7 9.6a2.4 2.4 0 1 1 3.4 2.2c-.7.4-1.1.9-1.1 1.6 M12 16.5v.1")]
        case .mail: [.path("M3.5 6.5h17v11h-17z M4 7l8 6 8-6")]
        case .chat: [.path("M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-7l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z")]
        case .lines: [.path("M4 6h16 M4 12h10 M4 18h13")]
        case .code: [.path("M9 8l-4 4 4 4 M15 8l4 4-4 4")]
        case .note: [.path("M6 3.5h9l3 3v14H6z M9 11h6 M9 15h6")]
        case .micOff: [.path("M15 9.5V6a3 3 0 0 0-5.6-1.5 M9 9v3a3 3 0 0 0 4.6 2.5 M5 11a7 7 0 0 0 11.5 5.4 M19 11a7 7 0 0 1-.6 2.8 M12 18v3 M4 4l16 16")]
        case .arrowRight: [.path("M5 12h14 M13 6l6 6-6 6")]
        }
    }

    /// The outline on the 24 × 24 grid.
    var gridPath: Path {
        var path = Path()
        for element in elements {
            switch element {
            case .path(let d): path.addPath(SVGPath.parse(d))
            case .circle(let cx, let cy, let r): path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            case .rect(let x, let y, let w, let h, let rx): path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: rx, height: rx))
            }
        }
        return path
    }
}

/// The icon's outline on its 24 × 24 grid, scaled into the rect.
public struct IconShape: Shape {
    let path: Path

    public init(_ icon: Icon) {
        path = icon.gridPath
    }

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / IconTokens.grid
        let ox = rect.midX - IconTokens.grid * s / 2, oy = rect.midY - IconTokens.grid * s / 2
        return path.applying(CGAffineTransform(translationX: ox, y: oy).scaledBy(x: s, y: s))
    }
}

/// An icon at a size, in a color, stroked as the boards stroke it (grid stroke × size / 24).
public struct IconView: View {
    let icon: Icon
    let size: CGFloat
    let color: Color
    let gridStroke: CGFloat?

    public init(_ icon: Icon, size: CGFloat = HubGeometry.iconGlyph, color: Color, gridStroke: CGFloat? = nil) {
        self.icon = icon
        self.size = size
        self.color = color
        self.gridStroke = gridStroke
    }

    public var body: some View {
        let stroke = (gridStroke ?? IconTokens.gridStroke(for: size)) * size / IconTokens.grid
        IconShape(icon)
            .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
