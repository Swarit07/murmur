import ApplicationServices
import Foundation

/// Adds a leading space when a dictation lands right after a word, so consecutive dictations do not
/// run together ("…the old one.Let's push…" in the Milestone 0 replay).
public enum SmartSpacing {
    /// `before` is the character just before the cursor, or nil when the field does not say.
    public static func adjust(_ text: String, before: Character?) -> String {
        guard let before, let first = text.first else { return text }
        if before.isWhitespace || before.isNewline { return text }
        if "([{\u{201C}\u{2018}\"'/-@#".contains(before) { return text }
        if first.isWhitespace || ".,!?;:)]}\u{201D}\u{2019}%".contains(first) { return text }
        return " " + text
    }

    /// Reads the character before the insertion point through Accessibility. Nil when the element has
    /// no text range (many custom editors), so nothing is added in doubt.
    public static func characterBeforeCursor(of element: AXUIElement?) -> Character? {
        guard let element else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location > 0 else {
            return nil
        }
        var previous = CFRange(location: range.location - 1, length: 1)
        guard let previousValue = AXValueCreate(.cfRange, &previous) else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, previousValue, &text) == .success,
              let string = text as? String else { return nil }
        return string.last
    }
}
