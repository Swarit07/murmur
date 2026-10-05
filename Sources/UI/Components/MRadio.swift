import SwiftUI

/// A 14 pt radio mark (§4): empty is a 1 pt `border-control` ring, selected a 4.5 pt ink ring. It is
/// drawn by selectable cards; the card is the control.
public struct MRadio: View {
    @Environment(\.theme) private var theme
    let selected: Bool

    public init(selected: Bool) {
        self.selected = selected
    }

    public var body: some View {
        Circle()
            .strokeBorder(selected ? theme.colors.inkFill.color : theme.colors.borderControl.color,
                          lineWidth: selected ? HubGeometry.radioSelectedRing : Stroke.hairline)
            .frame(width: HubGeometry.radio, height: HubGeometry.radio)
            .accessibilityHidden(true)
    }
}
