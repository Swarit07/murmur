import AppKit
import ApplicationServices
import MurmurKit

/// Debug self-test (QA): speaks short phrases with the system voice, runs each one through the real
/// pipeline (gate, engine, rules, cleanup model, guard, focus check, clipboard paste) into a scratch
/// TextEdit document, and reads the document back through Accessibility. Restores every setting, the
/// clipboard, the dictionary and snippets, and removes its History rows afterwards.
@MainActor
final class SelfTest {
    let controller: DictationController
    let store: HistoryStore
    let settings = AppSettings.shared
    let dir = MurmurPaths.appSupport.appendingPathComponent("selftest")
    private var report: [String] = []
    private var passed = 0
    private var total = 0

    init(controller: DictationController, store: HistoryStore) {
        self.controller = controller
        self.store = store
    }

    struct Case {
        let name: String
        let phrase: String
        var setup: (SelfTest) -> Void = { _ in }
        /// Nil when the text is right, otherwise what is wrong.
        let check: (String) -> String?
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func missing(_ expected: [String], in text: String) -> String? {
        let found = Set(words(text))
        let gone = expected.filter { !found.contains($0.lowercased()) }
        return gone.isEmpty ? nil : "missing \(gone.joined(separator: ", "))"
    }

    var cases: [Case] {
        [
            Case(name: "Plain dictation", phrase: "The quick brown fox jumps over the lazy dog.") { text in
                if let m = Self.missing(["quick", "brown", "fox", "lazy", "dog"], in: text) { return m }
                if text.first?.isUppercase != true { return "does not start with a capital" }
                return [".", "!", "?"].contains(String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(1))) ? nil : "no closing punctuation"
            },
            Case(name: "Dictionary word", phrase: "I would like some marmalade on my toast.") { text in
                if !text.contains("Murmurly") { return "dictionary spelling Murmurly not used" }
                return Self.words(text).contains("marmalade") ? "heard-as word left in" : nil
            },
            Case(name: "Snippet", phrase: "Please add my quality signature.") { text in
                text.contains("Best wishes,\nThe Murmur QA bot") ? nil : "snippet text not inserted exactly"
            },
            Case(name: "AI edits off (rules only)", phrase: "Um, so I think we should, uh, move the launch to Friday.",
                 setup: { $0.settings.transformsEnabled = false }) { text in
                if let m = Self.missing(["launch", "friday"], in: text) { return m }
                let w = Self.words(text)
                return w.contains("um") || w.contains("uh") ? "filler words left in" : nil
            },
            Case(name: "Numbered list (Smart Formatting)",
                 phrase: "My three goals for today are, first, ship the app, second, write the docs, and third, take a break.",
                 setup: { $0.settings.transformsEnabled = true; $0.settings.smartFormatting = true }) { text in
                let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                let numbered = ["1.", "2.", "3."].filter { n in lines.contains { $0.hasPrefix(n) } }
                return numbered.count == 3 ? Self.missing(["ship", "docs", "break"], in: text) : "not a numbered list"
            },
        ]
    }

