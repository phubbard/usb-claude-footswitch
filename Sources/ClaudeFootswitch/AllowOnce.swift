import AppKit
import ApplicationServices
import os

struct AllowOnceResult {
    let pressed: Bool
    let message: String
    let discoveredLabels: [String]
}

/// Finds and presses the target button (default "Allow once") inside the Claude
/// desktop app using the Accessibility API. Works even when Claude is in the
/// background and regardless of where its window sits.
///
/// Claude is an Electron/Chromium app, so its buttons live in a web a11y tree that
/// Chromium only exposes on demand — we flip that on with the `AXManualAccessibility`
/// attribute before searching.
final class AllowOnce {
    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "AllowOnce")

    var targetBundleID = Settings.defaultBundleID
    var label = Settings.defaultLabel

    private let maxNodes = 12_000
    private let maxDepth = 70

    // MARK: Public

    @discardableResult
    func press(dryRun: Bool = false) -> AllowOnceResult {
        guard Permissions.accessibilityTrusted else {
            return AllowOnceResult(pressed: false, message: "Accessibility permission not granted.", discoveredLabels: [])
        }
        let apps = candidateApps()
        guard !apps.isEmpty else {
            return AllowOnceResult(pressed: false, message: "Claude isn’t running (looked for \(targetBundleID)).", discoveredLabels: [])
        }

        let needle = label.lowercased()
        var seen: [String] = []

        for app in apps {
            let axApp = appElement(for: app)
            var match: AXUIElement?

            traverse(axApp) { element, pressable, text in
                guard pressable, !text.isEmpty else { return true }
                seen.append(text)
                if text.lowercased().contains(needle) {
                    match = element
                    return false // stop traversal
                }
                return true
            }

            if let button = match {
                if dryRun {
                    return AllowOnceResult(pressed: false, message: "Found “\(label)” (dry run).", discoveredLabels: seen)
                }
                let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
                if err == .success {
                    log.info("Pressed “\(self.label, privacy: .public)”.")
                    return AllowOnceResult(pressed: true, message: "Pressed “\(label)”.", discoveredLabels: seen)
                }
                return AllowOnceResult(pressed: false, message: "Found “\(label)” but the press failed (AXError \(err.rawValue)).", discoveredLabels: seen)
            }
        }

        return AllowOnceResult(pressed: false, message: "No “\(label)” button visible right now.", discoveredLabels: seen)
    }

    /// Every pressable label currently exposed by the target app (diagnostics).
    func allPressableLabels() -> [String] {
        guard Permissions.accessibilityTrusted else { return [] }
        var labels: [String] = []
        for app in candidateApps() {
            traverse(appElement(for: app)) { _, pressable, text in
                if pressable, !text.isEmpty { labels.append(text) }
                return true
            }
        }
        return labels
    }

    func targetAppName() -> String? {
        candidateApps().first?.localizedName
    }

    // MARK: App resolution

    private func candidateApps() -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications
        let exact = running.filter { $0.bundleIdentifier == targetBundleID }
        if !exact.isEmpty { return exact }
        // Fall back to any Anthropic app / one literally named "Claude".
        return running.filter {
            ($0.bundleIdentifier ?? "").hasPrefix("com.anthropic.") || $0.localizedName == "Claude"
        }
    }

    private func appElement(for app: NSRunningApplication) -> AXUIElement {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Force Chromium/Electron to build and expose its web accessibility tree.
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return axApp
    }

    // MARK: Tree walking

    /// Depth-first walk. `visit` receives (element, isPressable, label) and returns
    /// false to stop the whole traversal early.
    private func traverse(_ root: AXUIElement, visit: (AXUIElement, Bool, String) -> Bool) {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0

        while let (element, depth) = stack.popLast() {
            visited += 1
            if visited > maxNodes { break }

            let pressable = actionNames(element).contains(kAXPressAction)
            let text = pressable ? combinedLabel(element) : ""
            if !visit(element, pressable, text) { return }

            if depth < maxDepth {
                for child in children(element) {
                    stack.append((child, depth + 1))
                }
            }
        }
    }

    /// A pressable element's own labels plus any nearby static-text descendants —
    /// Electron often puts a button's visible text in a child node.
    private func combinedLabel(_ element: AXUIElement) -> String {
        var parts: [String] = []
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            if let s = stringAttr(element, attr), !s.isEmpty { parts.append(s) }
        }

        var stack: [(AXUIElement, Int)] = children(element).map { ($0, 1) }
        var scanned = 0
        while let (node, depth) = stack.popLast(), scanned < 80 {
            scanned += 1
            if stringAttr(node, kAXRoleAttribute) == "AXStaticText",
               let s = stringAttr(node, kAXValueAttribute) ?? stringAttr(node, kAXTitleAttribute),
               !s.isEmpty {
                parts.append(s)
            }
            if depth < 4 {
                for child in children(node) { stack.append((child, depth + 1)) }
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: AX attribute helpers

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
