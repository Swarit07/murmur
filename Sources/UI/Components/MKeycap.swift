import SwiftUI

/// A key cap (§4). Inline: 20 high, radius 5, mono 10. Standard: 30 high, radius 7, mono 12, padding
/// 0 × 10. Paper fill (window fill inside panels), a 1 pt ink ring and a 2 pt bottom edge, so it reads
/// as a key. Pressed: ink with `on-ink` text, 1 pt down.
public struct MKeycap: View {
    public enum Size: Sendable { case inline, regular }
    let label: String
    let size: Size
    let pressed: Bool
    let onWindow: Bool

    @Environment(\.theme) private var theme

    /// `onWindow` uses the window fill, for key caps sitting on a paper panel.
    public init(_ label: String, size: Size = .regular, pressed: Bool = false, onWindow: Bool = false) {
        self.label = label
        self.size = size
        self.pressed = pressed
        self.onWindow = onWindow
    }

    public var body: some View {
        let c = theme.colors
        let inline = size == .inline
        let radius = inline ? Radius.keycapSmall : Radius.keycap
        let height = inline ? HubGeometry.keycapInlineHeight : HubGeometry.keycapHeight
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Text(label)
            .textStyle(inline ? TypeTokens.keycapInline : TypeTokens.keycap)
            .foregroundStyle(pressed ? c.onInk.color : c.textPrimary.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, inline ? HubGeometry.keycapPaddingHInline : HubGeometry.keycapPaddingH)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(shape.fill(pressed ? c.inkFill.color : (onWindow ? c.bgWindow.color : c.bgPanel.color)))
            .overlay {
                if !pressed {
                    shape.strokeBorder(c.edgeKey.color, lineWidth: Stroke.hairline)
                    // The bottom edge: a 2 pt inset band along the lower side.
                    shape.inset(by: Stroke.hairline / 2)
                        .stroke(c.edgeList.color, lineWidth: Stroke.keycapBottom)
                        .mask(alignment: .bottom) { Rectangle().frame(height: Stroke.keycapBottom + Stroke.hairline) }
                }
            }
            .offset(y: pressed ? theme.motion.offset(MotionTokens.pressDrop) : 0)
            .accessibilityLabel(label)
    }
}

/// A shortcut as key caps: "⌥" "Space".
public struct MShortcut: View {
    let keys: [String]
    let size: MKeycap.Size
    let onWindow: Bool

    public init(_ keys: [String], size: MKeycap.Size = .regular, onWindow: Bool = false) {
        self.keys = keys
        self.size = size
        self.onWindow = onWindow
    }

    public var body: some View {
        HStack(spacing: Spacing.s4) {
            ForEach(keys.indices, id: \.self) { MKeycap(keys[$0], size: size, onWindow: onWindow) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}
