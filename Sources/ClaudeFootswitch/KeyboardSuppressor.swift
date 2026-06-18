import AppKit
import CoreGraphics
import os

/// Swallows the foot pedal's own keystroke (this pedal types Return) so a stomp doesn't
/// leak an Enter to the focused app — which, in a terminal, could submit a command.
///
/// We can't seize the keyboard in userspace, so instead we run a CGEventTap and drop
/// Return events in a short window *armed by a confirmed pedal press*. The pedal is
/// identified definitively by IOHIDManager (VID/PID), so the real Enter key is untouched
/// outside that window. Requires Accessibility permission (same as posting ⌘↩).
final class KeyboardSuppressor {
    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "Suppress")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var suppressUntil = Date.distantPast
    private let returnKeyCode: Int64 = 36 // kVK_Return

    /// Window after a pedal press during which Return events are dropped.
    var window: TimeInterval = 0.25
    /// Master on/off (menu-controlled).
    var enabled = true

    var isRunning: Bool { tap != nil }

    /// Call the instant a pedal press is detected, before the stray Return reaches the tap.
    func arm() {
        suppressUntil = Date().addingTimeInterval(window)
    }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<KeyboardSuppressor>.fromOpaque(refcon)
                    .takeUnretainedValue()
                    .handle(type: type, event: event)
            },
            userInfo: ctx
        ) else {
            log.error("CGEventTap creation failed (Accessibility not granted?).")
            Diag.log("CGEventTap FAILED to create — Accessibility?")
            return
        }

        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Diag.log("CGEventTap installed (Return suppression ready)")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that's slow or on certain input; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == returnKeyCode else { return Unmanaged.passUnretained(event) }

        // The pedal types a PLAIN Return; our own approve sends ⌘↩ (Command held). Only
        // ever drop the plain one, and only just after a confirmed pedal press, so the
        // real Enter key and our own ⌘↩ are never touched.
        let hasCommand = event.flags.contains(.maskCommand)
        let armed = Date() < suppressUntil
        let suppress = enabled && armed && !hasCommand
        if armed { // log only the interesting window, not every Return system-wide
            Diag.log("tap Return \(type == .keyDown ? "down" : "up") cmd=\(hasCommand) → \(suppress ? "SUPPRESSED" : "passed")")
        }
        return suppress ? nil : Unmanaged.passUnretained(event)
    }
}
