import Foundation

/// UserDefaults-backed configuration.
final class Settings {
    private enum Key {
        static let seize = "seizeDevice"
        static let bundleID = "targetBundleID"
        static let debounceMs = "debounceMs"
    }

    static let defaultBundleID = "com.anthropic.claudefordesktop"

    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            Key.seize: true,
            Key.bundleID: Settings.defaultBundleID,
            Key.debounceMs: 250,
        ])
    }

    /// Open the pedal exclusively so its own keystroke never reaches the focused app.
    var seize: Bool {
        get { d.bool(forKey: Key.seize) }
        set { d.set(newValue, forKey: Key.seize) }
    }

    /// Bundle identifier of the app holding the prompt.
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
