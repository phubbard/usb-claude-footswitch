import AppKit
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let log = Logger(subsystem: "net.phfactor.ClaudeFootswitch", category: "App")
    private let settings = Settings()
    private let hid = HIDFootswitch()
    private let allowOnce = AllowOnce()
    private let suppressor = KeyboardSuppressor()

    private var statusItem: NSStatusItem!
    private var permWatch: Timer?
    private var hidStarted = false
    private var suppressorStarted = false
    private var didShowLaunchGuidance = false
    private var imGrantedAtLaunch = false

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        allowOnce.targetBundleID = settings.bundleID
        imGrantedAtLaunch = Permissions.inputMonitoringGranted
        Diag.log("=== launch: accessibility=\(Permissions.accessibilityTrusted) inputMonitoring=\(imGrantedAtLaunch) ===")

        hid.debounceInterval = Double(settings.debounceMs) / 1000.0
        hid.onPress = { [weak self] in
            self?.suppressor.arm() // drop the pedal's stray Return before it lands
            self?.handlePress()
        }
        hid.onConnectionChange = { [weak self] _ in self?.updateIcon() }

        setupStatusItem()
        updateIcon()

        // React quickly when the user toggles Accessibility in System Settings.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(recheckPermissions),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)

        evaluatePermissions(promptIfMissing: true)
    }

    // MARK: Permissions

    /// Checks live state. Starts everything if granted; otherwise requests what's missing
    /// (once) and watches for the grant so we recover without re-nagging.
    private func evaluatePermissions(promptIfMissing: Bool) {
        let ax = Permissions.accessibilityTrusted
        let im = Permissions.inputMonitoringGranted
        if ax { startSuppressorIfNeeded() }

        if ax && im {
            stopPermWatch()
            if imGrantedAtLaunch {
                startHIDIfNeeded()
            } else {
                // Input Monitoring was granted while running. IOHIDManager only starts
                // receiving events in a process that had the grant at launch, so relaunch.
                log.notice("Input Monitoring granted at runtime — relaunching to read the pedal.")
                Diag.log("Input Monitoring granted at runtime → relaunching")
                relaunchApp()
            }
            updateIcon()
            return
        }

        if promptIfMissing {
            if !ax { Permissions.accessibilityTrusted(prompt: true) }
            if !im { Permissions.requestInputMonitoring() }
            if !didShowLaunchGuidance {
                didShowLaunchGuidance = true
                showPermissionGuidance(ax: ax, im: im)
            }
        }
        startPermWatch()
        updateIcon()
    }

    @objc private func recheckPermissions() {
        evaluatePermissions(promptIfMissing: false)
    }

    private func startPermWatch() {
        guard permWatch == nil else { return }
        permWatch = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.evaluatePermissions(promptIfMissing: false)
        }
    }

    private func stopPermWatch() {
        permWatch?.invalidate()
        permWatch = nil
    }

    private func startHIDIfNeeded() {
        if hidStarted { return }
        guard Permissions.inputMonitoringGranted else {
            Diag.log("startHID skipped: Input Monitoring not granted")
            return
        }
        Diag.log("startHID: opening device")
        hid.start()
        hidStarted = true
    }

    private func startSuppressorIfNeeded() {
        guard !suppressorStarted, Permissions.accessibilityTrusted else { return }
        suppressor.start()
        suppressorStarted = suppressor.isRunning
    }

    private func showPermissionGuidance(ax: Bool, im: Bool) {
        let alert = NSAlert()
        alert.messageText = "Two permissions needed"
        alert.informativeText = """
        Claude Footswitch needs:

        • Input Monitoring — to read the foot pedal\(im ? "  ✓ granted" : "")
        • Accessibility — to send ⌘↩ to Claude\(ax ? "  ✓ granted" : "")

        Enable the missing one(s) in System Settings ▸ Privacy & Security. The app picks \
        up the change automatically — no need to relaunch in most cases.
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

    // MARK: Pedal → approve

    private func handlePress() {
        let result = allowOnce.approve()
        log.info("Press → \(result.message, privacy: .public)")
        Diag.log("approve: success=\(result.success) — \(result.message)")
        flash(success: result.success)
    }

    @objc private func testApprove() {
        let result = allowOnce.approve()
        flash(success: result.success)
        guard !result.success else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn’t send ⌘↩"
        alert.informativeText = result.message
        runModal(alert)
    }

    // MARK: Status item & menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        if let image = NSImage(systemSymbolName: "shoeprints.fill", accessibilityDescription: "Claude Footswitch") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "🦶"
        }
        let ready = hid.isConnected && Permissions.accessibilityTrusted && Permissions.inputMonitoringGranted
        button.alphaValue = ready ? 1.0 : 0.4
        button.toolTip = statusSummary()
    }

    private func statusSummary() -> String {
        if !Permissions.inputMonitoringGranted || !Permissions.accessibilityTrusted {
            return "Permissions needed — open the menu"
        }
        return hid.isConnected ? "Ready — stomp to approve" : "Foot pedal not found"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ax = Permissions.accessibilityTrusted
        let im = Permissions.inputMonitoringGranted

        menu.addItem(disabled("Claude Footswitch"))
        menu.addItem(disabled(hid.isConnected ? "  ● Pedal connected" : "  ○ Pedal not found"))
        menu.addItem(disabled("  → \(allowOnce.targetAppName() ?? settings.bundleID)"))
        menu.addItem(.separator())

        menu.addItem(action("Approve Claude (send ⌘↩) now", #selector(testApprove)))
        let suppressItem = action("Suppress pedal’s own Return", #selector(toggleSuppress))
        suppressItem.state = suppressor.enabled ? .on : .off
        if !suppressor.isRunning { suppressItem.toolTip = "Needs Accessibility permission" }
        menu.addItem(suppressItem)
        menu.addItem(.separator())

        menu.addItem(disabled("Permissions"))
        menu.addItem(action("  Input Monitoring: \(mark(im))", #selector(fixInputMonitoring)))
        menu.addItem(action("  Accessibility: \(mark(ax))", #selector(fixAccessibility)))
        if !(ax && im) {
            menu.addItem(action("  Relaunch (if a grant isn’t detected)", #selector(relaunchApp)))
        }
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

    // MARK: Menu actions

    @objc private func toggleLogging() { hid.logEvents.toggle() }

    @objc private func toggleSuppress() { suppressor.enabled.toggle() }

    @objc private func showButtons() {
        let labels = allowOnce.allPressableLabels()
        let alert = NSAlert()
        alert.messageText = "Buttons Claude exposes to Accessibility"
        alert.informativeText = labels.isEmpty
            ? "None found — which is expected: Claude's prompt is web content that doesn't expose AX buttons. That's why this app sends ⌘↩ instead of pressing a button."
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

    @objc private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
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

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Helpers

    private var launchAtLoginEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    private func flash(success: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = success ? "checkmark.circle.fill" : "xmark.octagon.fill"
        let color: NSColor = success ? .systemGreen : .systemRed
        if let image = coloredSymbol(symbol, color) {
            button.image = image
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.updateIcon()
        }
    }

    /// A solidly tinted (non-template) menu-bar glyph — same fill trick as the app icon,
    /// which renders reliably where contentTintColor / paletteColors did not.
    private func coloredSymbol(_ name: String, _ color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let image = NSImage(size: base.size)
        image.lockFocus()
        base.draw(at: .zero, from: NSRect(origin: .zero, size: base.size), operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
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
