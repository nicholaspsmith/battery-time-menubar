# Battery Time menu-bar app (Swift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the `battery-time.5s.sh` SwiftBar plugin into a standalone Swift menu-bar app (`BatteryTime`, bundle "Battery Time.app") built on StatusItemKit, with all `pmset`/`ioreg`/log parsing in a pure, unit-tested `BatteryTimeCore` library, the battery glyph folded in from `render-title.swift`, and instant plug/unplug via IOKit power-source notifications.

**Architecture:** SwiftPM package at the repo root with three targets: `BatteryTimeCore` (pure parsing/formatting, no AppKit), `BatteryTime` (executable; AppKit + StatusItemKit + BatteryTimeCore), `BatteryTimeCoreTests`. The app polls every 5s via `Shell.run` and also refreshes immediately on AC change via `IOPSNotificationCreateRunLoopSource`. The existing SwiftBar plugin and its `power-watch` launchd agent stay in place (the app replaces the watcher's role with in-process IOKit notifications, but does not remove the plugin's copy).

**Tech Stack:** Swift 5.9, SwiftPM, AppKit, IOKit.ps, StatusItemKit v0.1.0 (local path), macOS 13+.

## Global Constraints

- Work on a feature branch: `git checkout -b swift-app` first. Do **not** modify `battery-time.5s.sh`, `power-watch.sh`, `render-title.swift`, helper scripts, or `test/` — the plugin keeps working until parity. (`render-title.swift` is *ported*, not edited: the new glyph code lives under `Sources/`.)
- Platform floor **macOS 13** (`platforms: [.macOS(.v13)]`).
- StatusItemKit dependency via **local path**: `.package(path: "../StatusItemKit")`.
- Bundle: `CFBundleName` = "Battery Time", `CFBundleExecutable` = `BatteryTime`, `CFBundleIdentifier` = `com.nicholaspsmith.BatteryTime`, `LSUIElement` = true.
- Tool paths: `/usr/bin/pmset`, `/usr/sbin/ioreg`, `/usr/bin/perl`, `/usr/bin/sudo`, `/usr/bin/open`. Energy-mode toggle relies on the existing `/etc/sudoers.d/battery-time-powermode` rule (already installed) — shell out exactly as the plugin does.
- Git: atomic commits per task; messages end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Reference for behavior (read these): `battery-time.5s.sh` — pmset parse 58–92, ioreg 96–101, ETA stopgap 103–121, humanize 123–130, glyph params 132–209, dropdown 211–270, energy mode 221–238, 24h 31–54 & 272–291, tips 293–307, display toggles 329–336. Glyph drawing: `render-title.swift` (whole file). Fixtures: `test/test_battery_time.sh`.

---

### Task 1: Package skeleton + `parsePmsetBatt`

**Files:**
- Create: `Package.swift`
- Create: `Sources/BatteryTimeCore/PmsetBatt.swift`
- Test: `Tests/BatteryTimeCoreTests/PmsetBattTests.swift`

**Interfaces:**
- Produces:
  - `enum PowerState: Equatable { case discharging, charging, charged, notCharging, pluggedOther }`
  - `struct BatteryReading: Equatable { let percent: Int?; let plugged: Bool; let state: PowerState; let rawTime: String? }`
  - `func parsePmsetBatt(_ raw: String) -> BatteryReading`
