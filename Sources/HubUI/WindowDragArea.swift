import AppKit
import SwiftUI

/// An empty strip that moves the window, for the parts of a transparent title bar that SwiftUI content
/// covers (AppKit only drags from the title bar itself). Double-click follows the system setting.
public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public final class DragView: NSView {
        override public var mouseDownCanMoveWindow: Bool { true }

        override public func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else {
                window?.performDrag(with: event)
                return
            }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        }
    }

    public func makeNSView(context: Context) -> NSView { DragView() }
    public func updateNSView(_ view: NSView, context: Context) {}
}
