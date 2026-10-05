import Foundation

/// C11: a dictation that ends with "press enter" presses Return after the paste (when turned on).
public enum PressEnter {
    /// The transcript without its trailing "press enter", and whether it had one.
    public static func split(_ text: String, enabled: Bool) -> (text: String, pressEnter: Bool) {
        guard enabled, let range = text.range(of: #"(?i)(^|[\s,.;:!?]+)press enter[.!]?$"#, options: .regularExpression) else {
            return (text, false)
        }
        return (String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces), true)
    }
}
