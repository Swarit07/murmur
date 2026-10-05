import AppKit
import AVFoundation
import Carbon.HIToolbox
import MurmurKit

@main
enum MurmurMain {
    @MainActor static let delegate = AppDelegate()

    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.delegate = delegate
            app.run()
        }
    }
}

/// Menu-bar shell (A1): no Dock icon unless Show in Dock is on, an icon that shows the dictation
/// state, and the menu in the spec's order.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = AppSettings.shared
    var store: HistoryStore!
    var controller: DictationController!
    var statusItem: NSStatusItem!
    var hotKeys: [GlobalHotKey] = []
    let windows = WindowManager()
    let sounds = Sounds()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        do {
            store = try HistoryStore()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Murmur could not open its History database."
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        controller = DictationController(settings: settings, store: store, sounds: sounds)
        controller.onStatus = { [weak self] status in self?.render(status) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.setAccessibilityLabel("Murmur")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        render(controller.status)

        // Paste and Copy last transcript: ⌃⌘V and ⌃⌘C (I7).
        let control = controlKey | cmdKey
        if let paste = GlobalHotKey(keyCode: kVK_ANSI_V, modifiers: control, action: { DispatchQueue.main.async { MainActor.assumeIsolated { Self.shared?.controller.pasteLast() } } }) {
            hotKeys.append(paste)
        }
        if let copy = GlobalHotKey(keyCode: kVK_ANSI_C, modifiers: control, action: { DispatchQueue.main.async { MainActor.assumeIsolated { Self.shared?.controller.copyLast() } } }) {
            hotKeys.append(copy)
        }

        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { note in
            let key = note.object as? String
            MainActor.assumeIsolated {
                if key == "showInDock" {
                    NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
                }
            }
        }

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        controller.start()
        if !Permissions.accessibility || !Permissions.inputMonitoring {
            showPermissions()
        }
    }

    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistory()
        return true
    }

    // MARK: Icon

    func render(_ status: DictationStatus) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let label: String
        switch status.phase {
        case .loading: symbol = "hourglass"; label = "Murmur: loading models"
        case .idle: symbol = "waveform"; label = "Murmur"
        case .recording(let handsFree): symbol = handsFree ? "waveform.badge.mic" : "waveform.circle.fill"; label = "Murmur: listening"
        case .processing: symbol = "ellipsis.circle"; label = "Murmur: processing"
        case .error: symbol = "exclamationmark.triangle"; label = "Murmur: needs attention"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        button.toolTip = status.message ?? label
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let message = controller.status.message {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }
        menu.addItem(item("Open Murmur", #selector(showHistory)))
        let paste = item("Paste last transcript", #selector(pasteLast), key: "v")
        paste.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(paste)
        let copy = item("Copy last transcript", #selector(copyLast), key: "c")
        copy.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(copy)
        menu.addItem(microphoneMenu())
        menu.addItem(.separator())
        menu.addItem(shortcutsMenu())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Check permissions…", #selector(showPermissions)))
        menu.addItem(.separator())
        let info = NSMenuItem(title: "\(controller.engineDescription) · \(controller.cleanupDescription)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(item("Quit Murmur", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    func menuDidClose(_ menu: NSMenu) {
        // Clicking the icon dismisses a notice (spec: Paste error leaves on a click on the app icon).
        controller.clearMessage()
    }

    func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    func microphoneMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let systemDefault = item("System default", #selector(chooseMicrophone(_:)))
        systemDefault.representedObject = nil
        systemDefault.state = settings.microphoneUID == nil ? .on : .off
        sub.addItem(systemDefault)
        sub.addItem(.separator())
        for device in AudioDevices.inputs() {
            let entry = item(device.name + (device.isDefault ? " (default)" : ""), #selector(chooseMicrophone(_:)))
            entry.representedObject = device.uid
            entry.state = settings.microphoneUID == device.uid ? .on : .off
            sub.addItem(entry)
        }
        parent.submenu = sub
        return parent
    }

    func shortcutsMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let apple = settings.keyboardLayout != "other"
        for line in apple
            ? ["Hold Fn (🌐) to talk", "Double-tap Fn or press Fn+Space for hands-free", "Esc cancels"]
            : ["Hold Control+Option to talk", "Press Control+Option+Space for hands-free", "Esc cancels"] {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            sub.addItem(info)
        }
        sub.addItem(.separator())
        let fn = item("Use Fn (Apple keyboard)", #selector(chooseKeyboard(_:)))
        fn.representedObject = "apple"
        fn.state = apple ? .on : .off
        let other = item("Use Control+Option (other keyboards)", #selector(chooseKeyboard(_:)))
        other.representedObject = "other"
        other.state = apple ? .off : .on
        sub.addItem(fn)
        sub.addItem(other)
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    @objc func pasteLast() { controller.pasteLast() }
    @objc func copyLast() { controller.copyLast() }

    @objc func chooseMicrophone(_ sender: NSMenuItem) {
        settings.microphoneUID = sender.representedObject as? String
    }

    @objc func chooseKeyboard(_ sender: NSMenuItem) {
        settings.keyboardLayout = sender.representedObject as? String ?? "apple"
    }

    @objc func showHistory() { windows.showHistory(store: store) }
    @objc func showSettings() { windows.showSettings(settings: settings) }
    @objc func showPermissions() {
        windows.showPermissions { [weak self] in self?.controller.startKeyTap() }
    }
}
