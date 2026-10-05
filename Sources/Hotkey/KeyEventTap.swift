import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// A listen-only CGEventTap on its own thread that decodes modifier changes and key presses into
/// `KeyEvent`s. Re-enables itself when the system disables it for being slow or after user input.
/// Needs Input Monitoring. Never sees or stores what is typed beyond the key code.
public final class KeyEventTap: @unchecked Sendable {
    public enum TapError: Error, CustomStringConvertible {
        case inputMonitoringDenied
        public var description: String { "could not create the event tap; Input Monitoring is not granted" }
    }

    private let handler: @Sendable (KeyEvent) -> Void
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    /// Fn is tracked from its own key events only: arrow and function keys also set the Fn flag.
    private var fnDown = false
    /// Number of times the system disabled the tap; exposed for diagnostics.
    public private(set) var reenableCount = 0

    public init(handler: @escaping @Sendable (KeyEvent) -> Void) {
        self.handler = handler
    }

    public var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    public func start() throws {
        guard tap == nil else { return }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            if let info {
                Unmanaged<KeyEventTap>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw TapError.inputMonitoringDenied }
        self.tap = tap
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap else { ready.signal(); return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "murmur.keytap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let time = DispatchTime.now().uptimeNanoseconds
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                reenableCount += 1
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .flagsChanged:
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function) {
                fnDown = event.flags.contains(.maskSecondaryFn)
            }
            handler(.modifiers(held: held(event.flags), time: time))
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            handler(.keyDown(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), time: time))
        case .keyUp:
            handler(.keyUp(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), time: time))
        case .otherMouseDown:
            handler(.mouseDown(button: Int(event.getIntegerValueField(.mouseEventButtonNumber)), time: time))
        case .otherMouseUp:
            handler(.mouseUp(button: Int(event.getIntegerValueField(.mouseEventButtonNumber)), time: time))
        default:
            break
        }
    }

    private func held(_ flags: CGEventFlags) -> Set<ModifierKey> {
        var set: Set<ModifierKey> = []
        if fnDown { set.insert(.fn) }
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskCommand) { set.insert(.command) }
        if flags.contains(.maskShift) { set.insert(.shift) }
        return set
    }
}

/// A system-wide shortcut registered with Carbon (`RegisterEventHotKey`). It is consumed, so the
/// frontmost app never sees it, and it needs no permission. Used for Paste and Copy last transcript.
public final class GlobalHotKey: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [UInt32: @Sendable () -> Void] = [:]
    nonisolated(unsafe) private static var nextId: UInt32 = 1
    nonisolated(unsafe) private static var installed = false

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// `keyCode` is a virtual key code; `modifiers` are Carbon masks (`controlKey`, `cmdKey`, …).
    /// Must be called on the main thread of an app with a running event loop.
    public init?(keyCode: Int, modifiers: Int, action: @escaping @Sendable () -> Void) {
        Self.lock.lock()
        id = Self.nextId
        Self.nextId += 1
        Self.handlers[id] = action
        let needsHandler = !Self.installed
        Self.installed = true
        Self.lock.unlock()

        if needsHandler {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                GlobalHotKey.lock.lock()
                let action = GlobalHotKey.handlers[hotKeyID.id]
                GlobalHotKey.lock.unlock()
                action?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D52_4D52), id: id) // "MRMR"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.lock.lock()
        Self.handlers[id] = nil
        Self.lock.unlock()
    }
}
