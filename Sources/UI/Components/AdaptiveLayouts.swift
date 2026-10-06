import SwiftUI

/// Two views side by side while the first keeps at least `minLeading` beside the second at its ideal
/// width; otherwise the second goes under the first. Used where a label sits beside a control (settings
/// rows), a title beside its stats, and a feature card's copy beside its samples, so a narrow window or
/// Large text reflows instead of crushing the label into one-letter lines or pushing past the edge.
public struct AdaptivePair: Layout {
    public enum Stacked: Sendable {
        /// The second view keeps its ideal width (a control under its label).
        case ideal
        /// The second view takes the full width (a samples column under the copy).
        case fill
    }

    let spacing: CGFloat
    let stackedSpacing: CGFloat
    let minLeading: CGFloat
    let alignment: VerticalAlignment
    let stacked: Stacked

    public init(spacing: CGFloat, stackedSpacing: CGFloat, minLeading: CGFloat, alignment: VerticalAlignment = .center, stacked: Stacked = .ideal) {
        self.spacing = spacing
        self.stackedSpacing = stackedSpacing
        self.minLeading = minLeading
        self.alignment = alignment
        self.stacked = stacked
    }

    struct Plan {
        var sideBySide: Bool
        var first: CGSize
        var second: CGSize
        var size: CGSize
    }

    /// Plans by proposed width and the second view's ideal size, kept for one layout pass, so placing
    /// the views doesn't measure them all again.
    public struct Cache {
        var ideal: CGSize?
        var plans: [CGFloat: Plan] = [:]
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func plan(_ proposal: ProposedViewSize, _ subviews: Subviews, _ cache: inout Cache) -> Plan {
        let key = proposal.width ?? -1
        if let cached = cache.plans[key] { return cached }
        let plan = makePlan(proposal, subviews, &cache)
        cache.plans[key] = plan
        return plan
    }

    func makePlan(_ proposal: ProposedViewSize, _ subviews: Subviews, _ cache: inout Cache) -> Plan {
        guard subviews.count == 2 else {
            let size = subviews.first?.sizeThatFits(proposal) ?? .zero
            return Plan(sideBySide: true, first: size, second: .zero, size: size)
        }
        let ideal = cache.ideal ?? subviews[1].sizeThatFits(.unspecified)
        cache.ideal = ideal
        let width = proposal.width ?? (subviews[0].sizeThatFits(.unspecified).width + spacing + ideal.width)
        let leading = width - ideal.width - spacing
        if leading >= minLeading {
            let first = subviews[0].sizeThatFits(ProposedViewSize(width: leading, height: nil))
            let second = subviews[1].sizeThatFits(ProposedViewSize(width: ideal.width, height: nil))
            return Plan(sideBySide: true, first: first, second: second, size: CGSize(width: width, height: max(first.height, second.height)))
        }
        let first = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let secondWidth = stacked == .fill ? width : min(ideal.width, width)
        let second = subviews[1].sizeThatFits(ProposedViewSize(width: secondWidth, height: nil))
        return Plan(sideBySide: false, first: first, second: second, size: CGSize(width: width, height: first.height + stackedSpacing + second.height))
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        plan(proposal, subviews, &cache).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let p = plan(ProposedViewSize(width: bounds.width, height: nil), subviews, &cache)
        guard subviews.count == 2 else {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            return
        }
        if p.sideBySide {
            func y(_ h: CGFloat) -> CGFloat {
                switch alignment {
                case .top: bounds.minY
                case .bottom: bounds.maxY - h
                default: bounds.minY + (bounds.height - h) / 2
                }
            }
            subviews[0].place(at: CGPoint(x: bounds.minX, y: y(p.first.height)),
                              proposal: ProposedViewSize(width: bounds.width - p.second.width - spacing, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.maxX - p.second.width, y: y(p.second.height)),
                              proposal: ProposedViewSize(width: p.second.width, height: nil))
        } else {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + p.first.height + stackedSpacing),
                              proposal: ProposedViewSize(width: p.second.width, height: nil))
        }
    }
}

/// Two equal columns while each gets at least `minColumn`; one column (first above second) below that.
public struct AdaptiveColumns: Layout {
    let spacing: CGFloat
    let stackedSpacing: CGFloat
    let minColumn: CGFloat

    public init(spacing: CGFloat, stackedSpacing: CGFloat, minColumn: CGFloat) {
        self.spacing = spacing
        self.stackedSpacing = stackedSpacing
        self.minColumn = minColumn
    }

    func twoColumns(_ width: CGFloat) -> Bool { (width - spacing) / 2 >= minColumn }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minColumn * 2 + spacing
        if twoColumns(width) {
            let column = (width - spacing) / 2
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + stackedSpacing * CGFloat(max(0, heights.count - 1)))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if twoColumns(bounds.width) {
            let column = (bounds.width - spacing) / 2
            for (i, view) in subviews.enumerated() {
                view.place(at: CGPoint(x: bounds.minX + CGFloat(i) * (column + spacing), y: bounds.minY), proposal: ProposedViewSize(width: column, height: nil))
            }
        } else {
            var y = bounds.minY
            for view in subviews {
                let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                view.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: nil))
                y += size.height + stackedSpacing
            }
        }
    }
}
