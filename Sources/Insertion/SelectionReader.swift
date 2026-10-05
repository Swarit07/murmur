import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Command Mode (M2) reads what is selected in the focused field before rewriting it.
public enum SelectionReader {
    /// The selected text: "" when nothing is selected, nil when the app does not say. Accessibility
    /// first; apps that do not expose their selection get a Cmd+C, read from the clipboard, which is
    /// then put back exactly as it was.
    @MainActor
    public static func selectedText(in element: AXUIElement?, board: SystemPasteboard = SystemPasteboard()) async -> String? {
        if let element {
            AXUIElementSetMessagingTimeout(element, 0.3)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success {
                return (value as? String) ?? ""
            }
        }
        return await copySelection(board: board)
    }

    /// Cmd+C, wait up to 400 ms for the clipboard to change, read it, restore it. Nil if nothing was
    /// copied (no selection, or the app ignores Cmd+C).
    @MainActor
    static func copySelection(board: SystemPasteboard) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let saved = board.snapshot()
        let source = CGEventSource(stateID: .combinedSessionState)
        let code = keyCode(for: "c") ?? CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(20))
            if board.changeCount != saved.changeCount {
                let text = board.string()
                board.restore(saved)
                return text
            }
        }
        return nil
    }

    /// The key code that types `character` in the current layout.
    @MainActor
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let target = character.unicodeScalars.first.map({ UniChar($0.value) }) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> CGKeyCode? in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
                if status == noErr, length == 1, chars[0] == target { return CGKeyCode(code) }
            }
            return nil
        }
    }
}
