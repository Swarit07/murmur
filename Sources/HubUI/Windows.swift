import AppKit
import AVFoundation
import Combine
import MurmurKit
import SwiftUI
import UI

/// Opens one window per kind and brings it forward when asked again.
@MainActor
public final class WindowManager {
    public init() {}

    private var windows: [String: NSWindow] = [:]

    public enum Chrome: Sendable {
        /// A normal title bar with the title.
        case standard
        /// A transparent 52-pt title bar that the content draws under; the traffic lights sit centered
        /// in it (the Hub's sidebar runs to the top of the window).
        case unified
        /// A transparent 28-pt title bar with no title; the content draws under it.
        case transparent
    }

    public func show<V: View>(_ id: String, title: String, size: NSSize, chrome: Chrome = .standard, @ViewBuilder content: () -> V) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = Self.makeWindow(id: id, title: title, size: size, chrome: chrome, content: content)
        window.center()
        if chrome == .unified { window.setFrameAutosaveName("murmur.\(id)") }
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Builds a window with Murmur's chrome without showing it (the snapshot tool renders these).
    public static func makeWindow<V: View>(id: String, title: String, size: NSSize, chrome: Chrome, @ViewBuilder content: () -> V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        if chrome != .standard {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }
        if chrome == .unified {
            window.toolbar = NSToolbar(identifier: "murmur.\(id)")
            window.toolbarStyle = .unified
        }
        window.setContentSize(size)
        return window
    }

    public func window(_ id: String) -> NSWindow? { windows[id] }

    public func close(_ id: String) {
        windows[id]?.close()
        windows[id] = nil
    }

    public func showTokens(forceState: ((FlowBarGalleryEntry?) -> Void)? = nil) {
        show("tokens", title: "Flow Bar Tokens", size: NSSize(width: 460, height: 760)) { TokenPanel(forceState: forceState) }
    }
}

/// Display names for the speech engines and cleanup models offered in Settings.
public enum ModelNames {
    public static let engines: [String: String] = [
        "parakeet-ultra": "Parakeet ultra (recommended)", "parakeet-v3": "Parakeet v3", "parakeet-v2": "Parakeet v2 (English)",
        "parakeet-phonon2": "Parakeet phonon2", "whisper-turbo": "Whisper Large v3 Turbo", "apple-speech": "Apple on-device",
        "groq-whisper": "Groq Whisper (cloud, needs key)",
    ]

    public static let cleanup: [String: String] = [
        "mlx:qwen3.5-4b": "Qwen3.5 4B (recommended)", "mlx:smollm3-3b": "SmolLM3 3B (less memory)", "mlx:qwen3-4b-2507": "Qwen3 4B 2507",
        "mlx:qwen3.5-2b": "Qwen3.5 2B", "apple-foundation": "Apple on-device", "groq": "Groq (cloud, needs key)",
        "openrouter": "OpenRouter (cloud, needs key)", "rules": "Rules only (no AI)",
    ]
}
