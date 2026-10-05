import AppKit
import AVFoundation
import Carbon.HIToolbox
import MurmurKit
import SwiftUI

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
            self?.hub?.status = status
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
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.swaritsheel.Murmur.debug.selfTest"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let app = Self.shared, app.settings.debugMenu else { return }
                app.runSelfTest()
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
        let info = NSMenuItem(title: modelsLine, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(item("Quit Murmur", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    /// “Parakeet ultra · Qwen3.5 4B”, or what is still loading.
    var modelsLine: String {
        func name(_ table: [String: String], _ id: String) -> String {
            (table[id] ?? id).replacingOccurrences(of: " (recommended)", with: "")
        }
        let engine = controller.engineDescription
        let cleanup = controller.cleanupDescription
        return "\(name(ModelNames.engines, engine)) · \(name(ModelNames.cleanup, cleanup == "rules only" ? "rules" : cleanup))"
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
        let config = DictationController.shortcutConfiguration(settings)
        let ptt = config.pushToTalk.displayName
        for line in ["Hold \(ptt) to talk", "Press \(config.handsFree.displayName) or double-tap \(ptt) for hands-free", "Esc cancels"] {
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
        sub.addItem(item(selfTestRunning ? "Self-test running…" : "Run self-test in TextEdit", #selector(runSelfTestFromMenu)))
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

    @objc func runSelfTestFromMenu() { runSelfTest() }

    /// Runs `SelfTest` once and shows the result on the Flow Bar; the full report is in the data folder.
    func runSelfTest() {
        guard !selfTestRunning else { return }
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
            Self.seedDemo(demoStore)
            let demo = HubModel(controller: controller, store: demoStore)
            windows.show("hub-preview", title: "Murmur (preview)", size: NSSize(width: 920, height: 620), chrome: .unified) { HubView(model: demo) }
            guard let window = windows.window("hub-preview") else { return }
            let sizes: [(String, NSSize)] = [("small", NSSize(width: 760, height: 480)), ("default", NSSize(width: 920, height: 620)), ("tall", NSSize(width: 920, height: 1250))]
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
            window.setContentSize(NSSize(width: 920, height: 620))

            // Clicks under the transparent title bar must reach the page header and the sidebar.
            var checks: [String] = []
            demo.go(.dictionary)
            demo.go(.snippets)
            try? await Task.sleep(for: .milliseconds(300))
            let height = window.contentView?.bounds.height ?? 0
            let back = NSPoint(x: 214 + 1 + 12 + 13, y: height - HubView.headerHeight / 2)
            let hit = window.contentView?.superview?.hitTest(back)
            checks.append("hit test at Back: \(hit.map { String(describing: type(of: $0)) } ?? "nothing")")
            for (label, point) in [("empty header", NSPoint(x: 640, y: height - HubView.headerHeight / 2)), ("sidebar top", NSPoint(x: 150, y: height - 20))] {
                let view = window.contentView?.superview?.hitTest(point)
                let drags = view is WindowDragArea.DragView || view?.mouseDownCanMoveWindow == true
                checks.append("Drag from \(label): \(drags ? "PASS" : "FAIL") (\(view.map { String(describing: type(of: $0)) } ?? "nothing"))")
            }
            await Self.click(window, at: back)
            checks.append("Back button: \(demo.page == .dictionary ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            await Self.click(window, at: NSPoint(x: 60, y: height - (HubView.headerHeight + 2 + 34 + 3 * 30 + 15)))
            checks.append("Sidebar Style row: \(demo.page == .style ? "PASS" : "FAIL (page \(demo.page.rawValue))")")
            try? checks.joined(separator: "\n").write(to: dir.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)

            // Empty states.
            if let emptyStore = try? HistoryStore(url: nil) {
                let empty = HubModel(controller: controller, store: emptyStore)
                window.contentViewController = NSHostingController(rootView: HubView(model: empty))
                window.setContentSize(NSSize(width: 920, height: 620))
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
            windows.show("onboarding-preview", title: "Set up Murmur (preview)", size: NSSize(width: 640, height: 540), chrome: .transparent) { OnboardingView(model: preview) }
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
                for state in Self.forcibleStates {
                    flowBar.model.forced = state
                    try? await Task.sleep(for: .milliseconds(450))
                    if let rep = Self.capture(panel) { sheet.append(rep) }
                }
                Self.contactSheet(sheet, columns: 2, scale: 1, to: dir.appendingPathComponent("sheet-bar-\(lookName).png"))
            }
            panel.appearance = nil
            flowBar.model.forced = nil
        }
    }

    /// Posts a left click to one of Murmur's windows through the normal event queue (the cursor does
    /// not move), then waits for it to be handled.
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

    /// Demo content for design snapshots: a few days of History in every state, dictionary words, snippets.
    static func seedDemo(_ store: HistoryStore) {
        let now = Date()
        let rows: [(Double, String, String?, DictationRecord.Status, Bool)] = [
            (0.1, "Can you send me the slides before the 3 pm sync? I want to add the Q3 numbers.", "Slack", .inserted, false),
            (0.6, "Thanks for the quick turnaround, this looks great. Let's ship it on Friday.", "Mail", .inserted, false),
            (1.2, "Refactor the history store so every write is its own transaction, then add a migration test for the useRaw column and run the full suite before merging. Also double-check the retry path for rows that were left in the recorded state after a crash, because those should come back as Recover, not Retry, and the button label should say so.", "Cursor", .inserted, false),
            (2.0, "Remind me to call Siobhan about the venue.", "Notes", .pasteFailed, false),
            (3.5, "um so I think we should uh move the launch to Friday", "Messages", .inserted, true),
            (26, "Here are the three things we agreed on: the pricing page, the onboarding email, and the changelog.", "Notion", .inserted, false),
            (27, "Book a table for four at 7:30.", "Messages", .inserted, false),
            (75, "The build is green again after the Metal fix.", "Terminal", .inserted, false),
            (76, "", "Safari", .transcriptionFailed, false),
        ]
        for (hoursAgo, text, app, status, useRaw) in rows {
            var r = DictationRecord(startedAt: now.addingTimeInterval(-hoursAgo * 3600), durationMs: Double(max(text.split(separator: " ").count, 4)) * 420,
                                    appBundleId: nil, appName: app, mode: "hold", engine: "parakeet-ultra", cleanup: "mlx:qwen3.5-4b",
                                    rawText: text.isEmpty ? nil : text, cleanText: text.isEmpty ? nil : (useRaw ? "I think we should move the launch to Friday." : text),
                                    status: status)
            r.useRaw = useRaw
            try? store.insert(r)
        }
        for (heard, word, suggested) in [("Chivan", "Siobhan", false), ("Q three", "Q3", false), ("Murmur", "Murmur", false), ("GRDB", "GRDB", false), ("Para keet", "Parakeet", true)] {
            try? store.save(DictionaryRecord(term: heard, replacement: word, source: suggested ? .suggested : .manual))
        }
        try? store.save(SnippetRecord(cue: "my email", expansion: "hello@example.com"))
        try? store.save(SnippetRecord(cue: "sign off", expansion: "Thanks,\nAlex"))
        try? store.save(SnippetRecord(cue: "calendar link", expansion: "https://cal.example.com/alex/30min"))
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
    @objc func showPermissions() { showHub(.general) }

    func showHub(_ page: HubPage) {
        hub.go(page)
        windows.show("hub", title: "Murmur", size: NSSize(width: 920, height: 620), chrome: .unified) { HubView(model: hub) }
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
        windows.show("onboarding", title: "Set up Murmur", size: NSSize(width: 640, height: 540), chrome: .transparent) { OnboardingView(model: model) }
    }
}
