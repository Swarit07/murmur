import AppKit
import MurmurKit
import SwiftUI
import UI

/// What the menu bar dropdown's header mirrors (§5.2): ready, loading, listening with a live timer,
/// working, or the last error with its one-line fix.
@MainActor
@Observable
public final class MenuHeaderModel {
    public var phase: DictationStatus.Phase = .loading
    public var message: String?
    public var hotkey = "fn"
    public var microphone = ""
    public var recordingSince: Date?

    public init() {}

    /// The status and its message, split into a title and a fix line ("Transcription failed." / "The audio
    /// is saved in History.").
    var lines: (title: String, detail: String) {
        if let message, !isBusy {
            let parts = message.split(separator: ". ", maxSplits: 1).map(String.init)
            let title = parts[0].hasSuffix(".") || parts.count == 1 ? parts[0] : parts[0] + "."
            return (title, parts.count > 1 ? parts[1] : "Open Murmur for details.")
        }
        return switch phase {
        case .loading: ("Loading models…", "Dictation starts as soon as they're ready.")
        case .idle, .inserted, .error: ("Murmur is ready", "Hold \(hotkey) to dictate · double-tap for hands-free")
        case .recording: ("Listening…", microphone)
        case .processing: ("Working…", "Writing what you said")
        }
    }

    var isBusy: Bool {
        switch phase {
        case .recording, .processing: true
        default: false
        }
    }
}

/// The dropdown's first item: a custom view in an otherwise native `NSMenu`.
public struct MenuHeaderView: View {
    let model: MenuHeaderModel
    @Environment(\.theme) private var theme

    public init(model: MenuHeaderModel) {
        self.model = model
    }

    public var body: some View {
        let c = theme.colors
        let lines = model.lines
        let recording: Bool = if case .recording = model.phase { true } else { false }
        HStack(alignment: .center, spacing: MenuBarGeometry.menuLiveDotGap) {
            if recording {
                Circle().fill(theme.flow.flowLive.color)
                    .frame(width: MenuBarGeometry.menuLiveDot, height: MenuBarGeometry.menuLiveDot)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: MenuBarGeometry.menuTextGap) {
                Text(lines.title).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                if !lines.detail.isEmpty {
                    Text(lines.detail).textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if recording, let since = model.recordingSince {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .textStyle(TypeTokens.keycapSmall).foregroundStyle(c.textSecondary.color)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, MenuBarGeometry.menuInsetH)
        .padding(.vertical, MenuBarGeometry.menuHeaderPaddingV)
        .frame(width: MenuBarGeometry.menuWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The dropdown's last item: "v0.1.0 · on-device engine" in mono.
public struct MenuFooterView: View {
    let text: String
    @Environment(\.theme) private var theme

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text).textStyle(TypeTokens.meta).foregroundStyle(theme.colors.textTertiary.color)
            .padding(.horizontal, MenuBarGeometry.menuInsetH)
            .padding(.vertical, MenuBarGeometry.menuFooterPaddingV)
            .frame(width: MenuBarGeometry.menuWidth, alignment: .leading)
    }
}

extension NSMenuItem {
    /// A menu item that shows a SwiftUI view (themed, at the Hub's default text size).
    @MainActor
    public static func hosting(_ view: some View) -> NSMenuItem {
        let host = NSHostingView(rootView: ThemeProvider { view })
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let item = NSMenuItem()
        item.view = host
        return item
    }
}
