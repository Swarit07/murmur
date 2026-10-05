import Foundation
import SwiftUI

/// Parses SVG path data (`M L H V C S Q T A Z`, absolute and relative) into a SwiftUI `Path`, so the
/// icons and the brand mark are drawn from the boards' own path strings (UI_REDESIGN.md v2 §3.6).
public enum SVGPath {
    public static func parse(_ data: String) -> Path {
        var path = Path()
        var tokens = Tokenizer(data)
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuad: CGPoint?

        while let next = tokens.nextCommandOrNumber() {
            if case .command(let c) = next {
                command = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                    lastQuad = nil
                }
                continue
            }
            tokens.pushBack(next)
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased().first ?? "M" {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                // Extra pairs after a move are implicit line-tos.
                command = relative ? "l" : "L"
                lastControl = nil
                lastQuad = nil
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
                lastQuad = nil
            case "H":
                guard let x = tokens.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
                lastQuad = nil
            case "V":
                guard let y = tokens.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
                lastQuad = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
                lastQuad = nil
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
                lastQuad = nil
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastQuad = c
                lastControl = nil
            case "T":
                guard let p = point() else { return path }
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addQuadCurve(to: p, control: c)
                current = p
                lastQuad = c
                lastControl = nil
            case "A":
                guard let rx = tokens.number(), let ry = tokens.number(), let rotation = tokens.number(),
                      let large = tokens.number(), let sweep = tokens.number(), let p = point() else { return path }
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry, rotation: rotation, large: large != 0, sweep: sweep != 0)
                current = p
                lastControl = nil
                lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    /// An SVG elliptical arc as cubic Béziers (SVG 1.1 implementation notes, F.6).
    static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        func onEllipse(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi, y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi, y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        var a = theta1
        for i in 0..<segments {
            let b = a + step
            let start = onEllipse(a), end = i == segments - 1 ? p1 : onEllipse(b)
            let d1 = derivative(a), d2 = derivative(b)
            path.addCurve(to: end, control1: CGPoint(x: start.x + t * d1.x, y: start.y + t * d1.y),
                          control2: CGPoint(x: end.x - t * d2.x, y: end.y - t * d2.y))
            a = b
        }
    }

    enum Token {
        case command(Character)
        case number(CGFloat)
    }

    struct Tokenizer {
        let chars: [Character]
        var index = 0
        var pending: Token?

        init(_ s: String) {
            chars = Array(s)
        }

        mutating func pushBack(_ token: Token) { pending = token }

        mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\t" { index += 1 }
        }

        mutating func nextCommandOrNumber() -> Token? {
            if let p = pending { pending = nil; return p }
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter && c != "e" && c != "E" {
                index += 1
                return .command(c)
            }
            return readNumber().map { .number($0) }
        }

        mutating func number() -> CGFloat? {
            if let p = pending {
                pending = nil
                if case .number(let n) = p { return n }
                pending = p
                return nil
            }
            skipSeparators()
            return readNumber()
        }

        /// One number: sign, digits, at most one dot, optional exponent. "0-3" and "1.5.5" split correctly.
        mutating func readNumber() -> CGFloat? {
            var s = ""
            var seenDot = false, seenExp = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { s.append(chars[index]); index += 1 }
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    s.append(c)
                } else if c == "." && !seenDot && !seenExp {
                    seenDot = true
                    s.append(c)
                } else if (c == "e" || c == "E") && !seenExp && !s.isEmpty {
                    seenExp = true
                    s.append(c)
                    if index + 1 < chars.count, chars[index + 1] == "-" || chars[index + 1] == "+" { index += 1; s.append(chars[index]) }
                } else {
                    break
                }
                index += 1
            }
            return Double(s).map { CGFloat($0) }
        }
    }
}
