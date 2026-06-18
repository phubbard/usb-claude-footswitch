import Foundation
import IOKit
import IOKit.hid
import os

/// Watches the RDing USB foot pedal (VID 0x1130 / PID 0x660C) via IOHIDManager and
/// reports a debounced "press" on each pedal-down event.
///
/// The pedal enumerates as a USB HID keyboard, so a press arrives as a key-down value
/// change. We don't care which key it's programmed to send — any non-zero key/button
/// value counts as a press. With `seize`, the device is opened exclusively so that
/// key never reaches the focused app.
final class HIDFootswitch {
    static let vendorID = 0x1130
    static let productID = 0x660C

    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "HID")
    private var manager: IOHIDManager?
    private var lastFire = Date.distantPast

    private(set) var isConnected = false

    /// Minimum gap between accepted presses (collapses key-down/up bursts into one).
    var debounceInterval: TimeInterval = 0.25
    /// When true, every raw HID value is logged (diagnostics).
    var logEvents = false

    /// Invoked on the main thread for each debounced press.
    var onPress: (() -> Void)?
    /// Invoked on the main thread when the pedal connects or disconnects.
    var onConnectionChange: ((Bool) -> Void)?

    // MARK: Lifecycle

    func start(seize: Bool) {
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

        let seizeOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        let noneOptions = IOOptionBits(kIOHIDOptionsTypeNone)
        var result = IOHIDManagerOpen(mgr, seize ? seizeOptions : noneOptions)
        if result != kIOReturnSuccess, seize {
            // Seizing can fail where a plain open succeeds — fall back so the pedal still works.
            log.notice("Seize open failed (\(String(format: "0x%08X", result), privacy: .public)); retrying without seize.")
            result = IOHIDManagerOpen(mgr, noneOptions)
        }
        if result != kIOReturnSuccess {
            log.error("IOHIDManagerOpen failed: \(String(format: "0x%08X", result), privacy: .public). Input Monitoring likely not granted — grant it, then relaunch.")
        } else {
            log.notice("HID manager opened (seize=\(seize, privacy: .public)).")
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
        onConnectionChange?(value)
    }

    // MARK: Input handling

    private func handle(value: IOHIDValue) {
        // Skip multi-byte values (e.g. opaque vendor reports) that GetIntegerValue can't represent.
        guard IOHIDValueGetLength(value) <= 8 else { return }

        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        if logEvents {
            log.info("event page=0x\(String(page, radix: 16), privacy: .public) usage=0x\(String(usage, radix: 16), privacy: .public) value=\(intValue, privacy: .public)")
        }

        // React to a key/button "down" on the keyboard, consumer, or button pages.
        let onInterestingPage = page == UInt32(kHIDPage_KeyboardOrKeypad)
            || page == UInt32(kHIDPage_Consumer)
            || page == UInt32(kHIDPage_Button)
        guard onInterestingPage, intValue != 0 else { return }

        // Ignore bare modifier keys (Left Control … Right GUI) so a modifier-only report is no-op.
        if page == UInt32(kHIDPage_KeyboardOrKeypad), (0xE0...0xE7).contains(usage) { return }

        let now = Date()
        guard now.timeIntervalSince(lastFire) >= debounceInterval else { return }
        lastFire = now

        log.notice("Pedal pressed.")
        onPress?()
    }
}
