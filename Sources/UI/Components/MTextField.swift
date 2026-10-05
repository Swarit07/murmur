import SwiftUI

/// A 40-point text field (§4): field fill, control border, focus ring, placeholder in placeholder ink.
/// `secure` hides the text (API keys); `multiline` grows to a few lines.
public struct MTextField: View {
    let placeholder: String
    @Binding var text: String
    let secure: Bool
    let multiline: Bool
    let leading: Icon?
    let onSubmit: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedInteraction) private var forced
    @FocusState private var focused: Bool

    public init(_ placeholder: String, text: Binding<String>, secure: Bool = false, multiline: Bool = false, leading: Icon? = nil,
                onSubmit: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        _text = text
        self.secure = secure
        self.multiline = multiline
        self.leading = leading
        self.onSubmit = onSubmit
    }

    public var body: some View {
        let state = resolvedState(forced: forced, enabled: isEnabled, pressed: false, focused: focused, hovering: false)
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: HubGeometry.fieldRadius, style: .continuous)
        HStack(spacing: Spacing.xs) {
            if let leading { IconView(leading, size: HubGeometry.iconGlyph, color: c.textSecondary.color) }
            // The placeholder is drawn here rather than as the field's prompt: AppKit colors prompts with the
            // system appearance, not the theme.
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .textStyle(TypeTokens.body)
                        .foregroundStyle(state == .disabled ? c.textDisabled.color : c.textPlaceholder.color)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else if multiline {
                        TextField("", text: $text, axis: .vertical).lineLimit(1...4)
                    } else {
                        TextField("", text: $text)
                    }
                }
            }
            .textFieldStyle(.plain)
            .textStyle(TypeTokens.body)
            .foregroundStyle(state == .disabled ? c.textDisabled.color : c.textPrimary.color)
            .focused($focused)
            .onSubmit(onSubmit)
            if !text.isEmpty && leading == .search {
                Button { text = "" } label: { IconView(.close, size: HubGeometry.checkGlyph, color: c.textSecondary.color) }
                    .buttonStyle(.plain)
                    .help("Clear")
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, multiline ? Spacing.xs : 0)
        .frame(minHeight: HubGeometry.fieldHeight)
        .background(shape.fill(c.bgField.color))
        .overlay(shape.strokeBorder(c.borderControl.color.opacity(state == .disabled ? OpacityTokens.disabled : 1), lineWidth: HubGeometry.hairline))
        .focusRing(state == .focused, radius: HubGeometry.fieldRadius)
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

/// A search field: a leading magnifier and a clear button.
public struct MSearchField: View {
    let placeholder: String
    @Binding var text: String

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    public var body: some View {
        MTextField(placeholder, text: $text, leading: .search)
    }
}
