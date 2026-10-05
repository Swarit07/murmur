import Context
import Foundation
@testable import Insertion
import Testing

final class FakePasteboard: Pasteboarding, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [PasteboardSnapshot.Item]
    private var count: Int
    var writes: [(String, [String])] = []

    init(items: [PasteboardSnapshot.Item] = [], changeCount: Int = 100) {
        self.items = items
        self.count = changeCount
    }

    var changeCount: Int { lock.withLock { count } }

    func snapshot() -> PasteboardSnapshot { lock.withLock { PasteboardSnapshot(items: items, changeCount: count) } }

    func writeTranscript(_ text: String, markers: [String]) -> Int {
        lock.withLock {
            items = [PasteboardSnapshot.Item([("public.utf8-plain-text", Data(text.utf8))] + markers.map { ($0, Data()) })]
            writes.append((text, markers))
            count += 1
            return count
        }
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        lock.withLock {
            items = snapshot.items
            count += 1
        }
    }

    func string() -> String? {
        lock.withLock {
            items.first?.types.first(where: { $0.0 == "public.utf8-plain-text" }).map { String(decoding: $0.1, as: UTF8.self) }
        }
    }

    /// Simulates the user copying something.
    func userCopies(_ text: String) {
        lock.withLock {
            items = [PasteboardSnapshot.Item([("public.utf8-plain-text", Data(text.utf8))])]
            count += 1
        }
    }

    var currentItems: [PasteboardSnapshot.Item] { lock.withLock { items } }
}

final class FakeSender: PasteSending, @unchecked Sendable {
    let succeeds: Bool
    let onPaste: (@Sendable () -> Void)?
    private(set) var calls = 0
    init(succeeds: Bool = true, onPaste: (@Sendable () -> Void)? = nil) {
        self.succeeds = succeeds
        self.onPaste = onPaste
    }
    func sendPaste(to pid: pid_t) -> Bool {
        calls += 1
        if succeeds { onPaste?() }
        return succeeds
    }
}

@Suite("Insertion transaction")
struct InsertionTransactionTests {
    let focus = FocusSnapshot(pid: 42, bundleId: "com.apple.TextEdit")