    func run() async -> String {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let startedAt = Date()
        let saved = (transforms: settings.transformsEnabled, smart: settings.smartFormatting, sounds: settings.soundsEnabled)
        let clipboard = Self.saveClipboard()
        let sentinel = "murmur-self-test-\(UUID().uuidString.prefix(8))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sentinel, forType: .string)
        settings.soundsEnabled = false
        settings.transformsEnabled = true
        let entry = DictionaryRecord(term: "marmalade", replacement: "Murmurly")
        let snippet = SnippetRecord(cue: "quality signature", expansion: "Best wishes,\nThe Murmur QA bot")
        try? store.save(entry)
        try? store.save(snippet)
        report = ["Murmur self-test, \(Date().formatted(date: .abbreviated, time: .standard))", ""]

        // Synthesize every clip first, so the document is only open while dictating.
        var clips: [String: [Float]] = [:]
        for phrase in cases.map(\.phrase) + ["Let's grab coffee after the meeting."] {
            clips[phrase] = await synthesize(phrase)
        }

        if let field = await openScratchDocument() {
            for c in cases {
                c.setup(self)
                try? await Task.sleep(for: .milliseconds(900))
                Self.setValue(field, "")
                let t0 = Date()
                guard controller.dictateForTest(clips[c.phrase] ?? []) else {
                    record(c.name, "could not start a dictation", text: "")
                    continue
                }
                let finished = await waitIdle()
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let text = Self.value(field) ?? ""
                record(c.name, finished ? (text.isEmpty ? "nothing was inserted" : c.check(text)) : "timed out", text: text, ms: ms)
            }
            settings.smartFormatting = saved.smart

            // Esc while processing inserts nothing; Undo on the notice inserts it after all.
            Self.setValue(field, "")
            if controller.dictateForTest(clips["Let's grab coffee after the meeting."] ?? []) {
                try? await Task.sleep(for: .milliseconds(120))
                controller.cancelCurrent()
                try? await Task.sleep(for: .milliseconds(1500))
                let afterCancel = Self.value(field) ?? ""
                record("Cancel while processing", afterCancel.isEmpty ? nil : "text was inserted after Esc", text: afterCancel)
                controller.undoCancel()
                _ = await waitIdle()
                let afterUndo = Self.value(field) ?? ""
                record("Undo after cancel", Self.missing(["coffee", "meeting"], in: afterUndo), text: afterUndo)
            } else {
                record("Cancel while processing", "could not start a dictation", text: "")
            }

            // Paste last transcript (⌃⌘V) inserts the newest dictation again.
            Self.setValue(field, "")
            let last = (try? store.lastWithText())?.bestText ?? ""
            controller.pasteLast()
            try? await Task.sleep(for: .milliseconds(1200))
            let pasted = Self.value(field) ?? ""
            record("Paste last transcript", pasted.trimmingCharacters(in: .whitespacesAndNewlines) == last ? nil : "pasted text differs from the newest dictation", text: pasted)

            Self.setValue(field, "")
            await closeScratchDocument(field)
        } else {
            record("Open TextEdit", "the scratch document did not get keyboard focus", text: "")
        }

        // The clipboard holds what it held before every paste.
        try? await Task.sleep(for: .milliseconds(800))
        let board = NSPasteboard.general.string(forType: .string)
        record("Clipboard restored after pastes", board == sentinel ? nil : "clipboard changed", text: "")

        // Every dictation reached History; then remove the test's rows.
        let rows = ((try? store.recent(limit: 100)) ?? []).filter { $0.startedAt >= startedAt && $0.appName == "TextEdit" }
        let inserted = rows.filter { $0.status == .inserted }.count
        record("History rows written", inserted >= cases.count + 1 ? nil : "only \(inserted) inserted rows", text: "\(rows.count) rows, \(inserted) inserted")
        for row in rows {
            try? store.deleteRecord(id: row.id)
            if let path = row.audioPath { try? FileManager.default.removeItem(atPath: path) }
        }

        try? store.deleteDictionaryEntry(id: entry.id)
        try? store.deleteSnippet(id: snippet.id)
        settings.transformsEnabled = saved.transforms
        settings.smartFormatting = saved.smart
        settings.soundsEnabled = saved.sounds
        Self.restoreClipboard(clipboard)

        let summary = "Self-test: \(passed) of \(total) passed"
        report.insert(summary, at: 1)
        try? report.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        return summary
    }

    private func record(_ name: String, _ failure: String?, text: String, ms: Int? = nil) {
        total += 1
        if failure == nil { passed += 1 }
        let timing = ms.map { " (\($0) ms)" } ?? ""
        let shown = text.replacingOccurrences(of: "\n", with: "⏎")
        report.append("\(failure == nil ? "PASS" : "FAIL") \(name)\(timing)\(failure.map { ": \($0)" } ?? "")\(shown.isEmpty ? "" : "\n     «\(shown)»")")
    }

    private func waitIdle(timeout: Double = 20) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while controller.isBusy {
            if Date() > end { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(400))
        return true
    }

    /// The system voice, 16 kHz, with half a second of silence on each side like a real key press.
    private func synthesize(_ phrase: String) async -> [Float] {
        let url = dir.appendingPathComponent("clip-\(abs(phrase.hashValue)).wav")
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

    // MARK: TextEdit through Accessibility

    var documentURL: URL { dir.appendingPathComponent("Murmur self-test.txt") }

    private func openScratchDocument() async -> AXUIElement? {
        try? "".write(to: documentURL, atomically: true, encoding: .utf8)
        guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return nil }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let app = try? await NSWorkspace.shared.open([documentURL], withApplicationAt: textEdit, configuration: config) else { return nil }
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(100))
            if app.isActive, let field = Self.focused(pid: app.processIdentifier), Self.attribute(field, kAXRoleAttribute) == kAXTextAreaRole {
                return field
            }
        }
        return nil
    }

    private func closeScratchDocument(_ field: AXUIElement) async {
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(field, kAXWindowAttribute as CFString, &window) == .success, let window {
            var close: CFTypeRef?
            if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXCloseButtonAttribute as CFString, &close) == .success, let close {
                AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
        try? FileManager.default.removeItem(at: documentURL)
    }

    static func focused(pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func value(_ element: AXUIElement) -> String? { attribute(element, kAXValueAttribute) }

    static func setValue(_ element: AXUIElement, _ text: String) {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
    }

    // MARK: Clipboard

    static func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    static func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        NSPasteboard.general.clearContents()
        let restored = items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { NSPasteboard.general.writeObjects(restored) }
    }
}
