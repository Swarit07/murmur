import Foundation
import Security

/// Settings live in UserDefaults (spec section 2). Secrets never do: see `Keychain`.
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()
    public static let didChange = Notification.Name("MurmurSettingsDidChange")

    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    enum Key: String {
        case engine, cleanupProvider, cleanupLevel, keyboardLayout, showInDock, soundsEnabled, microphoneUID, keepAudio, showFlowBar, debugMenu
    }

    private func string(_ key: Key, _ fallback: String) -> String { defaults.string(forKey: key.rawValue) ?? fallback }

    private func set(_ value: Any?, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: Self.didChange, object: key.rawValue)
    }

    /// Speech engine id (EngineCatalog). Default from the Milestone 0 bake-off.
    public var engine: String {
        get { string(.engine, "parakeet-ultra") }
        set { set(newValue, .engine) }
    }

    /// Cleanup provider id (CleanupCatalog). Default from the Milestone 0 bake-off.
    public var cleanupProvider: String {
        get { string(.cleanupProvider, "mlx:qwen3.5-4b") }
        set { set(newValue, .cleanupProvider) }
    }

    /// "none", "light" or "medium".
    public var cleanupLevel: String {
        get { string(.cleanupLevel, "light") }
        set { set(newValue, .cleanupLevel) }
    }

    /// "apple" uses Fn (Globe); "other" uses Ctrl+Option.
    public var keyboardLayout: String {
        get { string(.keyboardLayout, "apple") }
        set { set(newValue, .keyboardLayout) }
    }

    public var showInDock: Bool {
        get { defaults.bool(forKey: Key.showInDock.rawValue) }
        set { set(newValue, .showInDock) }
    }

    public var soundsEnabled: Bool {
        get { defaults.object(forKey: Key.soundsEnabled.rawValue) as? Bool ?? true }
        set { set(newValue, .soundsEnabled) }
    }

    /// Core Audio UID of the chosen input device; nil follows the system default.
    public var microphoneUID: String? {
        get { defaults.string(forKey: Key.microphoneUID.rawValue) }
        set { set(newValue, .microphoneUID) }
    }

    /// Show the idle Flow Bar at all times (A5, System). Off: it appears only while dictating.
    public var showFlowBar: Bool {
        get { defaults.object(forKey: Key.showFlowBar.rawValue) as? Bool ?? true }
        set { set(newValue, .showFlowBar) }
    }

    /// Shows the Debug submenu (force Flow Bar states, token panel, focus test).
    public var debugMenu: Bool {
        get { defaults.object(forKey: Key.debugMenu.rawValue) as? Bool ?? true }
        set { set(newValue, .debugMenu) }
    }

    /// Keep audio files for Retry and Recover (A4 shows them for 14 days).
    public var keepAudio: Bool {
        get { defaults.object(forKey: Key.keepAudio.rawValue) as? Bool ?? true }
        set { set(newValue, .keepAudio) }
    }
}

/// Generic-password items in the login Keychain, for cloud API keys (spec rule 2).
public enum Keychain {
    static let service = "com.swaritsheel.Murmur"

    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
