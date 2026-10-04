import Context
import Core
import Foundation

public enum InsertionFailure: String, Sendable, Codable, Equatable {
    case focusChanged
    case secureField
    case noTextBox
    case pasteNotSent
}

public enum InsertionResult: Sendable, Equatable {
    /// Pasted. `restored` says whether the previous clipboard was put back (false when the user
    /// copied something during the wait, which is then kept).
    case inserted(restored: Bool)
    /// Nothing pasted; the transcript is left on the clipboard for a manual paste.
    case failed(InsertionFailure)
}

/// Section 4 of the spec: focus guard, pasteboard snapshot, transcript with marker types, paste
/// keystroke, wait, restore only if untouched. On any failure the transcript stays on the clipboard.
public struct InsertionTransaction: Sendable {
    public var pasteboard: any Pasteboarding
    public var sender: any PasteSending
    public var restoreDelay: Duration
    public var remoteDesktopDelay: Duration
    /// When false, an element that does not look editable is still pasted into (many custom editors
    /// report generic roles). The No text box notice is a Milestone 5 item.
    public var requireEditable: Bool

    public static let remoteDesktopBundles: Set<String> = [
        "com.microsoft.rdc.macos", "com.microsoft.rdc.mac", "com.citrix.receiver.icaviewer.mac",
        "com.realvnc.vncviewer", "com.anydesk.anydeskmac", "com.teamviewer.TeamViewer", "com.p5sys.jump.mac.viewer",
    ]

    public init(
        pasteboard: any Pasteboarding = SystemPasteboard(),
        sender: any PasteSending = SystemPasteSender(),
        restoreDelay: Duration = .milliseconds(500),
        remoteDesktopDelay: Duration = .seconds(5),
        requireEditable: Bool = false
    ) {
        self.pasteboard = pasteboard
        self.sender = sender
        self.restoreDelay = restoreDelay
        self.remoteDesktopDelay = remoteDesktopDelay
        self.requireEditable = requireEditable
    }

    /// Runs the whole transaction. `onPasted` fires right after the keystroke is posted, before the
    /// restore wait, so callers can stop the latency clock there.
    public func insert(
        _ text: String,
        expected: FocusSnapshot,
        current: FocusSnapshot,
        onPasted: (@Sendable () -> Void)? = nil
    ) async -> InsertionResult {
        // 1. Focus guard and secure-field check.
        if let failure = guardFailure(expected: expected, current: current) {
            _ = pasteboard.writeTranscript(text, markers: [])
            return .failed(failure)
        }
        // 2. Snapshot.
        let saved = pasteboard.snapshot()
        // 3. Transcript with marker types; the new change count is the token.
        let token = pasteboard.writeTranscript(text, markers: PasteboardMarkers.all)
        // 4. Paste keystroke.
        guard sender.sendPaste(to: current.pid) else {
            // 7. Leave a plain copy (no concealed markers) so the user can paste it by hand.
            _ = pasteboard.writeTranscript(text, markers: [])
            return .failed(.pasteNotSent)
        }
        onPasted?()
        // 5. Wait for the target app to read the pasteboard.
        let isRemote = current.bundleId.map(Self.remoteDesktopBundles.contains) ?? false
        try? await Task.sleep(for: isRemote ? remoteDesktopDelay : restoreDelay)
        // 6. Restore only if nobody touched the pasteboard since we wrote to it.
        if pasteboard.changeCount == token {
            pasteboard.restore(saved)
            return .inserted(restored: true)
        }
        return .inserted(restored: false)
    }

    public func guardFailure(expected: FocusSnapshot, current: FocusSnapshot) -> InsertionFailure? {
        if current.isSecure || expected.isSecure { return .secureField }
        if !expected.sameFocus(as: current) { return .focusChanged }
        if requireEditable && !current.isEditable { return .noTextBox }
        return nil
    }
}
