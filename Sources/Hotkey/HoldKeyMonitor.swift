import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Watches one modifier key system-wide with a listen-only CGEventTap on its own thread and reports
/// when it goes down and up. Also reports Esc. Needs Input Monitoring.
///
/// Milestone 0 scope: modifier-only push-to-talk. Taps, double-taps, chords and the Fn-with-another-key
/// rule (D1) arrive with the full recognizer in Milestone 1.
public final class HoldKeyMonitor: @unchecked Sendable {
    public enum Key: String, CaseIterable, Sendable {
        case rightOption = "right-option"
        case rightCommand = "right-command"
        case rightControl = "right-control"
        case fn

        var keyCode: Int64 {
            switch self {
            case .rightOption: Int64(kVK_RightOption)
            case .rightCommand: Int64(kVK_RightCommand)
            case .rightControl: Int64(kVK_RightControl)
            case .fn: Int64(kVK_Function)
            }
        }

        var flag: CGEventFlags {
            switch self {
            case .rightOption: .maskAlternate
            case .rightCommand: .maskCommand
            case .rightControl: .maskControl
            case .fn: .maskSecondaryFn
            }
        }

        public var label: String {
            switch self {
            case .rightOption: "Right Option"
            case .rightCommand: "Right Command"
            case .rightControl: "Right Control"
            case .fn: "Fn (Globe)"
            }
        }
    }

    public enum Event: Sendable {
        case down(UInt64)
        case up(UInt64)
        case escape
    }

    public enum MonitorError: Error, CustomStringConvertible {
        case inputMonitoringDenied
        public var description: String { "could not create the event tap; Input Monitoring is not granted" }
    }

    let key: Key
    let handler: @Sendable (Event) -> Void
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var isDown = false

    public init(key: Key, handler: @escaping @Sendable (Event) -> Void) {
        self.key = key
        self.handler = handler
    }

    public func start() throws {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HoldKeyMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw MonitorError.inputMonitoringDenied }
        self.tap = tap
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap else { return }
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "murmur.hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system turns slow or interrupted taps off; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) { handler(.escape) }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else { return }
            let pressed = event.flags.contains(key.flag)
            let now = DispatchTime.now().uptimeNanoseconds
            if pressed && !isDown {
                isDown = true
                handler(.down(now))
            } else if !pressed && isDown {
                isDown = false
                handler(.up(now))
            }
        default:
            break
        }
    }
}
