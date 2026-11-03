// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct Usage24h: Equatable {
    public let batterySeconds: Int
    public let acSeconds: Int
    public let minCharge: Int?
    public let highACSeconds: Int
    public let lowEpisodes: Int

    public init(batterySeconds: Int, acSeconds: Int, minCharge: Int?, highACSeconds: Int, lowEpisodes: Int) {
        self.batterySeconds = batterySeconds
        self.acSeconds = acSeconds
        self.minCharge = minCharge
        self.highACSeconds = highACSeconds
        self.lowEpisodes = lowEpisodes
    }
}

/// Port of the perl in battery-time.5s.sh (lines 31-54). Scans `pmset -g log`
/// for "Using AC"/"Using Batt" events (each with a leading `YYYY-MM-DD HH:MM:SS`
/// timestamp and optional `Charge: N`), builds intervals to the next event (the
/// last runs to `now`), and within the trailing 24h sums battery vs AC seconds,
/// tracks the minimum charge, AC-seconds at charge >= 95%, and the count of
/// distinct dips to <= 20%.
public func parsePmsetLog(_ log: String, now: Date) -> Usage24h {
    let win = now.addingTimeInterval(-86400)

    // timelocal in the perl parses the timestamp as LOCAL time.
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone.current

    struct Event { let date: Date; let isAC: Bool; let charge: Int }
    var events: [Event] = []

    let tsRE = try? NSRegularExpression(pattern: "^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})")
    for rawLine in log.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        // must mention "Using AC" or "Using Batt"
        guard let usingMatch = firstMatch(in: line, pattern: "Using (AC|Batt)") else { continue }
        let isAC = usingMatch == "AC"
        // and have a leading timestamp
        guard let re = tsRE else { continue }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
              let r = Range(m.range(at: 1), in: line) else { continue }
        let tsStr = String(line[r])
        guard let date = fmt.date(from: tsStr) else { continue }
        let charge = firstMatch(in: line, pattern: "Charge:\\s*([0-9]+)").flatMap { Int($0) } ?? -1
        events.append(Event(date: date, isAC: isAC, charge: charge))
    }

    var batterySeconds = 0
    var acSeconds = 0
    var minc = 101
    var hi = 0
    var lo = 0
    var pl = false

    for i in events.indices {
        var st = events[i].date
        var en = (i < events.count - 1) ? events[i + 1].date : now
        if en < win { continue }
        if st < win { st = win }
        if en > now { en = now }
        var d = Int(en.timeIntervalSince(st))
        if d < 0 { d = 0 }
        if events[i].isAC { acSeconds += d } else { batterySeconds += d }
        let c = events[i].charge
        if c >= 0 {
            if c < minc { minc = c }
            if events[i].isAC && c >= 95 { hi += d }
            if c <= 20 && !pl { lo += 1; pl = true }
            else if c > 25 { pl = false }
        }
    }

    let minCharge: Int? = (minc == 101) ? nil : minc
    return Usage24h(batterySeconds: batterySeconds, acSeconds: acSeconds,
                    minCharge: minCharge, highACSeconds: hi, lowEpisodes: lo)
}

/// What a battery tip is about. The raw value keys its seen count.
public enum TipKind: String, CaseIterable {
    case deepDischarge, highCharge, heat, cycles
}

public struct BatteryTip: Equatable {
    public let kind: TipKind
    public let text: String
}

/// Battery-longevity tips (plugin lines 293-307), shown only when a trigger
/// fires. The text has no leading 💡.
public func batteryTipList(usage u: Usage24h, temperatureCentiC: Int?, cycleCount: Int?) -> [BatteryTip] {
    var tips: [BatteryTip] = []
    if let mc = u.minCharge, mc >= 0, (mc <= 15 || u.lowEpisodes >= 2) {
        let ep = u.lowEpisodes >= 2 ? " (\(u.lowEpisodes)× under 20%)" : ""
        tips.append(BatteryTip(kind: .deepDischarge,
                               text: "You dropped to \(mc)% recently\(ep). Recharge before ~20% — deep discharges add wear."))
    }
    if u.highACSeconds >= 28800 {
        tips.append(BatteryTip(kind: .highCharge,
                               text: "Plugged in near full \(u.highACSeconds / 3600)h today. Sitting at high charge ages Li-ion — enable Optimized Charging / 80% limit."))
    }
    if let t = temperatureCentiC, t / 100 >= 35 {
        tips.append(BatteryTip(kind: .heat,
                               text: "Battery is \(t / 100)°C now. Heat is the top cause of aging — improve airflow, ease load while charging."))
    }
    if let c = cycleCount, c >= 800 {
        tips.append(BatteryTip(kind: .cycles,
                               text: "Cycle count \(c) of ~1000 rated — nearing rated life; some capacity loss is expected."))
    }
    return tips
}

/// The tip strings alone.
public func batteryTips(usage u: Usage24h, temperatureCentiC: Int?, cycleCount: Int?) -> [String] {
    batteryTipList(usage: u, temperatureCentiC: temperatureCentiC, cycleCount: cycleCount).map(\.text)
}

/// How many times a tip may be shown before it retires: after the third
/// showing the same advice is noise.
public let tipShowLimit = 3

/// Forgets the seen count of every kind that is not firing now, so a tip
/// whose condition cleared and came back is new again. Call it only when the
/// 24 h usage is known: without it the usage tips look cleared when they are
/// merely not computed yet.
public func pruneSeenTips(_ seen: [String: Int], firing: [BatteryTip]) -> [String: Int] {
    let live = Set(firing.map(\.kind.rawValue))
    return seen.filter { live.contains($0.key) }
}

/// The firing tips not yet shown `tipShowLimit` times.
public func freshTips(_ tips: [BatteryTip], seen: [String: Int]) -> [BatteryTip] {
    tips.filter { seen[$0.kind.rawValue, default: 0] < tipShowLimit }
}

/// `seen` after showing `tips` once more.
public func markTipsShown(_ tips: [BatteryTip], seen: [String: Int]) -> [String: Int] {
    var out = seen
    for t in tips { out[t.kind.rawValue, default: 0] += 1 }
    return out
}
