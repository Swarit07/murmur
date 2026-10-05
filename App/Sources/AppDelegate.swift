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
    var flowBar: FlowBarWiring!
    var focusTest: FocusTest?
    var hub: HubModel!
    var onboarding: OnboardingModel?
    var permissionTimer: Timer?
    var lastPermissions = PermissionSnapshot.current()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        installMainMenu()
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
        flowBar = FlowBarWiring(app: self)
        controller.onStatus = { [weak self] status in
            self?.render(status)
            self?.flowBar.render(status)
        }
        hub = HubModel(controller: controller, store: store)
        controller.onLevel = { [weak self] level in
            self?.flowBar.model.push(level: level)
            self?.hub.push(level: level)
        }

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

        // Lets a script start the focus test (Debug menu must be on): the gate can run hands-off.
        // Design review: saves PNGs of the Hub pages and Flow Bar states to the data folder.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.snapshot"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.saveSnapshots()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.runFocusTest"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.runFocusTest(delay: 2)
            }
        }

        controller.start()
        startPermissionWatchdog()
        if !settings.onboardingDone {
            showOnboarding()
        } else if !PermissionSnapshot.current().allGranted {
            showHub(.general)
        }
    }

    // MARK: Permissions watchdog (A3)

    /// Notices revoked permissions within two seconds, tells the user where to fix them, and picks the
    /// shortcut back up once Input Monitoring is granted again. Pasting already fails closed without
    /// Accessibility (the text stays on the clipboard and in History).
    func startPermissionWatchdog() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermissions() }
        }
    }

    func checkPermissions() {
        let now = PermissionSnapshot.current()
        defer { lastPermissions = now }
        guard now != lastPermissions else { return }
        var lost: [String] = []
        if lastPermissions.microphone && !now.microphone { lost.append("Microphone") }
        if lastPermissions.accessibility && !now.accessibility { lost.append("Accessibility") }
        if lastPermissions.inputMonitoring && !now.inputMonitoring { lost.append("Input Monitoring") }
        if !lost.isEmpty {
            controller.notice("Murmur lost the \(lost.joined(separator: " and ")) permission. Open Murmur › Settings › General to turn it back on.")
        }
        if now.inputMonitoring && !lastPermissions.inputMonitoring { controller.startKeyTap() }
        if now.allGranted && !lastPermissions.allGranted { controller.clearMessage() }
    }

    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    /// A menu-bar app has no visible menu, but its text fields still need ⌘X ⌘C ⌘V ⌘A ⌘Z: AppKit routes
    /// those key equivalents through the main menu. Without this, a dictation into Murmur's own windows
    /// (onboarding practice, Dictionary) posted ⌘V and nothing pasted.
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

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
        case .idle, .inserted: symbol = "waveform"; label = "Murmur"
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
        if flowBar.model.hiddenUntil.map({ $0 > Date() }) ?? false {
            menu.addItem(item("Show Flow Bar", #selector(showFlowBar)))
        } else {
            menu.addItem(item("Hide Flow Bar for 1 hour", #selector(hideFlowBar)))
        }
        menu.addItem(.separator())
        menu.addItem(shortcutsMenu())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Check permissions…", #selector(showPermissions)))
        if settings.debugMenu { menu.addItem(debugMenu()) }
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

    func debugMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let states = NSMenuItem(title: "Force Flow Bar state", action: nil, keyEquivalent: "")
        let stateMenu = NSMenu()
        for (index, state) in Self.forcibleStates.enumerated() {
            let entry = item(state.name, #selector(forceState(_:)))
            entry.tag = index
            entry.state = flowBar.model.forced == state ? .on : .off
            stateMenu.addItem(entry)
        }
        stateMenu.addItem(.separator())
        stateMenu.addItem(item("Clear forced state", #selector(clearForcedState)))
        states.submenu = stateMenu
        sub.addItem(states)
        sub.addItem(item("Token panel…", #selector(showTokens)))
        let soundsItem = NSMenuItem(title: "Play sounds", action: nil, keyEquivalent: "")
        let soundsMenu = NSMenu()
        for sound in UISound.allCases {
            let entry = item(sound.rawValue.capitalized, #selector(playSound(_:)))
            entry.representedObject = sound.rawValue
            soundsMenu.addItem(entry)
        }
        soundsItem.submenu = soundsMenu
        sub.addItem(soundsItem)
        sub.addItem(item("Run focus test (50 trials)", #selector(runFocusTestFromMenu)))
        sub.addItem(item("Open data folder", #selector(openDataFolder)))
        sub.addItem(item("Run onboarding again", #selector(showOnboardingFromMenu)))
        sub.addItem(item("Save window snapshots", #selector(saveSnapshotsFromMenu)))
        parent.submenu = sub
        return parent
    }

    static let forcibleStates: [FlowBarState] = [
        .idle, .hidden, .listening(handsFree: false), .listening(handsFree: true), .processing, .inserted,
        .notice(FlowBarNotice(kind: .pasteError, message: "Couldn't paste. The text is on the clipboard.")),
        .notice(FlowBarNotice(kind: .transcriptionError, message: "Transcription failed.")),
        .notice(FlowBarNotice(kind: .noTextBox, message: "No text box. Click one and press ⌃⌘V.")),
        .notice(FlowBarNotice(kind: .cancelled, message: "Cancelled")),
    ]

    @objc func forceState(_ sender: NSMenuItem) { flowBar.model.forced = Self.forcibleStates[sender.tag] }
    @objc func clearForcedState() { flowBar.model.forced = nil }
    @objc func showTokens() { windows.showTokens() }
    @objc func playSound(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let sound = UISound(rawValue: raw) { sounds.play(sound) }
    }
    @objc func hideFlowBar() { flowBar.bar.hide(for: 3600) }
    @objc func showFlowBar() { flowBar.bar.unhide() }
    @objc func openDataFolder() { NSWorkspace.shared.open(MurmurPaths.appSupport) }
    @objc func saveSnapshotsFromMenu() { saveSnapshots() }

    /// Renders Murmur's own windows to PNG (no Screen Recording needed for our own views): every Hub page,
    /// the onboarding window if open, and each Flow Bar state.
    func saveSnapshots() {
        let dir = MurmurPaths.appSupport.appendingPathComponent("snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            let returnTo = hub.page
            showHub(hub.page)
            for page in HubPage.main + HubPage.settings {
                hub.go(page)
                try? await Task.sleep(for: .milliseconds(450))
                if let window = windows.window("hub") { Self.png(of: window, to: dir.appendingPathComponent("hub-\(page.rawValue).png")) }
            }
            hub.go(returnTo)
            if let window = windows.window("onboarding") { Self.png(of: window, to: dir.appendingPathComponent("onboarding-current.png")) }
            for (index, state) in Self.forcibleStates.enumerated() {
                flowBar.model.forced = state
                try? await Task.sleep(for: .milliseconds(500))
                Self.png(of: flowBar.bar.panelForSnapshots, to: dir.appendingPathComponent(String(format: "bar-%02d.png", index)))
            }
            flowBar.model.forced = nil
            NSWorkspace.shared.open(dir)
        }
    }

    static func png(of window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    @objc func runFocusTestFromMenu() { runFocusTest(delay: 5) }

    func runFocusTest(delay: Double) {
        if focusTest == nil { focusTest = FocusTest(bar: flowBar.bar, controller: controller) }
        focusTest?.run(delay: delay) { [weak self] message in
            self?.flowBar.model.forced = .notice(FlowBarNotice(kind: .info, message: message))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(message.hasPrefix("Focus test starts") ? 4.5 : 8))
                if case .notice(let n)? = self?.flowBar.model.forced, n.message == message { self?.flowBar.model.forced = nil }
            }
        }
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

    @objc func showHistory() { showHub(.home) }
    @objc func showSettings() { showHub(.general) }
    @objc func showDictionary() { showHub(.dictionary) }
    @objc func showSnippets() { showHub(.snippets) }
    @objc func showOnboardingFromMenu() { showOnboarding() }
    @objc func showPermissions() { showHub(.general) }

    func showHub(_ page: HubPage) {
        hub.go(page)
        windows.show("hub", title: "Murmur", size: NSSize(width: 920, height: 620)) { HubView(model: hub) }
    }

    func showOnboarding() {
        let model = onboarding ?? OnboardingModel(hub: hub)
        onboarding = model
        model.onShowFlowBar = { [weak self] show in
            self?.flowBar.model.forced = show ? .notice(FlowBarNotice(kind: .info, message: "This is the Flow Bar. Click it to dictate hands-free.")) : nil
        }
        model.onFinish = { [weak self] in
            self?.windows.close("onboarding")
            self?.showHub(.home)
        }
        windows.show("onboarding", title: "Set up Murmur", size: NSSize(width: 600, height: 470)) { OnboardingView(model: model) }
    }
}
