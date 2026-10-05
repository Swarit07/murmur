import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

public protocol PasteSending: Sendable {
    /// Posts Cmd+V (or an equivalent) to the frontmost app. Returns false if nothing could be sent.
    /// Main thread only: the keyboard-layout lookup (Text Input Sources) asserts it on macOS 26 and later.
    @MainActor func sendPaste(to pid: pid_t) -> Bool
    /// I9: types the text as Unicode key events instead of pasting. Returns false if nothing was sent.
    @MainActor func type(_ text: String) async -> Bool
}

/// Cmd+V resolved for the active keyboard layout, with the Edit > Paste menu item through
/// Accessibility as the fallback.
public struct SystemPasteSender: PasteSending {
    public init() {}

    @MainActor
    public func sendPaste(to pid: pid_t) -> Bool {
        if postCommandV() { return true }
        return pressPasteMenuItem(pid: pid)
    }

    /// Unicode key events in chunks of whole characters (never splitting an emoji), Return for line
    /// breaks, and a short pause between chunks so the app keeps up.
    @MainActor
    public func type(_ text: String) async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let source = CGEventSource(stateID: .privateState)
        func post(_ units: [UniChar]) {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cgSessionEventTap)
            }
        }
        var chunk: [UniChar] = []
        for character in text {
            if character == "\n" || character == "\r\n" {
                if !chunk.isEmpty { post(chunk); chunk = [] }
                KeyPresser.pressReturn()
                try? await Task.sleep(for: .milliseconds(4))
                continue
            }
            let units = Array(String(character).utf16)
            if chunk.count + units.count > 16 {
                post(chunk)
                chunk = []
                try? await Task.sleep(for: .milliseconds(4))
            }
            chunk += units
        }
        if !chunk.isEmpty { post(chunk) }
        return true
    }

    /// Key code that types "v" under the current layout (Dvorak puts it elsewhere). Looked up each
    /// time so a layout switch needs no restart.
    @MainActor
    public static func keyCodeForV() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return CGKeyCode(kVK_ANSI_V)
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> CGKeyCode in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return CGKeyCode(kVK_ANSI_V) }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars
                )
                if status == noErr, length == 1, chars[0] == UniChar(UInt8(ascii: "v")) {
                    return CGKeyCode(code)
                }
            }
            return CGKeyCode(kVK_ANSI_V)
        }
    }

    @MainActor
    func postCommandV() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let code = Self.keyCodeForV()
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// Finds the menu item bound to Cmd+V in the app's menu bar and presses it.
    @MainActor
    func pressPasteMenuItem(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return false }
        return findPaste(in: bar as! AXUIElement, depth: 0)
    }

    @MainActor
    private func findPaste(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 4 else { return false }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return false }
        for child in list {
            var char: CFTypeRef?, mods: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &char)
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdModifiersAttribute as CFString, &mods)
            if (char as? String)?.uppercased() == "V", (mods as? Int ?? 0) == 0 {
                return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
            }
            if findPaste(in: child, depth: depth + 1) { return true }
        }
        return false
    }
}

/// Presses keys in the frontmost app (C11's Return).
public enum KeyPresser {
    @MainActor
    public static func pressReturn() {
        guard AXIsProcessTrusted() else { return }
        // A private source and no flags: the session state can still carry the Command flag of the paste
        // keystroke just posted, which would turn this into Cmd+Return.
        let source = CGEventSource(stateID: .privateState)
        let code = CGKeyCode(kVK_Return)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = []
            event.post(tap: .cgSessionEventTap)
        }
    }
}
