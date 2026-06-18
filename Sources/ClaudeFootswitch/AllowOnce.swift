import AppKit
import ApplicationServices
import CoreGraphics
import os

struct AllowOnceResult {
    let success: Bool
    let message: String
}

/// Approves Claude's prompt by sending the "Allow once" keyboard shortcut (⌘↩) to the
/// Claude app.
///
/// This is deliberately *not* an accessibility-tree button press: Claude's permission UI
/// is web content that doesn't reliably expose tappable AX buttons, but it does bind ⌘↩
/// to "Allow once". Synthesizing that chord is simpler and far more reliable. Posting
/// keystrokes to another app still requires Accessibility permission.
final class AllowOnce {
    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "AllowOnce")

    var targetBundleID = Settings.defaultBundleID

    private let commandKey: CGKeyCode = 55 // kVK_Command
    private let returnKey: CGKeyCode = 36  // kVK_Return

    // MARK: Approve

    @discardableResult
    func approve() -> AllowOnceResult {
        guard Permissions.accessibilityTrusted else {
            return AllowOnceResult(success: false, message: "Accessibility permission not granted (needed to send keystrokes).")
        }
        guard let app = candidateApps().first else {
            return AllowOnceResult(success: false, message: "Claude isn’t running (looked for \(targetBundleID)).")
        }

        let pid = app.processIdentifier
        let name = app.localizedName ?? "Claude"
        let previous = NSWorkspace.shared.frontmostApplication

        // Claude's ⌘↩ accelerator only fires when it's the key app. If it isn't frontmost,
        // bring it forward, send the chord, then hand focus straight back to where the user
        // was — so Claude can sit off to the side and they stay in flow (Mail, etc.).
        if previous?.processIdentifier == pid {
            sendCommandReturn()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.sendCommandReturn()
                guard let previous, previous.processIdentifier != pid else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    previous.activate(options: [.activateIgnoringOtherApps])
                    Diag.log("restored focus to \(previous.localizedName ?? "previous app")")
                }
            }
        }

        log.info("Sent ⌘↩ to \(name, privacy: .public).")
        return AllowOnceResult(success: true, message: "Sent ⌘↩ to \(name).")
    }

    private func sendCommandReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        func post(_ key: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        // Full chord: Command down, Return down+up (with Command held), Command up.
        post(commandKey, keyDown: true, flags: .maskCommand)
        post(returnKey, keyDown: true, flags: .maskCommand)
        post(returnKey, keyDown: false, flags: .maskCommand)
        post(commandKey, keyDown: false, flags: [])
    }

    // MARK: Target app

    func targetAppName() -> String? { candidateApps().first?.localizedName }
    func isTargetRunning() -> Bool { !candidateApps().isEmpty }

    private func candidateApps() -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications
        let exact = running.filter { $0.bundleIdentifier == targetBundleID }
        if !exact.isEmpty { return exact }
        return running.filter {
            ($0.bundleIdentifier ?? "").hasPrefix("com.anthropic.") || $0.localizedName == "Claude"
        }
    }

    // MARK: Diagnostics — list buttons the AX tree exposes (best-effort)

    func allPressableLabels() -> [String] {
        guard Permissions.accessibilityTrusted else { return [] }
        var labels: [String] = []
        for app in candidateApps() {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            traverse(axApp) { _, pressable, text in
                if pressable, !text.isEmpty { labels.append(text) }
                return true
            }
        }
        return labels
    }

    private func traverse(_ root: AXUIElement, visit: (AXUIElement, Bool, String) -> Bool) {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while let (element, depth) = stack.popLast() {
            visited += 1
            if visited > 12_000 { break }
            let pressable = actionNames(element).contains(kAXPressAction)
            let text = pressable ? label(of: element) : ""
            if !visit(element, pressable, text) { return }
            if depth < 70 {
                for child in children(element) { stack.append((child, depth + 1)) }
            }
        }
    }

    private func label(of element: AXUIElement) -> String {
        var parts: [String] = []
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            if let s = stringAttr(element, attr), !s.isEmpty { parts.append(s) }
        }
        return parts.joined(separator: " ")
    }

    private func stringAttr(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }
}
