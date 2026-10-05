import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

public enum Permissions {
    /// Accessibility: needed to read the focused element and to post the paste keystroke.
    public static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds this process to the Accessibility list.
    public static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Input Monitoring: needed for the listen-only event tap that sees a held key.
    public static var inputMonitoring: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    public static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    /// Another app (often a password field or a terminal setting) holding Secure Keyboard Entry.
    public static var secureEventInput: Bool { IsSecureEventInputEnabled() }

    /// What the Globe/Fn key does: 0 nothing, 1 change input source, 2 emoji, 3 dictation. Nil if unset.
    public static var fnUsageType: Int? {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
    }
}

/// The app and element that had focus when the key went down. Insertion only happens if focus is
/// still the same (I3).
public struct FocusSnapshot: @unchecked Sendable {
    public let pid: pid_t
    public let bundleId: String?
    public let appName: String?
    public let element: AXUIElement?
    public let role: String?
    public let subrole: String?
    public let isSecure: Bool
    public let isEditable: Bool

    public init(
        pid: pid_t, bundleId: String?, appName: String? = nil, element: AXUIElement? = nil,
        role: String? = nil, subrole: String? = nil, isSecure: Bool = false, isEditable: Bool = true
    ) {
        self.pid = pid
        self.bundleId = bundleId
        self.appName = appName
        self.element = element
        self.role = role
        self.subrole = subrole
        self.isSecure = isSecure
        self.isEditable = isEditable
    }

    public func sameFocus(as other: FocusSnapshot) -> Bool {
        guard pid == other.pid else { return false }
        switch (element, other.element) {
        case (nil, nil): return true
        case let (a?, b?): return CFEqual(a, b)
        default: return false
        }
    }

    public var description: String {
        "\(appName ?? "?") (\(bundleId ?? "?")) role=\(role ?? "-")\(subrole.map { "/\($0)" } ?? "")\(isSecure ? " SECURE" : "")"
    }
}

public enum FocusContext {
    static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXWebArea",
    ]

    /// Reads the frontmost app and its focused element through Accessibility.
    public static func snapshot() -> FocusSnapshot {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        // Ask Accessibility for the focused app: NSWorkspace's frontmostApplication only updates when
        // the main run loop turns, which a command line tool may not do.
        var pid: pid_t = 0
        var appValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
           let v = appValue, CFGetTypeID(v) == AXUIElementGetTypeID() {
            AXUIElementGetPid(v as! AXUIElement, &pid)
        }
        if pid == 0 { pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }
        let app = NSRunningApplication(processIdentifier: pid)
        var element: AXUIElement?
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
           let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() {
            element = (v as! AXUIElement)
        }
        let role = element.flatMap { string($0, kAXRoleAttribute) }
        let subrole = element.flatMap { string($0, kAXSubroleAttribute) }
        var editable = role.map { editableRoles.contains($0) } ?? false
        if !editable, let element {
            // Rich editors (web content, Electron) often report a generic role but a settable value.
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
                editable = true
            }
        }
        let secure = subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField" || Permissions.secureEventInput
        return FocusSnapshot(
            pid: pid, bundleId: app?.bundleIdentifier, appName: app?.localizedName, element: element,
            role: role, subrole: subrole, isSecure: secure, isEditable: editable
        )
    }

    /// The text of an editable element (its AX value), for S2's correction check.
    public static func value(of element: AXUIElement?) -> String? {
        guard let element else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.3)
        return string(element, kAXValueAttribute)
    }

    /// The address of the web page that contains `element`, for browsers and web views: walks up to
    /// the nearest web area and reads its URL. Nil outside web content.
    public static func webAddress(of element: AXUIElement?) -> URL? {
        var current = element
        for _ in 0..<40 {
            guard let node = current else { return nil }
            if string(node, kAXRoleAttribute) == "AXWebArea" {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, "AXURL" as CFString, &value) == .success, let value {
                    if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! URL) }
                    if let s = value as? String { return URL(string: s) }
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = (parent as! AXUIElement)
        }
        return nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