- Rules (plugin 58–92): `plugged` = output contains `'AC Power'`. From the `InternalBattery` line: `percent` = the `NN%` integer; `state` from the status word (`discharging`→.discharging, `charging`→.charging, `charged`→.charged, `not charging`→.notCharging, else .pluggedOther); `rawTime` = the `H:MM` token, but only when charging or discharging (else nil).

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BatteryTime",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BatteryTime", targets: ["BatteryTime"]),
        .library(name: "BatteryTimeCore", targets: ["BatteryTimeCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
    ],
    targets: [
        .target(name: "BatteryTimeCore"),
        .executableTarget(
            name: "BatteryTime",
            dependencies: ["BatteryTimeCore", .product(name: "StatusItemKit", package: "StatusItemKit")]
        ),
        .testTarget(name: "BatteryTimeCoreTests", dependencies: ["BatteryTimeCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing test** `Tests/BatteryTimeCoreTests/PmsetBattTests.swift`

```swift
import XCTest
@testable import BatteryTimeCore

final class PmsetBattTests: XCTestCase {
    func testDischarging() {
        let raw = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=12345)\t82%; discharging; 3:14 remaining present: true
        """
        let r = parsePmsetBatt(raw)
        XCTAssertEqual(r.percent, 82)
        XCTAssertFalse(r.plugged)
        XCTAssertEqual(r.state, .discharging)
        XCTAssertEqual(r.rawTime, "3:14")
    }
    func testCharging() {
        let raw = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t45%; charging; 1:20 remaining present: true
        """
        let r = parsePmsetBatt(raw)
        XCTAssertEqual(r.percent, 45)
        XCTAssertTrue(r.plugged)
        XCTAssertEqual(r.state, .charging)
        XCTAssertEqual(r.rawTime, "1:20")
    }
    func testChargedHasNoTime() {
        let raw = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t100%; charged; 0:00 remaining present: true
        """
        let r = parsePmsetBatt(raw)
        XCTAssertEqual(r.percent, 100)
        XCTAssertTrue(r.plugged)
        XCTAssertEqual(r.state, .charged)
        XCTAssertNil(r.rawTime)
    }
    func testNotCharging() {
        let raw = " -InternalBattery-0\t77%; not charging; 0:00 remaining present: true\nNow drawing from 'AC Power'"
        let r = parsePmsetBatt(raw)
        XCTAssertEqual(r.state, .notCharging)
        XCTAssertNil(r.rawTime)
    }
}
```

- [ ] **Step 3: Run, verify fail** — `swift test --filter PmsetBattTests` → FAIL.

- [ ] **Step 4: Implement `Sources/BatteryTimeCore/PmsetBatt.swift`**

```swift
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
```

- [ ] **Step 5: Run, verify pass** — PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/BatteryTimeCore/PmsetBatt.swift Tests/BatteryTimeCoreTests/PmsetBattTests.swift
git commit -m "feat: package skeleton + pmset -g batt parsing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `parseIORegBattery`

**Files:**
- Create: `Sources/BatteryTimeCore/IORegBattery.swift`
- Test: `Tests/BatteryTimeCoreTests/IORegBatteryTests.swift`

**Interfaces:**
- Produces:
  - `struct IORegBattery: Equatable { let cycleCount, designCapacity, rawMaxCapacity, rawCurrentCapacity, voltageMV, temperatureCentiC: Int?; let instantAmperageRaw: String?; let adapterName: String?; let adapterWatts: Int? }`
  - `func parseIORegBattery(_ raw: String) -> IORegBattery`
- Rules (plugin 96–101): integer keys parsed from lines like `"CycleCount" = 123` (value may be negative). Keys: `CycleCount`, `DesignCapacity`, `AppleRawMaxCapacity`, `AppleRawCurrentCapacity`, `Voltage`, `Temperature`. **`InstantAmperage` is kept as the raw digit String** (`instantAmperageRaw`) — on discharge it's an unsigned 64-bit value (~1.8e19) that overflows `Int`; Task 3 reparses it via `UInt64`. `AdapterDetails` is a nested dict; pull `Name` (`"Name"="X"`) and `Watts` (`"Watts"=NN`) from wherever they appear.

- [ ] **Step 1: Write the failing test** `Tests/BatteryTimeCoreTests/IORegBatteryTests.swift`

```swift
import XCTest
@testable import BatteryTimeCore

final class IORegBatteryTests: XCTestCase {
    // Trimmed, representative ioreg -rn AppleSmartBattery output.
    let fixture = """
      | {
        "CycleCount" = 142
        "DesignCapacity" = 4382
        "AppleRawMaxCapacity" = 4100
        "AppleRawCurrentCapacity" = 3000
        "Voltage" = 12600
        "InstantAmperage" = 18446744073709550000
        "Temperature" = 3012
        "AdapterDetails" = {"Watts"=96,"Name"="96W USB-C Power Adapter","Description"="usb"}
      | }
    """

    func testIntegerFields() {
        let b = parseIORegBattery(fixture)
        XCTAssertEqual(b.cycleCount, 142)
        XCTAssertEqual(b.designCapacity, 4382)
        XCTAssertEqual(b.rawMaxCapacity, 4100)
        XCTAssertEqual(b.rawCurrentCapacity, 3000)
        XCTAssertEqual(b.voltageMV, 12600)
        XCTAssertEqual(b.temperatureCentiC, 3012)
    }
    func testAdapter() {
        let b = parseIORegBattery(fixture)
        XCTAssertEqual(b.adapterName, "96W USB-C Power Adapter")
        XCTAssertEqual(b.adapterWatts, 96)
    }
    func testEmpty() {
        let b = parseIORegBattery("-")
        XCTAssertNil(b.cycleCount)
        XCTAssertNil(b.adapterName)
    }
}
```

- [ ] **Step 2: Run, verify fail** → FAIL.

- [ ] **Step 3: Implement `Sources/BatteryTimeCore/IORegBattery.swift`**

```swift
import Foundation

public struct IORegBattery: Equatable {
    public let cycleCount: Int?
    public let designCapacity: Int?
    public let rawMaxCapacity: Int?
    public let rawCurrentCapacity: Int?
    public let voltageMV: Int?
    public let temperatureCentiC: Int?
    public let instantAmperageRaw: String?   // raw digits; overflows Int on discharge
    public let adapterName: String?
    public let adapterWatts: Int?
}

public func parseIORegBattery(_ raw: String) -> IORegBattery {
    func intVal(_ key: String) -> Int? {
        // matches:  "Key" = 123   or   "Key" = -123
        firstMatch(in: raw, pattern: "\"\(key)\"\\s*=\\s*(-?[0-9]+)").flatMap { Int($0) }
    }
    let name = firstMatch(in: raw, pattern: "\"AdapterDetails\"[\\s\\S]*?\"Name\"\\s*=\\s*\"([^\"]*)\"")
        ?? firstMatch(in: raw, pattern: "\"Name\"\\s*=\\s*\"([^\"]*)\"")
    let watts = (firstMatch(in: raw, pattern: "\"Watts\"\\s*=\\s*([0-9]+)")).flatMap { Int($0) }

    return IORegBattery(
        cycleCount: intVal("CycleCount"),
        designCapacity: intVal("DesignCapacity"),
        rawMaxCapacity: intVal("AppleRawMaxCapacity"),
        rawCurrentCapacity: intVal("AppleRawCurrentCapacity"),
        voltageMV: intVal("Voltage"),
        temperatureCentiC: intVal("Temperature"),
        instantAmperageRaw: firstMatch(in: raw, pattern: "\"InstantAmperage\"\\s*=\\s*(-?[0-9]+)"),
        adapterName: name,
        adapterWatts: watts
    )
}
```

- [ ] **Step 4: Run, verify pass** — `testIntegerFields`/`testAdapter`/`testEmpty` PASS. (Optionally assert `b.instantAmperageRaw == "18446744073709550000"`.)

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryTimeCore/IORegBattery.swift Tests/BatteryTimeCoreTests/IORegBatteryTests.swift
git commit -m "feat: ioreg AppleSmartBattery parsing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Derived computations (health, humanize, temp, ETA stopgap)

**Files:**
- Create: `Sources/BatteryTimeCore/BatteryMath.swift`
- Test: `Tests/BatteryTimeCoreTests/BatteryMathTests.swift`

**Interfaces:**
- Produces:
  - `func healthPercent(rawMax: Int?, design: Int?) -> Int?` — `min(100, rawMax*100/design)` (plugin 241–244).
  - `func humanize(_ hmm: String) -> String` — "H:MM" → "X hr Y min" / "X hr" / "Y min" (plugin 123–130).
  - `func celsius(fromCentiC: Int) -> Int` and `func fahrenheit(fromCentiC: Int) -> Int` (plugin 256–262).
  - `func dischargeMagnitude(instantAmperageRaw: String) -> Int?` — two's-complement of the unsigned 64-bit value (`2^64 - x` when `x` has ≥11 digits), else the value (plugin 112–114, 247).
  - `func etaStopgapMinutes(rawCurrent: Int, voltageMV: Int?, instantAmperageRaw: String?) -> Int?` — measured-draw projection capped by a nominal ~12 W (plugin 103–121). Returns nil when no estimate is possible.

- [ ] **Step 1: Write the failing test** `Tests/BatteryTimeCoreTests/BatteryMathTests.swift`

```swift
import XCTest
@testable import BatteryTimeCore

final class BatteryMathTests: XCTestCase {
    func testHealth() {
        XCTAssertEqual(healthPercent(rawMax: 4100, design: 4382), 93)
        XCTAssertEqual(healthPercent(rawMax: 5000, design: 4382), 100)  // capped
        XCTAssertNil(healthPercent(rawMax: nil, design: 4382))
        XCTAssertNil(healthPercent(rawMax: 4100, design: 0))
    }
    func testHumanize() {
        XCTAssertEqual(humanize("3:14"), "3 hr 14 min")
        XCTAssertEqual(humanize("2:00"), "2 hr")
        XCTAssertEqual(humanize("0:42"), "42 min")
    }
    func testTemp() {
        XCTAssertEqual(celsius(fromCentiC: 3012), 30)
        XCTAssertEqual(fahrenheit(fromCentiC: 3012), 86)
    }
    func testDischargeMagnitude() {
        // -1500 mA encoded as unsigned 64-bit
        XCTAssertEqual(dischargeMagnitude(instantAmperageRaw: "18446744073709550116"), 1500)
        XCTAssertEqual(dischargeMagnitude(instantAmperageRaw: "1500"), 1500)  // charging (positive)
    }
    func testEtaStopgapCappedByNominal() {
        // huge rawCurrent + tiny draw -> capped by ~12W nominal, not 20h+
        let mins = etaStopgapMinutes(rawCurrent: 4000, voltageMV: 12000, instantAmperageRaw: "18446744073709551516")
        XCTAssertNotNil(mins)
        XCTAssertLessThanOrEqual(mins!, 4000 * 60 / (12000000 / 12000))  // <= nominal projection
    }
}
```

- [ ] **Step 2: Run, verify fail** → FAIL.

- [ ] **Step 3: Implement `Sources/BatteryTimeCore/BatteryMath.swift`**

```swift
import Foundation

public func healthPercent(rawMax: Int?, design: Int?) -> Int? {
    guard let m = rawMax, let d = design, d > 0 else { return nil }
    return min(100, m * 100 / d)
}

public func humanize(_ hmm: String) -> String {
    let parts = hmm.split(separator: ":")
    let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
    let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    if h > 0 && m > 0 { return "\(h) hr \(m) min" }
    if h > 0 { return "\(h) hr" }
    return "\(m) min"
}

public func celsius(fromCentiC c: Int) -> Int { c / 100 }
public func fahrenheit(fromCentiC c: Int) -> Int { (c / 100) * 9 / 5 + 32 }

/// Magnitude (mA) of InstantAmperage. Discharge is a large unsigned value
/// (two's complement of a negative); >= 11 digits means negative.
public func dischargeMagnitude(instantAmperageRaw raw: String) -> Int? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    if s.count >= 11, let u = UInt64(s) {
        let mag = UInt64(18446744073709551615) - u + 1   // 2^64 - u
        return Int(mag)
    }
    return Int(s)
}

/// Stop-gap ETA (minutes) right after unplug, before macOS has its own estimate:
/// measured-draw projection capped by a nominal ~12 W. nil if no estimate.
public func etaStopgapMinutes(rawCurrent: Int, voltageMV: Int?, instantAmperageRaw: String?) -> Int? {
    var nominal: Int? = nil
    if let v = voltageMV, v > 0 { nominal = rawCurrent * 60 / (12_000_000 / v) }  // ~12 W cap
    var measured: Int? = nil
    if let raw = instantAmperageRaw, let mag = dischargeMagnitude(instantAmperageRaw: raw), mag > 0 {
        measured = rawCurrent * 60 / mag
    }
    switch (measured, nominal) {
    case let (m?, n?): return min(m, n)
    case let (m?, nil): return m
    case let (nil, n?): return n
    default: return nil
    }
}
```

- [ ] **Step 4: Run, verify pass** — PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryTimeCore/BatteryMath.swift Tests/BatteryTimeCoreTests/BatteryMathTests.swift
git commit -m "feat: battery math (health, humanize, temp, ETA stopgap)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: 24-hour usage parse + tips triggers

**Files:**
- Create: `Sources/BatteryTimeCore/Usage24h.swift`
- Test: `Tests/BatteryTimeCoreTests/Usage24hTests.swift`

**Interfaces:**
- Produces:
  - `struct Usage24h: Equatable { let batterySeconds, acSeconds: Int; let minCharge: Int?; let highACSeconds: Int; let lowEpisodes: Int }`
  - `func parsePmsetLog(_ log: String, now: Date) -> Usage24h` — port of the perl in plugin 31–54. Parse lines matching `Using (AC|Batt)` with a leading `YYYY-MM-DD HH:MM:SS` timestamp and optional `Charge: N`; build intervals to the next event (last runs to `now`); within the trailing 24h sum battery vs AC seconds, track min charge, AC-seconds-at-charge≥95%, and count of distinct dips ≤20%.
  - `func batteryTips(usage: Usage24h, temperatureCentiC: Int?, cycleCount: Int?) -> [String]` — the trigger rules (plugin 293–307); returns the tip strings (without the 💡 prefix).

- [ ] **Step 1: Write the failing test** `Tests/BatteryTimeCoreTests/Usage24hTests.swift`

```swift
import XCTest
@testable import BatteryTimeCore

final class Usage24hTests: XCTestCase {
    // now = 2026-06-22 12:00:00 local. Two intervals inside the window.
    private func date(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)!
    }
    func testSplitsBatteryVsAC() {
        let now = date("2026-06-22 12:00:00")
        let log = """
        2026-06-22 10:00:00 Using Batt (Charge: 80)
        2026-06-22 11:00:00 Using AC (Charge: 60)
        """
        // 10:00->11:00 on battery = 3600s; 11:00->now(12:00) on AC = 3600s
        let u = parsePmsetLog(log, now: now)
        XCTAssertEqual(u.batterySeconds, 3600)
        XCTAssertEqual(u.acSeconds, 3600)
        XCTAssertEqual(u.minCharge, 60)
    }
    func testTipsLowDischargeAndCycles() {
        let u = Usage24h(batterySeconds: 0, acSeconds: 0, minCharge: 12, highACSeconds: 0, lowEpisodes: 1)
        let tips = batteryTips(usage: u, temperatureCentiC: nil, cycleCount: 850)
        XCTAssertTrue(tips.contains { $0.contains("12%") })          // deep-discharge tip
        XCTAssertTrue(tips.contains { $0.contains("Cycle count 850") }) // cycle tip
    }
}
```

- [ ] **Step 2: Run, verify fail** → FAIL.

- [ ] **Step 3: Implement `Sources/BatteryTimeCore/Usage24h.swift`** — port the perl: regex-scan each line for the timestamp + `Using (AC|Batt)` + optional `Charge: N`; collect `(date, isAC, charge)` events in order; for each event, the interval runs to the next event's date (or `now` for the last); clip intervals to `[now-86400, now]`; accumulate `batterySeconds`/`acSeconds`; track `minCharge` (min over events with charge≥0), `highACSeconds` (AC intervals where charge≥95), and `lowEpisodes` (count of transitions into ≤20% that weren't already counted, reset above 25%). Then:

```swift
public func batteryTips(usage u: Usage24h, temperatureCentiC: Int?, cycleCount: Int?) -> [String] {
    var tips: [String] = []
    if let mc = u.minCharge, mc >= 0, (mc <= 15 || u.lowEpisodes >= 2) {
        let ep = u.lowEpisodes >= 2 ? " (\(u.lowEpisodes)× under 20%)" : ""
        tips.append("You dropped to \(mc)% recently\(ep). Recharge before ~20% — deep discharges add wear.")
    }
    if u.highACSeconds >= 28800 {
        tips.append("Plugged in near full \(u.highACSeconds / 3600)h today. Sitting at high charge ages Li-ion — enable Optimized Charging / 80% limit.")
    }
    if let t = temperatureCentiC, t / 100 >= 35 {
        tips.append("Battery is \(t / 100)°C now. Heat is the top cause of aging — improve airflow, ease load while charging.")
    }
    if let c = cycleCount, c >= 800 {
        tips.append("Cycle count \(c) of ~1000 rated — nearing rated life; some capacity loss is expected.")
    }
    return tips
}
```

(Implement `parsePmsetLog` above `batteryTips` in the same file; use `firstMatch` from Task 1 and a POSIX `DateFormatter` with `en_US_POSIX`.)

- [ ] **Step 4: Run, verify pass** — PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryTimeCore/Usage24h.swift Tests/BatteryTimeCoreTests/Usage24hTests.swift
git commit -m "feat: 24h usage parse + battery tips triggers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Battery glyph (port of render-title.swift) — build + visual verify

**Files:**
- Create: `Sources/BatteryTime/BatteryGlyph.swift`

**Interfaces:**
- Produces: `enum BatteryGlyph { static func image(pct: Int, charging: Bool, lead: String, trailing: String, ink: NSColor, fill: BatteryFill) -> NSImage }` and `enum BatteryFill { case none, yellow, blue, red }`.
- This is a direct port of `render-title.swift`'s drawing into an `NSImage` (drop the base64/PNG round-trip). `fill == .none` → `isTemplate = true` (adapts light/dark); a colored fill → `isTemplate = false`. Same metrics: bodyW 26, bodyH 13, nub, radius 3.2, lineW 1.2, fillInset 1.3, gap 4, the bolt-cutout knockout, lead text left + trailing text right.

- [ ] **Step 1: Implement `Sources/BatteryTime/BatteryGlyph.swift`** — port `render-title.swift` lines 40–138 into a function returning `NSImage(size:flipped:)` whose drawing handler runs the same composition (lead text, `drawBattery`, trailing text). Map `--fill` to `BatteryFill`; set `image.isTemplate = (fill == .none)`. Keep `boltPath`/`knockout` exactly. (No CLI arg parsing — parameters come in directly.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles (the executable target now has `BatteryGlyph` + the placeholder main from Task 6 — if main.swift doesn't exist yet, add a 1-line `import StatusItemKit` placeholder so the target builds, replaced in Task 6).

- [ ] **Step 3: Commit**

```bash
git add Sources/BatteryTime/BatteryGlyph.swift
git commit -m "feat: battery glyph image (ported from render-title.swift)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: App target — status item, full dropdown, polling (build + manual verify)

**Files:**
- Create: `Sources/BatteryTime/main.swift`
- Create: `Sources/BatteryTime/DisplayPrefs.swift` (UserDefaults-backed icon/pct/time + temp unit)
- Create: `Resources/Info.plist`
- Create: `scripts/build-app.sh`

**Interfaces:**
- Consumes: all of `BatteryTimeCore`, `BatteryGlyph`, `StatusItemKit` (`Shell`, `StatusItemController`, `LoginItem`).

- [ ] **Step 1: Write `Resources/Info.plist`** (CFBundleExecutable `BatteryTime`, CFBundleName "Battery Time", id `com.nicholaspsmith.BatteryTime`, LSUIElement true, LSMinimumSystemVersion 13.0).

- [ ] **Step 2: Write `scripts/build-app.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh BatteryTime "Battery Time"
```
Then `chmod +x scripts/build-app.sh`.

- [ ] **Step 3: Write `Sources/BatteryTime/DisplayPrefs.swift`** — UserDefaults wrappers replacing the plugin's `set-display.sh`/`set-tempunit.sh` files: `showIcon`/`showPct`/`showTime` (defaults 1/0/1) and `tempUnit` ("C"/"F"), each get/set.

- [ ] **Step 4: Write `Sources/BatteryTime/main.swift`** — the app:
  - Poll (5s) via `StatusItemController.onPoll`: run `pmset -g batt`, `ioreg -rn AppleSmartBattery`, `pmset -g` (powermode); parse with Core; compute the title (lead `pct%`, glyph `pct`/charging/fill-color from powermode/low per plugin 145–154, trailing `mb_time` with whole-hours `Nh` per plugin 142–143; ETA stopgap when discharging w/ no time per plugin 108–121); call `controller.setIcon(BatteryGlyph.image(...))` (or `setTitle` text fallback if `showIcon` off and only text). Respect `DisplayPrefs`.
  - Build menu (`onBuildMenu`) mirroring plugin 211–339: Energy Mode header + Automatic/Low/High (checkmark current; action shells `sudo pmset -b|-c powermode N`), "Battery: NN%", detail line, Health, Power (W), Adapter, extras (temp·V·mAh), temp toggle, 24h usage (two lines), Battery Life Tips (NSAlert with the tip text) when non-empty, "Menu bar shows…" submenu with icon/pct/time checkable toggles, Start at Login, "Open Battery Settings…" (`open x-apple.systempreferences:com.apple.Battery-Settings.extension`), Quit. Menu-action items get `target = self`; Quit does not.
  - 24h cache: keep `Usage24h?` in memory; recompute by running `perl` over `pmset -g log` on a background queue, refreshed at most every 10 min (track last-compute time); never block the poll. (You may instead call the plugin's perl one-liner via `Shell.run("/usr/bin/perl", ...)`, or call `parsePmsetLog` directly on the `pmset -g log` text — prefer `parsePmsetLog`.)

- [ ] **Step 5: Build the app bundle**

Run: `./scripts/build-app.sh`
Expected: `Built build/Battery Time.app`.

- [ ] **Step 6: Run the Core tests** — `swift test` → all PASS.

- [ ] **Step 7: Manual verification**

Run: `open "build/Battery Time.app"`. Verify: a battery glyph with % and time shows in the menu bar; fill turns yellow in Low Power, blue in High Power, red when ≤20% on battery; the bolt appears while charging; the dropdown shows energy mode (current checkmarked, switching works without a password prompt), stats, temp toggle, 24h usage, tips when triggered, the display toggles change the bar, Start at Login, Open Battery Settings, Quit. Then `pkill -x BatteryTime`.

- [ ] **Step 8: Commit**

```bash
git add Sources/BatteryTime/main.swift Sources/BatteryTime/DisplayPrefs.swift Resources/Info.plist scripts/build-app.sh
git commit -m "feat: BatteryTime app (status glyph, full dropdown, polling)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Instant plug/unplug via IOKit power-source notifications

**Files:**
- Create: `Sources/BatteryTime/PowerSourceWatcher.swift`
- Modify: `Sources/BatteryTime/main.swift` (start the watcher; refresh on callback)

**Interfaces:**
- Produces: `final class PowerSourceWatcher { init(onChange: @escaping () -> Void); func start() }` using `IOPSNotificationCreateRunLoopSource`.

- [ ] **Step 1: Implement `Sources/BatteryTime/PowerSourceWatcher.swift`**

```swift
import Foundation
import IOKit.ps

/// Fires `onChange` on the main run loop whenever the power source changes
/// (AC plug/unplug), replacing the plugin's pmset -g pslog launchd watcher.
public final class PowerSourceWatcher {
    private let onChange: () -> Void
    private var source: CFRunLoopSource?

    public init(onChange: @escaping () -> Void) { self.onChange = onChange }

    public func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let me = Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue()
            me.onChange()
        }, ctx)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }
}
```

- [ ] **Step 2: Wire it in `main.swift`** — in `applicationDidFinishLaunching`, after `controller.start()`, create `PowerSourceWatcher(onChange: { [weak self] in self?.refreshNow() })` and `start()` it, where `refreshNow()` re-runs the poll body immediately. Hold a strong reference on the app object.

- [ ] **Step 3: Build + verify**

Run: `./scripts/build-app.sh && open "build/Battery Time.app"`
Verify the menu-bar time/glyph updates **immediately** on plugging/unplugging the charger (not after the 5s tick). Then `pkill -x BatteryTime`.

- [ ] **Step 4: Commit**

```bash
git add Sources/BatteryTime/PowerSourceWatcher.swift Sources/BatteryTime/main.swift
git commit -m "feat: instant plug/unplug via IOKit power-source notifications

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: README note + .gitignore

**Files:**
- Modify: `README.md` (add "Standalone Swift app" section)
- Create/Modify: `.gitignore` (`.build/`, `build/`, `*.app`, `.swiftpm/`)

- [ ] **Step 1: Append to `README.md`**: the repo now also ships a standalone Swift app (`BatteryTime`) built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit); build with `./scripts/build-app.sh`, `open "build/Battery Time.app"`. It replaces the `power-watch` launchd agent with in-process IOKit notifications and uses the existing passwordless-sudo rule for the energy-mode toggle. The SwiftBar plugin remains available.

- [ ] **Step 2: Ensure `.gitignore`** contains `.build/`, `build/`, `*.app`, `.swiftpm/`.

- [ ] **Step 3: Commit**

```bash
git add README.md .gitignore
git commit -m "docs: note the standalone Swift app

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-review checklist (run before reporting done)

- `swift test` green (PmsetBatt, IORegBattery, BatteryMath, Usage24h); `./scripts/build-app.sh` produces `build/Battery Time.app`.
- Plugin (`battery-time.5s.sh`), `render-title.swift`, `power-watch.sh`, helper scripts, and `test/` untouched (`git status` shows only new Swift files + README/.gitignore).
- All work on the `swift-app` branch.
- Energy-mode toggle works without a password prompt (relies on the pre-installed sudoers rule).
