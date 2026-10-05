import SwiftUI

/// A text field (§4): 36 high, radius 8, paper fill, 1 pt `border-control`. Focus: a 1 pt ink border
/// plus a 3 pt halo. `quote` sets the text in the italic serif (a "sounds like" hint); `secure` hides
/// it (API keys); `multiline` grows to a few lines (snippet expansions).
public struct MTextField: View {
    let placeholder: String
    @Binding var text: String
    let secure: Bool
    let multiline: Bool
    let quote: Bool
    let leading: Icon?
    let onSubmit: () -> Void
    let onCancel: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @FocusState private var focused: Bool
    @State private var hovering = false

    public init(_ placeholder: String, text: Binding<String>, secure: Bool = false, multiline: Bool = false, quote: Bool = false,
                leading: Icon? = nil, onSubmit: @escaping () -> Void = {}, onCancel: (() -> Void)? = nil) {
        self.placeholder = placeholder
        _text = text
        self.secure = secure
        self.multiline = multiline
        self.quote = quote
        self.leading = leading
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: hovering)
        let c = theme.colors
        let style = quote ? TypeTokens.quote : TypeTokens.label.weight(400)
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let isFocused = state == .focused
        HStack(spacing: Spacing.s8) {
            if let leading { IconView(leading, size: HubGeometry.searchIcon, color: c.textTertiary.color) }
            // The placeholder is drawn here rather than as the field's prompt: AppKit colors prompts with the
            // system appearance, not the theme.
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .textStyle(style)
                        .foregroundStyle(c.textTertiary.color)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else if multiline {
                        TextField("", text: $text, axis: .vertical).lineLimit(1...6)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .textStyle(style)
                .foregroundStyle(state == .disabled ? c.textTertiary.color : c.textPrimary.color)
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand { onCancel?() }
            }
            if !text.isEmpty && leading == .search {
                Button { text = "" } label: { IconView(.cancel, size: HubGeometry.searchIcon, color: c.textTertiary.color) }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, HubGeometry.fieldPaddingH)
        .padding(.vertical, multiline ? Spacing.s8 : 0)
        .frame(minHeight: HubGeometry.fieldHeight)
        .background(shape.fill(state == .disabled ? c.fillSelected.color : c.bgPanel.color))
        .overlay(shape.strokeBorder(isFocused ? c.textPrimary.color : (state == .disabled ? c.borderDivider.color : c.borderControl.color), lineWidth: Stroke.hairline))
        .background {
            // The focus halo: 3 pt of ink at 8% around the field.
            if isFocused {
                RoundedRectangle(cornerRadius: Radius.control + Stroke.fieldHalo, style: .continuous)
                    .fill(c.fieldHalo.color)
                    .padding(-Stroke.fieldHalo)
            }
        }
        .contentShape(shape)
        .onTapGesture { focused = true }
        .onHover { hovering = $0 }
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

/// A search field: a 14 pt leading magnifier and a clear button.
public struct MSearchField: View {
    let placeholder: String
    @Binding var text: String

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    public var body: some View {
        MTextField(placeholder, text: $text, leading: .search, onCancel: { text = "" })
    }
}
