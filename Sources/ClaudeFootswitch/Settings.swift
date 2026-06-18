import Foundation

/// UserDefaults-backed configuration.
final class Settings {
    private enum Key {
        static let seize = "seizeDevice"
        static let label = "allowOnceLabel"
        static let bundleID = "targetBundleID"
        static let debounceMs = "debounceMs"
    }

    static let defaultBundleID = "com.anthropic.claudefordesktop"
    static let defaultLabel = "Allow once"

    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            Key.seize: true,
            Key.label: Settings.defaultLabel,
            Key.bundleID: Settings.defaultBundleID,
            Key.debounceMs: 250,
        ])
    }

    /// Open the pedal exclusively so its own keystroke never reaches the focused app.
    var seize: Bool {
        get { d.bool(forKey: Key.seize) }
        set { d.set(newValue, forKey: Key.seize) }
    }

    /// The button label to look for in the target app (case-insensitive substring match).
    var label: String {
        get { d.string(forKey: Key.label) ?? Settings.defaultLabel }
        set { d.set(newValue, forKey: Key.label) }
    }

    /// Bundle identifier of the app holding the button.
    var bundleID: String {
        get { d.string(forKey: Key.bundleID) ?? Settings.defaultBundleID }
        set { d.set(newValue, forKey: Key.bundleID) }
    }

    /// Minimum gap between two accepted presses.
    var debounceMs: Int {
        get { max(0, d.integer(forKey: Key.debounceMs)) }
        set { d.set(newValue, forKey: Key.debounceMs) }
    }
}
