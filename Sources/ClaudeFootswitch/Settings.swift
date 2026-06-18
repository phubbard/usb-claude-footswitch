import Foundation

/// UserDefaults-backed configuration.
final class Settings {
    private enum Key {
        static let bundleID = "targetBundleID"
        static let debounceMs = "debounceMs"
    }

    static let defaultBundleID = "com.anthropic.claudefordesktop"

    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            Key.bundleID: Settings.defaultBundleID,
            Key.debounceMs: 250,
        ])
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
