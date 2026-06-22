import Foundation

/// UserDefaults-backed menu-bar display preferences, replacing the plugin's
/// `set-display.sh` / `set-tempunit.sh` flag files. Defaults mirror the plugin:
/// icon on, percentage off, time on, temperature in °C.
enum DisplayPrefs {
    private static let defaults = UserDefaults.standard

    private static let kShowIcon = "showIcon"
    private static let kShowPct = "showPct"
    private static let kShowTime = "showTime"
    private static let kTempUnit = "tempUnit"

    /// Reads a bool flag that defaults to `fallback` when never set.
    private static func boolOr(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    static var showIcon: Bool {
        get { boolOr(kShowIcon, true) }
        set { defaults.set(newValue, forKey: kShowIcon) }
    }
    static var showPct: Bool {
        get { boolOr(kShowPct, false) }
        set { defaults.set(newValue, forKey: kShowPct) }
    }
    static var showTime: Bool {
        get { boolOr(kShowTime, true) }
        set { defaults.set(newValue, forKey: kShowTime) }
    }

    /// "C" or "F"; defaults to "C".
    static var tempUnit: String {
        get {
            let v = defaults.string(forKey: kTempUnit)
            return v == "F" ? "F" : "C"
        }
        set { defaults.set(newValue == "F" ? "F" : "C", forKey: kTempUnit) }
    }
}
