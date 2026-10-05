import AppKit
import ApplicationServices
import Carbon.HIToolbox
import HubUI
import MurmurKit

/// Debug app matrix (SPEC §8, the apps that need no account): dictates one spoken sentence through the
/// real pipeline into a blank target in each installed app and checks four of the five matrix items: the
/// text lands complete, one Undo removes it, the clipboard is restored, focus is unchanged. ("Paste last
/// after a forced failure" is in the self-test.)
///
/// Targets: TextEdit, Safari, Chrome, Firefox, Terminal, Ghostty. VS Code and Cursor stay manual: their
/// editors don't expose text to Accessibility reliably, and Cursor may open its Agents window instead.
///
/// Safety: it only types into targets it made itself (an empty scratch file, a local test page with a
/// labelled field, a new terminal window in its own folder) and confirms before every dictation that
/// the target is frontmost and its field has focus; otherwise that app is skipped, never typed into.
/// Apps it launched are quit again; tabs and windows it opened are closed; History rows are removed.
@MainActor
final class AppMatrix {
    let controller: DictationController
    let store: HistoryStore
    let settings = AppSettings.shared
    let dir = MurmurPaths.appSupport.appendingPathComponent("selftest/matrix", isDirectory: true)
    static let sentence = "The quick brown fox jumps over the lazy dog."
    static let fieldLabel = "Murmur matrix field"
    private var lines: [String] = []
    private var passed = 0

    enum Kind { case document, webPage, terminal }

    struct Target {
        let name: String
        let bundleId: String
        let kind: Kind
        /// Chromium apps expose their fields to Accessibility only while an assistive mode is on; the run
        /// turns it on for the test and back off afterwards.
        var chromium = false
    }

    static let targets: [Target] = [
        Target(name: "TextEdit", bundleId: "com.apple.TextEdit", kind: .document),
        Target(name: "Safari", bundleId: "com.apple.Safari", kind: .webPage),
        Target(name: "Chrome", bundleId: "com.google.Chrome", kind: .webPage, chromium: true),
        Target(name: "Firefox", bundleId: "org.mozilla.firefox", kind: .webPage),
        Target(name: "Terminal", bundleId: "com.apple.Terminal", kind: .terminal),
        Target(name: "Ghostty", bundleId: "com.mitchellh.ghostty", kind: .terminal),
    ]

    init(controller: DictationController, store: HistoryStore) {
        self.controller = controller
        self.store = store
    }

    /// Names of the targets to run (all when empty).
    var only: Set<String> = []
    /// What the last focus check saw, for a skipped app's report line.
    private var lastSeen = ""