    /// Plain text, rich text, an image, a file URL, PDF and RTFD on two items.
    static func richClipboard() -> [PasteboardSnapshot.Item] {
        [
            PasteboardSnapshot.Item([
                ("public.utf8-plain-text", Data("original".utf8)),
                ("public.rtf", Data("{\\rtf1 original}".utf8)),
                ("public.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ]),
            PasteboardSnapshot.Item([
                ("public.file-url", Data("file:///Users/me/report.pdf".utf8)),
                ("com.adobe.pdf", Data([0x25, 0x50, 0x44, 0x46])),
                ("com.apple.flat-rtfd", Data([1, 2, 3])),
            ]),
        ]
    }

    @Test func restoresEveryItemAndType() async {
        let board = FakePasteboard(items: Self.richClipboard())
        let sender = FakeSender()
        let tx = InsertionTransaction(pasteboard: board, sender: sender, restoreDelay: .milliseconds(10))
        let result = await tx.insert("Hello.", expected: focus, current: focus)
        #expect(result == .inserted(restored: true))
        #expect(board.currentItems == Self.richClipboard())
        #expect(sender.calls == 1)
        // The transcript went on with the transient and concealed markers.
        #expect(board.writes.first?.1 == PasteboardMarkers.all)
    }

    @Test func emptyClipboardStaysEmpty() async {
        let board = FakePasteboard(items: [])
        let tx = InsertionTransaction(pasteboard: board, sender: FakeSender(), restoreDelay: .milliseconds(10))
        #expect(await tx.insert("Hi", expected: focus, current: focus) == .inserted(restored: true))
        #expect(board.currentItems.isEmpty)
    }

    /// I2: a copy made during the wait must be kept.
    @Test func userCopyDuringWindowIsKept() async {
        let board = FakePasteboard(items: Self.richClipboard())
        let sender = FakeSender(onPaste: { [board] in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { board.userCopies("user copy") }
        })
        let tx = InsertionTransaction(pasteboard: board, sender: sender, restoreDelay: .milliseconds(150))
        let result = await tx.insert("Hello.", expected: focus, current: focus)
        #expect(result == .inserted(restored: false))
        #expect(board.string() == "user copy")
    }

    /// I3: focus changed since key down. Nothing pasted, transcript left on the clipboard.
    @Test func focusChangedFails() async {
        let board = FakePasteboard(items: Self.richClipboard())
        let sender = FakeSender()
        let other = FocusSnapshot(pid: 7, bundleId: "com.apple.Safari")
        let tx = InsertionTransaction(pasteboard: board, sender: sender, restoreDelay: .milliseconds(10))
        #expect(await tx.insert("Hello.", expected: focus, current: other) == .failed(.focusChanged))
        #expect(sender.calls == 0)
        #expect(board.string() == "Hello.")
        #expect(board.writes.last?.1 == [])
    }

    /// I6: never write into secure fields.
    @Test func secureFieldFails() async {
        let board = FakePasteboard(items: Self.richClipboard())
        let sender = FakeSender()
        let secure = FocusSnapshot(pid: 42, bundleId: "com.apple.TextEdit", subrole: "AXSecureTextField", isSecure: true)
        let tx = InsertionTransaction(pasteboard: board, sender: sender, restoreDelay: .milliseconds(10))
        #expect(await tx.insert("hunter2", expected: secure, current: secure) == .failed(.secureField))
        #expect(sender.calls == 0)
    }

    /// I5: the paste keystroke could not be sent. Transcript stays on the clipboard, no restore.
    @Test func pasteNotSentLeavesTranscript() async {
        let board = FakePasteboard(items: Self.richClipboard())
        let tx = InsertionTransaction(pasteboard: board, sender: FakeSender(succeeds: false), restoreDelay: .milliseconds(10))
        #expect(await tx.insert("Hello.", expected: focus, current: focus) == .failed(.pasteNotSent))
        #expect(board.string() == "Hello.")
        #expect(board.writes.last?.1 == [])
    }

    @Test func noTextBoxWhenRequired() async {
        let board = FakePasteboard()
        let notEditable = FocusSnapshot(pid: 42, bundleId: "com.apple.finder", isEditable: false)
        let tx = InsertionTransaction(pasteboard: board, sender: FakeSender(), restoreDelay: .milliseconds(10), requireEditable: true)
        #expect(await tx.insert("Hello.", expected: notEditable, current: notEditable) == .failed(.noTextBox))
    }

    @Test func remoteDesktopWaitsLonger() async {
        let board = FakePasteboard()
        let rdp = FocusSnapshot(pid: 9, bundleId: "com.microsoft.rdc.macos")
        let tx = InsertionTransaction(pasteboard: board, sender: FakeSender(), restoreDelay: .milliseconds(10), remoteDesktopDelay: .milliseconds(200))
        let start = Date()
        _ = await tx.insert("Hi", expected: rdp, current: rdp)
        #expect(Date().timeIntervalSince(start) >= 0.19)
    }
}

@Suite("Smart spacing")
struct SmartSpacingTests {
    @Test(arguments: [
        ("Let's push.", Character("."), " Let's push."),
        ("hello", Character("d"), " hello"),
        ("Hello.", Character(" "), "Hello."),
        ("Hello.", Character("\n"), "Hello."),
        ("quoted", Character("\u{201C}"), "quoted"),
        (", and more", Character("d"), ", and more"),
        ("Hi", Character("("), "Hi"),
    ])
    func adjust(text: String, before: Character, expected: String) {
        #expect(SmartSpacing.adjust(text, before: before) == expected)
    }

    @Test func unknownCursorAddsNothing() {
        #expect(SmartSpacing.adjust("Hello.", before: nil) == "Hello.")
        #expect(SmartSpacing.adjust("", before: "a") == "")
    }
}
