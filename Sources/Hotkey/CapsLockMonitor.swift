import Foundation
import IOKit
import IOKit.hid

/// Caps Lock press and release from the keyboard HID reports. The event tap only sees Caps Lock when its
/// lock state flips (once per press), so holding it as push-to-talk needs the raw key. While Caps Lock is
/// a Murmur shortcut, the lock state is put back after each press so typing is not left in capitals.
/// Needs Input Monitoring, like the event tap.
public final class CapsLockMonitor: @unchecked Sendable {
    private let handler: @Sendable (KeyEvent) -> Void
    private var manager: IOHIDManager?
    private var lockStateBeforePress = false

    public init(handler: @escaping @Sendable (KeyEvent) -> Void) {
        self.handler = handler
    }

    public func start() -> Bool {
        guard manager == nil else { return true }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardCapsLock) else { return }
            let down = IOHIDValueGetIntegerValue(value) != 0
            Unmanaged<CapsLockMonitor>.fromOpaque(context).takeUnretainedValue().caps(down: down)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        self.manager = manager
        return true
    }

    public func stop() {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    private func caps(down: Bool) {
        if down {
            lockStateBeforePress = Self.lockState() ?? false
        } else {
            // The system flips the lock on press; put it back once the key is up.
            let restore = lockStateBeforePress
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.setLockState(restore) }
        }
        handler(.capsLock(down: down, time: DispatchTime.now().uptimeNanoseconds))
    }

    static func withHIDSystem<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connect) }
        return body(connect)
    }

    static func lockState() -> Bool? {
        withHIDSystem { connect in
            var state = false
            return IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS ? state : nil
        }
    }

    static func setLockState(_ on: Bool) {
        _ = withHIDSystem { IOHIDSetModifierLockState($0, Int32(kIOHIDCapsLockState), on) }
    }
}
