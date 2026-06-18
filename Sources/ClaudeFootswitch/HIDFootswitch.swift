import Foundation
import IOKit
import IOKit.hid
import os

/// Watches the RDing USB foot pedal (VID 0x1130 / PID 0x660C) via IOHIDManager and
/// reports a debounced "press" on each pedal-down event.
///
/// The pedal enumerates as a USB HID keyboard (this unit types Return). We read it
/// non-exclusively: macOS doesn't allow a userspace app to truly seize a keyboard
/// (attempting it blocks event delivery *and* re-enumerates the device in a loop), so
/// the pedal's own keystroke still reaches the system. Suppressing that is handled
/// elsewhere, not here.
final class HIDFootswitch {
    static let vendorID = 0x1130
    static let productID = 0x660C

    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "HID")
    private var manager: IOHIDManager?
    private var lastFire = Date.distantPast

    private(set) var isConnected = false

    /// Minimum gap between accepted presses (collapses key-down/up bursts into one).
    var debounceInterval: TimeInterval = 0.25
    /// When true, every raw value is logged (diagnostics).
    var logEvents = false

    /// Invoked on the main thread for each debounced press.
    var onPress: (() -> Void)?
    /// Invoked on the main thread when the pedal connects or disconnects.
    var onConnectionChange: ((Bool) -> Void)?

    // MARK: Lifecycle

    func start() {
        stop()

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        let match: [String: Int] = [
            kIOHIDVendorIDKey: HIDFootswitch.vendorID,
            kIOHIDProductIDKey: HIDFootswitch.productID,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HIDFootswitch>.fromOpaque(context).takeUnretainedValue().handle(value: value)
        }, ctx)

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDFootswitch>.fromOpaque(context).takeUnretainedValue().setConnected(true)
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDFootswitch>.fromOpaque(context).takeUnretainedValue().refreshConnected()
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            log.error("IOHIDManagerOpen failed: \(String(format: "0x%08X", result), privacy: .public).")
            Diag.log("HID open FAILED 0x\(String(format: "%08X", result)) — Input Monitoring not granted?")
        } else {
            log.notice("HID manager opened.")
            Diag.log("HID open OK")
        }
        refreshConnected()
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        setConnected(false)
    }

    // MARK: Connection state

    private func refreshConnected() {
        guard let mgr = manager else { setConnected(false); return }
        let devices = IOHIDManagerCopyDevices(mgr)
        let count = devices.map { CFSetGetCount($0) } ?? 0
        setConnected(count > 0)
    }

    private func setConnected(_ value: Bool) {
        guard value != isConnected else { return }
        isConnected = value
        log.notice("Pedal \(value ? "connected" : "disconnected", privacy: .public).")
        Diag.log("pedal \(value ? "CONNECTED" : "disconnected")")
        onConnectionChange?(value)
    }

    // MARK: Input handling

    private func handle(value: IOHIDValue) {
        guard IOHIDValueGetLength(value) <= 8 else { return }
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        if logEvents {
            Diag.log("value page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue)")
        }

        let onInterestingPage = page == UInt32(kHIDPage_KeyboardOrKeypad)
            || page == UInt32(kHIDPage_Consumer)
            || page == UInt32(kHIDPage_Button)
        guard onInterestingPage, intValue != 0 else { return }
        if page == UInt32(kHIDPage_KeyboardOrKeypad), (0xE0...0xE7).contains(usage) { return }

        let now = Date()
        guard now.timeIntervalSince(lastFire) >= debounceInterval else { return }
        lastFire = now

        log.notice("Pedal pressed.")
        Diag.log("PRESS → invoking approve")
        onPress?()
    }
}
