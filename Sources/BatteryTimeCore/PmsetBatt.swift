import Foundation

public enum PowerState: Equatable { case discharging, charging, charged, notCharging, pluggedOther }

public struct BatteryReading: Equatable {
    public let percent: Int?
    public let plugged: Bool
    public let state: PowerState
    public let rawTime: String?
}

public func parsePmsetBatt(_ raw: String) -> BatteryReading {
    let plugged = raw.contains("'AC Power'")
    let line = raw.split(separator: "\n").first(where: { $0.contains("InternalBattery") }).map(String.init) ?? ""

    let percent = firstMatch(in: line, pattern: "([0-9]+)%").flatMap { Int($0) }

    let state: PowerState
    if line.contains("discharging") { state = .discharging }
    else if line.contains("not charging") { state = .notCharging }
    else if line.contains("charging") { state = .charging }
    else if line.contains("charged") { state = .charged }
    else { state = .pluggedOther }

    var rawTime: String? = nil
    if state == .discharging || state == .charging {
        rawTime = firstMatch(in: line, pattern: "([0-9]{1,2}:[0-9]{2})")
    }
    return BatteryReading(percent: percent, plugged: plugged, state: state, rawTime: rawTime)
}

/// First capture group of `pattern` in `s`, or nil.
func firstMatch(in s: String, pattern: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}
