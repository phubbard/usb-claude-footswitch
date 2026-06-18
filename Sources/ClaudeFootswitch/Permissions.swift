import AppKit
import ApplicationServices
import IOKit.hid

/// Thin wrappers around the two TCC permissions this app needs:
/// Accessibility (to press the button) and Input Monitoring (to read the pedal).
enum Permissions {

    // MARK: Accessibility

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Checks Accessibility trust; pass `prompt: true` to surface the system prompt.
    @discardableResult
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: Input Monitoring

    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Asks the system to grant Input Monitoring. Returns true if already granted.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    // MARK: -

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
