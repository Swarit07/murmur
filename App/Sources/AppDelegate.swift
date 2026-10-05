import AppKit
import AVFoundation
import Carbon.HIToolbox
import HubUI
import MurmurKit
import SwiftUI
import UI

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
    var selfTestRunning = false
    var appMatrixRunning = false
    var onboarding: OnboardingModel?
    var permissionTimer: Timer?
    var lastPermissions = PermissionSnapshot.current()
    /// The dropdown's header (§5.2) and the processing ripple's redraw timer.
    let menuHeader = MenuHeaderModel()
    var rippleTimer: Timer?
    var rippleStart = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bundled fonts first, so every window opens in Murmur's type (system fonts if this fails).
        FontRegistry.registerBundledFonts()
        AppearanceController.apply(AppSettings.shared.appearance)
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
            self?.hub?.status = status
        }
        hub = HubModel(controller: controller, store: store)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
                if key == "appearance" { AppearanceController.apply(AppSettings.shared.appearance) }
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
        // Performance pass: unload the cleanup model now, as the idle timer would.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.unload"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                Task { await app.controller.unloadModelsNow() }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.selfTest"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.runSelfTest()
            }
        }
        // Object: optional comma-separated app names to run ("Safari,Chrome"); all when empty.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.appMatrix"), object: nil, queue: .main) { note in
            let only = (note.object as? String).map { Set($0.split(separator: ",").map { String($0) }) } ?? []
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.runAppMatrix(only: only)
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.runFocusTest"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.runFocusTest(delay: 2)
            }
        }
        // Design review and profiling: force a Flow Bar gallery state by name ("none" clears it).
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.forceFlowBar"), object: nil, queue: .main) { note in
            let name = note.object as? String
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.flowBar.model.force(FlowBarState.gallery.first { $0.name == name })
            }
        }
        // Design review (U8): shows the status item and dropdown in a state ("recording", "processing",
        // "error", "loading", or the current one), opens the dropdown for a few seconds, then restores.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.menu"), object: nil, queue: .main) { note in
            let name = note.object as? String
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                var status = app.controller.status
                switch name {
                case "recording": status.phase = .recording(handsFree: true)
                case "processing": status.phase = .processing
                case "loading": status.phase = .loading
                case "error":
                    status.phase = .error
                    status.message = "Transcription failed. The audio is saved in History."
                default: break
                }
                app.render(status)
                // Saves the open dropdown (a window of this process), then closes it.
                let capture = Timer(timeInterval: 1.2, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        app.captureMenuWindows(name ?? "current")
                        app.statusItem.menu?.cancelTracking()
                        app.render(app.controller.status)
                    }
                }
                RunLoop.main.add(capture, forMode: .common)
                app.statusItem.button?.performClick(nil)
            }
        }
        // Performance pass (U3): a 10-second hands-free recording, then discarded (nothing is inserted
        // or kept), so the Flow Bar can be profiled while it draws the live waveform.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.recordTenSeconds"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu, !app.controller.isRecording else { return }
                let sounds = app.settings.soundsEnabled
                app.settings.soundsEnabled = false
                app.controller.toggleHandsFree()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(10))
                    app.controller.discardCurrent()
                    app.settings.soundsEnabled = sounds
                }
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
            controller.notice("Murmur lost the \(lost.joined(separator: " and ")) permission. Open Murmur › Settings › System to turn it back on.")
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

    /// The status item shows the glyph's four states (§3.6). Loading uses the processing glyph, still;
    /// only processing ripples, and not under Reduce Motion.
    func render(_ status: DictationStatus) {
        let wasRecording: Bool = if case .recording = menuHeader.phase { true } else { false }
        menuHeader.phase = status.phase
        menuHeader.message = status.message
        menuHeader.hotkey = hub?.hotkeyLabel ?? menuHeader.hotkey
        menuHeader.microphone = controller?.microphoneName ?? ""
        if case .recording = status.phase {
            if !wasRecording { menuHeader.recordingSince = Date() }
        } else {
            menuHeader.recordingSince = nil
        }
        guard let button = statusItem?.button else { return }
        let state: MenuBarGlyph.State
        let label: String
        switch status.phase {
        case .loading: state = .processing; label = "Murmur: loading models"
        case .idle, .inserted: state = .idle; label = "Murmur"
        case .recording: state = .recording; label = "Murmur: listening"
        case .processing: state = .processing; label = "Murmur: working"
        case .error: state = .error; label = "Murmur: needs attention"
        }
        let ripple = status.phase == .processing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if ripple, rippleTimer == nil {
            rippleStart = Date()
            let timer = Timer(timeInterval: MotionTokens.menuBarFrame, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard let app = Self.shared, let button = app.statusItem?.button else { return }
                    button.image = MenuBarGlyph.image(.processing, phase: Date().timeIntervalSince(app.rippleStart))
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            rippleTimer = timer
        } else if !ripple {
            rippleTimer?.invalidate()
            rippleTimer = nil
        }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // A still processing glyph shows the ripple a quarter of the way through, so the dots read as dots.
        button.image = MenuBarGlyph.image(state, phase: MotionTokens.dotsPeriod / 4, dark: dark)
        button.setAccessibilityLabel(label)
        button.toolTip = status.message ?? label
    }

    /// Design review: writes this process's open menu windows to PNGs in the data folder. (The status item
    /// itself lives in the system's menu bar process, so murmur-snap renders the glyph states instead.)
    func captureMenuWindows(_ name: String) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur/Snapshots/menu", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let windows = NSApp.windows.filter { $0.isVisible && $0.className.contains("Menu") }
        for (i, window) in windows.enumerated() {
            guard let id = CGWindowID(exactly: window.windowNumber),
                  let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            let file = folder.appendingPathComponent("\(name)-\(i)-\(window.className).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
        }
    }

    // MARK: Menu

    /// The dropdown in §5.2's order: header; Open, Paste last, Copy last; Microphone, Hide Flow Bar;
    /// Shortcuts, Settings, Check permissions; Quit; footer. Native items, system highlight.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menuHeader.hotkey = hub.hotkeyLabel
        menuHeader.microphone = controller.microphoneName
        menu.addItem(.hosting(MenuHeaderView(model: menuHeader)))
        menu.addItem(.separator())
        menu.addItem(item("Open Murmur", #selector(showHistory), key: "o"))
        // The app's global shortcuts are ⌃⌘V and ⌃⌘C (SPEC I7); the menu shows the real ones.
        let paste = item("Paste last transcript", #selector(pasteLast), key: "v")
        paste.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(paste)
        let copy = item("Copy last transcript", #selector(copyLast), key: "c")
        copy.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(copy)
        menu.addItem(.separator())
        menu.addItem(microphoneMenu())
        if flowBar.model.hiddenUntil.map({ $0 > Date() }) ?? false {
            menu.addItem(item("Show Flow Bar", #selector(showFlowBar)))
        } else {
            menu.addItem(item("Hide Flow Bar for 1 hour", #selector(hideFlowBar)))
        }
        menu.addItem(.separator())
        menu.addItem(shortcutsMenu())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        let permissions = item("Check permissions", #selector(showPermissions))
        let snapshot = PermissionSnapshot.current()
        let missing = [snapshot.microphone, snapshot.accessibility, snapshot.inputMonitoring].filter { !$0 }.count
        if missing > 0 { permissions.badge = NSMenuItemBadge(string: "\(missing) missing") }
        menu.addItem(permissions)
        if settings.debugMenu { menu.addItem(debugMenu()) }
        menu.addItem(.separator())
        menu.addItem(item("Quit Murmur", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        menu.addItem(.separator())
        menu.addItem(.hosting(MenuFooterView(footerLine)))
    }

    /// "v0.1.0 · on-device engine", or which part runs in the cloud.
    var footerLine: String {
        let cloud = AppInfo.cloud(controller)
        let place = switch (cloud.speech, cloud.cleanup) {
        case (false, false): "on-device engine"
        case (false, true): "on-device speech, cloud cleanup"
        case (true, false): "cloud speech, on-device cleanup"
        case (true, true): "cloud engine"
        }
        return "v\(AppInfo.version) · \(place)"
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

    /// Automatic (the system default, named), each input device, then Sound Settings….
    func microphoneMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let devices = AudioDevices.inputs()
        let automatic = item("Automatic", #selector(chooseMicrophone(_:)))
        if let name = devices.first(where: \.isDefault)?.name {
            let title = NSMutableAttributedString(string: "Automatic ", attributes: [.font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: "(\(name))", attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
            automatic.attributedTitle = title
        }
        automatic.representedObject = nil
        automatic.state = settings.microphoneUID == nil ? .on : .off
        sub.addItem(automatic)
        for device in devices {
            let entry = item(device.name, #selector(chooseMicrophone(_:)))
            entry.representedObject = device.uid
            entry.state = settings.microphoneUID == device.uid ? .on : .off
            sub.addItem(entry)
        }
        sub.addItem(.separator())
        sub.addItem(item("Sound Settings…", #selector(openSoundSettings)))
        parent.submenu = sub
        return parent
    }

    @objc func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound?input") { NSWorkspace.shared.open(url) }
    }

    func shortcutsMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let config = DictationController.shortcutConfiguration(settings)
        let ptt = config.pushToTalk.displayName
        var lines = ["Hold \(ptt) to talk", "Press \(config.handsFree.displayName) or double-tap \(ptt) for hands-free"]
        if let command = config.command { lines.append("Hold \(command.displayName) for Command Mode") }
        lines.append("Esc cancels")
        for line in lines {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            sub.addItem(info)
        }
        sub.addItem(.separator())
        func matches(_ preset: HotkeyConfiguration) -> Bool {
            config.pushToTalk == preset.pushToTalk && config.handsFree == preset.handsFree
        }
        let fn = item("Use Fn (Apple keyboard)", #selector(chooseKeyboard(_:)))
        fn.representedObject = "apple"
        fn.state = matches(.appleKeyboard) ? .on : .off
        let other = item("Use Control+Option (other keyboards)", #selector(chooseKeyboard(_:)))
        other.representedObject = "other"
        other.state = matches(.otherKeyboard) ? .on : .off
        sub.addItem(fn)
        sub.addItem(other)
        sub.addItem(item("Change shortcuts…", #selector(showSettings)))
        parent.submenu = sub
        return parent
    }

    func debugMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let states = NSMenuItem(title: "Force Flow Bar state", action: nil, keyEquivalent: "")
        let stateMenu = NSMenu()
        for (index, gallery) in Self.forcibleStates.enumerated() {
            let entry = item(gallery.name, #selector(forceState(_:)))
            entry.tag = index
            entry.state = flowBar.model.forced == gallery.state && flowBar.model.hovering == gallery.hover ? .on : .off
            stateMenu.addItem(entry)
        }
        stateMenu.addItem(.separator())
        stateMenu.addItem(item("Clear forced state", #selector(clearForcedState)))
        states.submenu = stateMenu
        sub.addItem(states)
        sub.addItem(item("Token panel…", #selector(showTokens)))
        sub.addItem(item("Design Gallery…", #selector(showGallery)))
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
        sub.addItem(item(selfTestRunning ? "Self-test running…" : "Run self-test in TextEdit", #selector(runSelfTestFromMenu)))
        sub.addItem(item(appMatrixRunning ? "App matrix running…" : "Run app matrix", #selector(runAppMatrixFromMenu)))
        parent.submenu = sub
        return parent
    }

    static let forcibleStates = FlowBarState.gallery

    @objc func forceState(_ sender: NSMenuItem) { flowBar.model.force(Self.forcibleStates[sender.tag]) }
    @objc func clearForcedState() { flowBar.model.force(nil) }
    @objc func showTokens() {
        windows.showTokens { [weak self] entry in self?.flowBar.model.force(entry) }
    }

    @objc func showGallery() {
        windows.show("gallery", title: "Design Gallery", size: NSSize(width: 1100, height: 800)) { DesignGallery() }
    }
    @objc func playSound(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let sound = UISound(rawValue: raw) { sounds.play(sound) }
    }
    @objc func hideFlowBar() {
        flowBar.bar.hide(for: 3600)
        controller.notice("Flow Bar hidden for an hour.", kind: .flowBarHidden)
    }
    @objc func showFlowBar() { flowBar.bar.unhide() }
    @objc func openDataFolder() { NSWorkspace.shared.open(MurmurPaths.appSupport) }
    @objc func saveSnapshotsFromMenu() { saveSnapshots() }

    @objc func runSelfTestFromMenu() { runSelfTest() }

    @objc func runAppMatrixFromMenu() { runAppMatrix() }

    /// Runs `AppMatrix` once (hands off the keyboard and mouse); the report is in the data folder.
    func runAppMatrix(only: Set<String> = []) {
        guard !appMatrixRunning, !selfTestRunning else { return }
        appMatrixRunning = true
        Task { @MainActor in
            let matrix = AppMatrix(controller: controller, store: store)
            matrix.only = only
            let summary = await matrix.run()
            appMatrixRunning = false
            controller.notice(summary + ". Report: Murmur data folder › selftest › app-matrix.txt.")
        }
    }

    /// Runs `SelfTest` once and shows the result on the Flow Bar; the full report is in the data folder.
    func runSelfTest() {
        guard !selfTestRunning, !appMatrixRunning else { return }
        selfTestRunning = true
        Task { @MainActor in
            let summary = await SelfTest(controller: controller, store: store).run()
            selfTestRunning = false
            controller.notice(summary + ". Report: Murmur data folder › selftest.")
        }
    }

    /// Renders Murmur's own windows to PNG (no Screen Recording needed for our own views) for design QA:
    /// every Hub page at three sizes in light and dark, every onboarding step, and every Flow Bar state,
    /// plus contact sheets that tile each group.
    func saveSnapshots() {
        let dir = MurmurPaths.appSupport.appendingPathComponent("snapshots")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            // A preview Hub on demo data, so tables are full and the real History window is untouched.
            guard let demoStore = try? HistoryStore(url: nil) else { return }
            DemoData.seed(demoStore)
            let demo = HubModel(controller: controller, store: demoStore)
            windows.show("hub-preview", title: "Murmur (preview)", size: HubGeometry.defaultWindow, chrome: .unified) { HubView(model: demo) }
            guard let window = windows.window("hub-preview") else { return }
            let sizes: [(String, NSSize)] = [("small", HubGeometry.minimumWindow), ("default", HubGeometry.defaultWindow), ("tall", NSSize(width: HubGeometry.defaultWindow.width, height: 1250))]
            let looks: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]
            for (lookName, look) in looks {
                window.appearance = NSAppearance(named: look)
                for (sizeName, size) in sizes {
                    window.setContentSize(size)
                    var sheet: [NSBitmapImageRep] = []
                    for page in HubPage.main + HubPage.settings {
                        demo.go(page)
                        try? await Task.sleep(for: .milliseconds(350))
                        if let rep = Self.capture(window) {
                            sheet.append(rep)
                            Self.write(rep, to: dir.appendingPathComponent("hub-\(page.rawValue)-\(sizeName)-\(lookName).png"))
                        }
                    }
                    Self.contactSheet(sheet, columns: 4, scale: sizeName == "tall" ? 0.4 : 0.5, to: dir.appendingPathComponent("sheet-hub-\(sizeName)-\(lookName).png"))
                }
            }
            window.appearance = nil
            window.setContentSize(HubGeometry.defaultWindow)

            // Clicks under the transparent title bar must reach the panel's top bar and the sidebar, and the
            // empty parts of both must drag the window.
            var checks: [String] = []
            demo.go(.home)
            try? await Task.sleep(for: .milliseconds(300))
            let height = window.contentView?.bounds.height ?? 0
            let g = HubGeometry.self
            for (label, point) in [("panel top bar", NSPoint(x: 700, y: height - (g.panelInset + g.topBarHeight / 2))),
                                   ("sidebar top", NSPoint(x: 150, y: height - g.sidebarPaddingTop))] {
                let view = window.contentView?.superview?.hitTest(point)
                let drags = view is WindowDragArea.DragView || view?.mouseDownCanMoveWindow == true
                checks.append("Drag from \(label): \(drags ? "PASS" : "FAIL") (\(view.map { String(describing: type(of: $0)) } ?? "nothing"))")
            }
            // The Style row: below the lights zone, the brand mark block and three rows.
            let styleRowY = g.sidebarPaddingTop + g.trafficLightsZone + g.sidebarItemGap + g.brandMarkHeight + g.brandMarkInset * 2
                + g.sidebarItemGap + 3 * (g.sidebarItemHeight + g.sidebarItemGap) + g.sidebarItemHeight / 2
            await Self.click(window, at: NSPoint(x: 60, y: height - styleRowY))
            checks.append("Sidebar Style row: \(demo.page == .style ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            await Self.key(window, "[", keyCode: 33, modifiers: .command)
            checks.append("Back with ⌘[: \(demo.page == .home ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            await Self.key(window, "]", keyCode: 30, modifiers: .command)
            checks.append("Forward with ⌘]: \(demo.page == .style ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            demo.go(.home)
            await Self.key(window, String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, modifiers: [.option, .numericPad, .function])
            checks.append("Next page with ⌥↓: \(demo.page == .dictionary ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            await Self.key(window, String(UnicodeScalar(NSUpArrowFunctionKey)!), keyCode: 126, modifiers: [.option, .numericPad, .function])
            checks.append("Previous page with ⌥↑: \(demo.page == .home ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            try? checks.joined(separator: "\n").write(to: dir.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)

            // Empty states.
            if let emptyStore = try? HistoryStore(url: nil) {
                let empty = HubModel(controller: controller, store: emptyStore)
                window.contentViewController = NSHostingController(rootView: HubView(model: empty))
                window.setContentSize(HubGeometry.defaultWindow)
                var sheet: [NSBitmapImageRep] = []
                for page in [HubPage.home, .dictionary, .snippets] {
                    empty.go(page)
                    try? await Task.sleep(for: .milliseconds(350))
                    if let rep = Self.capture(window) { sheet.append(rep) }
                }
                Self.contactSheet(sheet, columns: 3, scale: 0.5, to: dir.appendingPathComponent("sheet-hub-empty.png"))
            }
            windows.close("hub-preview")

            // Onboarding, every step, in a preview that changes no settings and starts nothing.
            let preview = OnboardingModel(hub: hub, preview: true)
            windows.show("onboarding-preview", title: "Set up Murmur (preview)", size: OnboardingGeometry.step, chrome: .transparent) { OnboardingView(model: preview) }
            if let ob = windows.window("onboarding-preview") {
                for (lookName, look) in looks {
                    ob.appearance = NSAppearance(named: look)
                    var sheet: [NSBitmapImageRep] = []
                    for step in OnboardingStep.allCases {
                        preview.step = step
                        try? await Task.sleep(for: .milliseconds(300))
                        if let rep = Self.capture(ob) { sheet.append(rep) }
                    }
                    Self.contactSheet(sheet, columns: 4, scale: 0.5, to: dir.appendingPathComponent("sheet-onboarding-\(lookName).png"))
                }
                windows.close("onboarding-preview")
            }

            // Flow Bar states.
            let panel = flowBar.bar.panelForSnapshots
            for (lookName, look) in looks {
                panel.appearance = NSAppearance(named: look)
                var sheet: [NSBitmapImageRep] = []
                for entry in Self.forcibleStates {
                    flowBar.model.force(entry)
                    try? await Task.sleep(for: .milliseconds(450))
                    if let rep = Self.capture(panel) { sheet.append(rep) }
                }
                // Command Mode's accent while listening (hold and hands-free) and working.
                flowBar.model.command = true
                for state in [FlowBarState.listening(handsFree: false), .listening(handsFree: true), .processing] {
                    flowBar.model.forced = state
                    try? await Task.sleep(for: .milliseconds(450))
                    if let rep = Self.capture(panel) { sheet.append(rep) }
                }
                flowBar.model.command = false
                flowBar.model.force(nil)
                Self.contactSheet(sheet, columns: 2, scale: 1, to: dir.appendingPathComponent("sheet-bar-\(lookName).png"))
            }
            panel.appearance = nil
            flowBar.model.forced = nil
        }
    }

    /// Posts a left click to one of Murmur's windows through the normal event queue (the cursor does
    /// not move), then waits for it to be handled.
    /// A key press with modifiers, posted to the window (keyboard navigation checks).
    static func key(_ window: NSWindow, _ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) async {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) {
                NSApp.postEvent(event, atStart: false)
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    static func click(_ window: NSWindow, at point: NSPoint) async {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    static func capture(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Tiles captures into one image with a gap, scaled down, for reviewing many at once.
    static func contactSheet(_ reps: [NSBitmapImageRep], columns: Int, scale: CGFloat, to url: URL) {
        guard let first = reps.first else { return }
        let w = CGFloat(first.pixelsWide) * scale, h = CGFloat(first.pixelsHigh) * scale, gap: CGFloat = 12
        let rows = (reps.count + columns - 1) / columns
        let size = NSSize(width: CGFloat(columns) * (w + gap) + gap, height: CGFloat(rows) * (h + gap) + gap)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (i, rep) in reps.enumerated() {
            let col = i % columns, row = i / columns
            let rect = NSRect(x: gap + CGFloat(col) * (w + gap), y: size.height - gap - h - CGFloat(row) * (h + gap), width: w, height: h)
            rep.draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        write(out, to: url)
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

    /// A preset replaces any custom shortcuts, so the choice always takes effect.
    @objc func chooseKeyboard(_ sender: NSMenuItem) {
        settings.keyboardLayout = sender.representedObject as? String ?? "apple"
        controller.setShortcuts(nil)
    }

    @objc func showHistory() { showHub(.home) }
    @objc func showSettings() { showHub(.general) }
    @objc func showDictionary() { showHub(.dictionary) }
    @objc func showSnippets() { showHub(.snippets) }
    @objc func showOnboardingFromMenu() { showOnboarding() }
    @objc func showPermissions() { showHub(.system) }

    func showHub(_ page: HubPage) {
        hub.go(page)
        hub.onRunOnboarding = { [weak self] in self?.showOnboarding() }
        windows.show("hub", title: "Murmur", size: HubGeometry.defaultWindow, chrome: .unified) { HubView(model: hub) }
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
        windows.show("onboarding", title: "Set up Murmur", size: OnboardingGeometry.step, chrome: .transparent) { OnboardingView(model: model) }
    }
}