    func run() async -> String {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let startedAt = Date()
        let sounds = settings.soundsEnabled
        settings.soundsEnabled = false
        let clipboard = SelfTest.saveClipboard()
        let sentinel = "murmur-app-matrix-\(UUID().uuidString.prefix(8))"
        lines = ["Murmur app matrix, \(Date().formatted(date: .abbreviated, time: .standard))", ""]
        let clip = await synthesize(Self.sentence)
        var names: Set<String> = []
        var tested = 0

        for target in Self.targets where only.isEmpty || only.contains(target.name) {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) else {
                lines.append("SKIP \(target.name): not installed")
                continue
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sentinel, forType: .string)
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleId).isEmpty
            guard let opened = await open(target, appURL: appURL) else {
                await cleanUpSkipped(target, quit: !wasRunning)
                lines.append("SKIP \(target.name): the test target didn't get keyboard focus, so nothing was typed (saw \(lastSeen))")
                continue
            }
            names.insert(opened.app.localizedName ?? target.name)
            tested += 1
            let failures = await check(target, opened, clip: clip, sentinel: sentinel)
            await close(target, opened, quit: !wasRunning)
            if failures.isEmpty { passed += 1 }
            let undo = target.kind == .terminal ? "line cleared with Control-U (shells have no Undo)" : "one Undo removes it"
            lines.append(failures.isEmpty ? "PASS \(target.name): text complete, \(undo), clipboard restored, focus unchanged"
                                           : "FAIL \(target.name): \(failures.joined(separator: "; "))")
        }

        // Remove this run's History rows, restore the clipboard and sounds.
        let rows = ((try? store.recent(limit: 100)) ?? []).filter { $0.startedAt >= startedAt && names.contains($0.appName ?? "") }
        for row in rows {
            try? store.deleteRecord(id: row.id)
            if let path = row.audioPath { try? FileManager.default.removeItem(atPath: path) }
        }
        SelfTest.restoreClipboard(clipboard)
        settings.soundsEnabled = sounds
        try? FileManager.default.removeItem(at: dir)

        let summary = "App matrix: \(passed) of \(tested) apps passed"
        lines.insert(summary, at: 1)
        let report = MurmurPaths.appSupport.appendingPathComponent("selftest/app-matrix.txt")
        try? lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        return summary
    }

    // MARK: Targets

    struct Opened {
        let app: NSRunningApplication
        let field: AXUIElement
        /// For a terminal: the window, closed afterwards.
        let window: AXUIElement?
    }

    private func open(_ target: Target, appURL: URL) async -> Opened? {
        let url: URL
        switch target.kind {
        case .document:
            url = dir.appendingPathComponent("murmur-matrix-\(target.name.replacingOccurrences(of: " ", with: "-")).txt")
            try? "".write(to: url, atomically: true, encoding: .utf8)
        case .webPage:
            url = dir.appendingPathComponent("murmur-matrix.html")
            let page = """
            <!doctype html><meta charset="utf-8"><title>Murmur matrix</title>
            <textarea aria-label="\(Self.fieldLabel)" placeholder="\(Self.fieldLabel)" autofocus rows="8" cols="60"></textarea>
            <script>setTimeout(() => document.querySelector("textarea").focus(), 300)</script>
            """
            try? page.write(to: url, atomically: true, encoding: .utf8)
        case .terminal:
            url = dir.appendingPathComponent("murmur-matrix", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let app = try? await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if target.chromium { Self.assistiveMode(element, on: true) }
        lastSeen = "nothing focused"
        for attempt in 0..<100 {
            try? await Task.sleep(for: .milliseconds(100))
            if !app.isActive { app.activate() }
            if let field = SelfTest.focused(pid: app.processIdentifier) {
                if isOurs(field, target) { return Opened(app: app, field: field, window: window(of: field)) }
                lastSeen = describe(field)
            }
            // A browser may leave focus in its address bar: find the labelled field and focus it.
            if target.kind == .webPage, attempt % 10 == 9, let field = findLabelled(in: element) {
                AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
        }
        return nil
    }

    /// Is this focused element the field this run made, and nothing of the owner's?
    private func isOurs(_ field: AXUIElement, _ target: Target) -> Bool {
        let role = SelfTest.attribute(field, kAXRoleAttribute)
        switch target.kind {
        case .webPage:
            return role == kAXTextAreaRole && Self.labelled(field)
        case .document:
            guard role == kAXTextAreaRole, let window = window(of: field) else { return false }
            let title = SelfTest.attribute(window, kAXTitleAttribute) ?? ""
            return title.contains("murmur-matrix") && (SelfTest.value(field) ?? "").isEmpty
        case .terminal:
            // A fresh shell in the test folder: its prompt ends with the folder name ("… murmur-matrix %").
            guard let text = SelfTest.value(field) else { return false }
            let last = text.split(separator: "\n").last.map(String.init) ?? ""
            return last.contains("murmur-matrix") && !last.contains("quick brown")
        }
    }

    private func describe(_ e: AXUIElement) -> String {
        let role = SelfTest.attribute(e, kAXRoleAttribute) ?? "?"
        let label = SelfTest.attribute(e, kAXDescriptionAttribute) ?? SelfTest.attribute(e, kAXTitleAttribute) ?? ""
        let title = window(of: e).flatMap { SelfTest.attribute($0, kAXTitleAttribute) } ?? ""
        return "\(role) \"\(label.prefix(30))\" in window \"\(title.prefix(50))\", \((SelfTest.value(e) ?? "").count) chars"
    }

    /// The test page's field, searched breadth-first through the focused window (bounded).
    private func findLabelled(in app: AXUIElement) -> AXUIElement? {
        var root: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &root) == .success, let root else { return nil }
        var queue = [root as! AXUIElement]
        var seen = 0
        while !queue.isEmpty, seen < 20_000 {
            let e = queue.removeFirst()
            seen += 1
            if SelfTest.attribute(e, kAXRoleAttribute) == kAXTextAreaRole, Self.labelled(e) { return e }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &children) == .success, let list = children as? [AXUIElement] {
                queue.append(contentsOf: list)
            }
        }
        return nil
    }

    static func labelled(_ e: AXUIElement) -> Bool {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXPlaceholderValueAttribute, "AXLabel"]
            .compactMap { SelfTest.attribute(e, $0) }.contains { $0.contains(fieldLabel) }
    }

    /// Chromium builds its accessibility tree only for assistive apps: these two attributes ask for it.
    static func assistiveMode(_ app: AXUIElement, on: Bool) {
        let value = on ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, value!)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, value!)
    }

    private func window(of field: AXUIElement) -> AXUIElement? {
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXWindowAttribute as CFString, &window) == .success, let window else { return nil }
        return (window as! AXUIElement)
    }

    private func stillFocused(_ opened: Opened) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == opened.app.processIdentifier,
              let now = SelfTest.focused(pid: opened.app.processIdentifier) else { return false }
        return CFEqual(now, opened.field)
    }

    // MARK: Checks

    private func check(_ target: Target, _ opened: Opened, clip: [Float], sentinel: String) async -> [String] {
        // The last look before typing: the test field is frontmost and focused.
        guard stillFocused(opened), isOurs(opened.field, target) else { return ["focus moved before the dictation; nothing was typed"] }
        let t0 = Date()
        guard controller.dictateForTest(clip) else { return ["could not start a dictation"] }
        let end = Date().addingTimeInterval(20)
        while controller.isBusy, Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(700))

        var failures: [String] = []
        let text = SelfTest.value(opened.field) ?? ""
        if let missing = SelfTest.missing(["quick", "brown", "fox", "jumps", "lazy", "dog"], in: text) {
            failures.append(text.isEmpty ? "nothing landed (or the app doesn't expose its text)" : "text incomplete (\(missing))")
        }
        if NSPasteboard.general.string(forType: .string) != sentinel { failures.append("clipboard not restored") }
        if !stillFocused(opened) { failures.append("focus changed") }

        if target.kind == .terminal {
            // Shells have no Undo; clear the line instead (Control-U), only while the test window has focus.
            if stillFocused(opened) { postKey(kVK_ANSI_U, flags: .maskControl, to: opened.app.processIdentifier) }
        } else if text.contains("quick brown") || insertedSince(t0) {
            // One Undo, through the app's own Edit menu, whenever something was typed, even when the app
            // hides its text (so the scratch file closes unmodified, with no save prompt).
            _ = SelfTest.pressMenuItem(pid: opened.app.processIdentifier, startingWith: "Undo")
            // Some apps (Firefox) apply the Undo a beat later: poll for up to 2 s before calling it a failure.
            var undone = false
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if !(SelfTest.value(opened.field) ?? "").contains("quick brown") { undone = true; break }
            }
            if !undone { failures.append("one Undo did not remove it") }
        }
        return failures
    }

    /// Whether this run's dictation reached the paste (its History row says inserted).
    private func insertedSince(_ t0: Date) -> Bool {
        ((try? store.recent(limit: 3)) ?? []).contains { $0.startedAt >= t0.addingTimeInterval(-1) && $0.status == .inserted }
    }

    private func postKey(_ key: Int, flags: CGEventFlags, to pid: pid_t) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = flags
            event.postToPid(pid)
        }
    }

    // MARK: Cleanup

    private func close(_ target: Target, _ opened: Opened, quit: Bool) async {
        let pid = opened.app.processIdentifier
        try? await Task.sleep(for: .milliseconds(300))
        switch target.kind {
        case .webPage:
            if stillFocused(opened) { _ = SelfTest.pressMenuItem(pid: pid, startingWith: "Close Tab") }
        case .document:
            pressClose(opened.window)
        case .terminal:
            pressClose(opened.window)
        }
        try? await Task.sleep(for: .milliseconds(800))
        if target.chromium { Self.assistiveMode(AXUIElementCreateApplication(pid), on: false) }
        if quit { opened.app.terminate() }
    }

    /// After a skip: switch Chromium's assistive mode back off, close the test tab if it's the front
    /// tab, and quit the app if this run launched it.
    private func cleanUpSkipped(_ target: Target, quit: Bool) async {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleId).first else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if target.chromium { Self.assistiveMode(element, on: false) }
        var window: CFTypeRef?
        if target.kind == .webPage, app.isActive,
           AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success, let window,
           SelfTest.attribute(window as! AXUIElement, kAXTitleAttribute)?.contains("Murmur matrix") == true {
            _ = SelfTest.pressMenuItem(pid: app.processIdentifier, startingWith: "Close Tab")
        }
        try? await Task.sleep(for: .milliseconds(500))
        if quit { app.terminate() }
    }

    private func pressClose(_ window: AXUIElement?) {
        guard let window else { return }
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success, let button {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    /// The system voice at 16 kHz, with half a second of silence on each side like a real key press.
    private func synthesize(_ phrase: String) async -> [Float] {
        let url = dir.appendingPathComponent("clip.wav")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEI16@16000", phrase]
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in done.resume() }
            do { try process.run() } catch { done.resume() }
        }
        let samples = (try? WAV.read(url)) ?? []
        try? FileManager.default.removeItem(at: url)
        let pad = [Float](repeating: 0, count: 8_000)
        return pad + samples + pad
    }
}
