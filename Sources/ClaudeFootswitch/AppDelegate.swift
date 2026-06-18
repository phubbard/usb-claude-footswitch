import AppKit
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "App")
    private let settings = Settings()
    private let hid = HIDFootswitch()
    private let allowOnce = AllowOnce()

    private var statusItem: NSStatusItem!

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        allowOnce.targetBundleID = settings.bundleID
        allowOnce.label = settings.label

        hid.debounceInterval = Double(settings.debounceMs) / 1000.0
        hid.onPress = { [weak self] in self?.handlePress() }
        hid.onConnectionChange = { [weak self] _ in self?.updateIcon() }

        setupStatusItem()
        updateIcon()

        promptForMissingPermissions()
        startHID()
    }

    // MARK: Status item & menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "shoeprints.fill", accessibilityDescription: "Claude Footswitch") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "🦶"
        }
        button.alphaValue = hid.isConnected ? 1.0 : 0.4
        button.toolTip = hid.isConnected ? "Foot pedal connected" : "Foot pedal not found"
    }

    /// Rebuilt every time the menu opens, so state is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled("Claude Footswitch"))
        menu.addItem(disabled(hid.isConnected ? "  ● Pedal connected" : "  ○ Pedal not found"))
        let appName = allowOnce.targetAppName() ?? settings.bundleID
        menu.addItem(disabled("  → \(appName)"))
        menu.addItem(.separator())

        menu.addItem(action("Press “\(settings.label)” now", #selector(testPress)))

        let seizeItem = action("Suppress pedal’s own keystroke", #selector(toggleSeize))
        seizeItem.state = settings.seize ? .on : .off
        menu.addItem(seizeItem)
        menu.addItem(.separator())

        menu.addItem(disabled("Permissions"))
        menu.addItem(action("  Input Monitoring: \(mark(Permissions.inputMonitoringGranted))", #selector(fixInputMonitoring)))
        menu.addItem(action("  Accessibility: \(mark(Permissions.accessibilityTrusted))", #selector(fixAccessibility)))
        menu.addItem(.separator())

        let diagnostics = NSMenu()
        let logItem = action("Log pedal events to Console", #selector(toggleLogging))
        logItem.state = hid.logEvents ? .on : .off
        diagnostics.addItem(logItem)
        diagnostics.addItem(action("Show Claude’s buttons…", #selector(showButtons)))
        let diagnosticsItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        diagnosticsItem.submenu = diagnostics
        menu.addItem(diagnosticsItem)

        let loginItem = action("Launch at login", #selector(toggleLaunchAtLogin))
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(action("Quit", #selector(quit)))
    }

    // MARK: Pedal → button

    private func handlePress() {
        let result = allowOnce.press()
        log.info("Press → \(result.message, privacy: .public)")
        flash(success: result.pressed)
    }

    @objc private func testPress() {
        let result = allowOnce.press()
        flash(success: result.pressed)
        guard !result.pressed else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn’t press “\(settings.label)”"
        var info = result.message
        if !result.discoveredLabels.isEmpty {
            info += "\n\nButtons currently visible:\n• " + result.discoveredLabels.prefix(20).joined(separator: "\n• ")
        }
        alert.informativeText = info
        runModal(alert)
    }

    // MARK: Menu actions

    @objc private func toggleSeize() {
        settings.seize.toggle()
        hid.start(seize: settings.seize)
    }

    @objc private func toggleLogging() {
        hid.logEvents.toggle()
    }

    @objc private func showButtons() {
        let labels = allowOnce.allPressableLabels()
        log.info("Visible buttons: \(labels.joined(separator: " | "), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Buttons Claude is exposing"
        alert.informativeText = labels.isEmpty
            ? "None found.\n\nMake sure a Claude permission prompt is on screen, Claude is running, and Accessibility is granted to this app."
            : "• " + labels.joined(separator: "\n• ")
        runModal(alert)
    }

    @objc private func fixInputMonitoring() {
        Permissions.requestInputMonitoring()
        Permissions.openInputMonitoringSettings()
    }

    @objc private func fixAccessibility() {
        Permissions.accessibilityTrusted(prompt: true)
        Permissions.openAccessibilitySettings()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Login-item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private var launchAtLoginEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    private func startHID() {
        if !Permissions.inputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }
        hid.start(seize: settings.seize)
    }

    private func promptForMissingPermissions() {
        let ax = Permissions.accessibilityTrusted
        let im = Permissions.inputMonitoringGranted
        guard !(ax && im) else { return }

        if !ax { Permissions.accessibilityTrusted(prompt: true) }
        if !im { Permissions.requestInputMonitoring() }

        let alert = NSAlert()
        alert.messageText = "Two permissions needed"
        alert.informativeText = """
        Claude Footswitch needs:

        • Input Monitoring — to read the foot pedal\(im ? " ✓" : "")
        • Accessibility — to press Claude’s “\(settings.label)” button\(ax ? " ✓" : "")

        Enable them under System Settings ▸ Privacy & Security, then relaunch this app.
        """
        alert.addButton(withTitle: "Open Input Monitoring")
        alert.addButton(withTitle: "Open Accessibility")
        alert.addButton(withTitle: "Later")
        switch runModal(alert) {
        case .alertFirstButtonReturn: Permissions.openInputMonitoringSettings()
        case .alertSecondButtonReturn: Permissions.openAccessibilitySettings()
        default: break
        }
    }

    private func flash(success: Bool) {
        guard let button = statusItem.button else { return }
        button.contentTintColor = success ? .systemGreen : .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak button] in
            button?.contentTintColor = nil
        }
    }

    @discardableResult
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func mark(_ ok: Bool) -> String { ok ? "✓" : "✕ — click to fix" }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }
}
