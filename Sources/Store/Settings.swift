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
        case engine, cleanupProvider, cleanupLevel, keyboardLayout, showInDock, soundsEnabled, microphoneUID, keepAudio, showFlowBar, debugMenu, transformsEnabled, smartFormatting, languages, shortcuts, neverStore, onboardingStep, onboardingDone, styles, commandMode, pressEnter, typingApps, unloadWhenIdle, appearance, textSize
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

    /// C1 master switch: off turns every AI edit off (rules still apply: spoken punctuation, dictionary,
    /// snippets).
    public var transformsEnabled: Bool {
        get { defaults.object(forKey: Key.transformsEnabled.rawValue) as? Bool ?? true }
        set { set(newValue, .transformsEnabled) }
    }

    /// C3 Smart Formatting: spoken lists become numbered lists, long dictations get paragraphs.
    /// Command Mode (M1): off until turned on in Settings › Experimental.
    public var commandMode: Bool {
        get { defaults.bool(forKey: Key.commandMode.rawValue) }
        set { set(newValue, .commandMode) }
    }

    /// Section 7: free the models' memory after 10 minutes without dictation. On by default since reloads no
    /// longer leak (docs/mlx-unload-leak.md).
    public var unloadWhenIdle: Bool {
        get { defaults.object(forKey: Key.unloadWhenIdle.rawValue) as? Bool ?? true }
        set { set(newValue, .unloadWhenIdle) }
    }

    /// "system", "light" or "dark" (Settings › General › Appearance).
    public var appearance: String {
        get { string(.appearance, "system") }
        set { set(newValue, .appearance) }
    }

    /// "default" or "large" (Settings › General › Text size).
    public var textSize: String {
        get { string(.textSize, "default") }
        set { set(newValue, .textSize) }
    }

    /// I9: bundle ids of apps that get the text typed instead of pasted.
    public var typingApps: [String] {
        get { defaults.stringArray(forKey: Key.typingApps.rawValue) ?? [] }
        set { set(newValue, .typingApps) }
    }

    /// C11: ending a dictation with "press enter" presses Return after the paste. Off by default.
    public var pressEnter: Bool {
        get { defaults.bool(forKey: Key.pressEnter.rawValue) }
        set { set(newValue, .pressEnter) }
    }

    public var smartFormatting: Bool {
        get { defaults.object(forKey: Key.smartFormatting.rawValue) as? Bool ?? true }
        set { set(newValue, .smartFormatting) }
    }

    /// T3: ISO 639-1 codes the user speaks. Empty means automatic detection.
    public var languages: [String] {
        get { defaults.stringArray(forKey: Key.languages.rawValue) ?? [] }
        set { set(newValue, .languages) }
    }

    /// D8: the push-to-talk and hands-free shortcuts as JSON (stored per Mac). Nil uses the defaults for
    /// `keyboardLayout`.
    public var shortcuts: Data? {
        get { defaults.data(forKey: Key.shortcuts.rawValue) }
        set { set(newValue, .shortcuts) }
    }

    /// A9: nothing is written to History or disk (no rows, no audio).
    public var neverStore: Bool {
        get { defaults.bool(forKey: Key.neverStore.rawValue) }
        set { set(newValue, .neverStore) }
    }

    /// Onboarding resumes at this step if Murmur quits partway.
    public var onboardingStep: Int {
        get { defaults.integer(forKey: Key.onboardingStep.rawValue) }
        set { set(newValue, .onboardingStep) }
    }

    public var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone.rawValue) }
        set { set(newValue, .onboardingDone) }
    }

    /// S4: the chosen style per category ("personal", "work", "email", "other") as JSON.
    public var styles: [String: String] {
        get { (defaults.dictionary(forKey: Key.styles.rawValue) as? [String: String]) ?? [:] }
        set { set(newValue, .styles) }
    }

    /// The language to pass to the engine: the one chosen language, or nil for automatic.
    public var engineLanguage: String? { languages.count == 1 ? languages[0] : nil }

    /// Show the idle Flow Bar at all times (A5, System). Off: it appears only while dictating.
    public var showFlowBar: Bool {
        get { defaults.object(forKey: Key.showFlowBar.rawValue) as? Bool ?? true }
        set { set(newValue, .showFlowBar) }
    }

    /// Shows the Debug submenu (force Flow Bar states, token panel, focus test) and enables the debug hooks
    /// other processes can post to. Off by default for releases; Settings › System turns it on.
    public var debugMenu: Bool {
        get { defaults.object(forKey: Key.debugMenu.rawValue) as? Bool ?? false }
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
