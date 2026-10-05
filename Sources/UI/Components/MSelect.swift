import SwiftUI

/// A select button (§4): 30 high, radius 8, paper fill, 1 pt `border-control`, 12 pt text and up/down
/// chevrons. It opens a native menu. The `navigate` variant shows a right chevron and runs an action
/// (Languages); `mono` sets the value in Geist Mono (the speech engine).
public struct MSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    let label: String
    let icon: Icon?
    let mono: Bool

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ label: String, selection: Binding<Value>, options: [(value: Value, label: String)], icon: Icon? = nil, mono: Bool = false) {
        self.label = label
        _selection = selection
        self.options = options
        self.icon = icon
        self.mono = mono
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let current = options.first { $0.value == selection }?.label ?? ""
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].label) { selection = options[i].value }
            }
        } label: {
            MSelectFace(text: current, icon: icon, trailing: .chevronUpDown, mono: mono, state: state)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: Radius.control)
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }
}

/// The "navigate" select: shows a summary and a right chevron; tapping runs the action.
public struct MNavigateSelect: View {
    let label: String
    let value: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(_ label: String, value: String, action: @escaping () -> Void) {
        self.label = label
        self.value = value
        self.action = action
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        Button(action: action) {
            MSelectFace(text: value, icon: nil, trailing: .chevronRight, mono: false, state: state)
        }
        .buttonStyle(.plain)
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .focusRing(state == .focused, radius: Radius.control)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

struct MSelectFace: View {
    @Environment(\.theme) private var theme
    let text: String
    let icon: Icon?
    let trailing: Icon
    let mono: Bool
    let state: InteractionState

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let ink = state == .disabled ? c.textTertiary.color : c.textPrimary.color
        HStack(spacing: Spacing.s8) {
            if let icon { IconView(icon, size: HubGeometry.searchIcon, color: ink) }
            Text(text).textStyle(mono ? TypeTokens.keycap.weight(400) : TypeTokens.hint).lineLimit(1)
            IconView(trailing, size: HubGeometry.selectChevron, color: ink, gridStroke: Stroke.selectChevron)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, HubGeometry.buttonPaddingHSmall)
        .frame(height: HubGeometry.selectHeight)
        .background(shape.fill(state == .disabled ? c.fillSelected.color : state == .hover ? c.fillHover.color : c.bgPanel.color))
        .overlay(shape.strokeBorder(state == .disabled ? c.borderDivider.color : c.borderControl.color, lineWidth: Stroke.hairline))
        .contentShape(shape)
    }
}
