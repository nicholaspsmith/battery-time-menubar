import AppKit
import BatteryTimeCore
import StatusItemKit

// MARK: - Tool paths

private let kPmset = "/usr/bin/pmset"
private let kIoreg = "/usr/sbin/ioreg"
private let kSudo = "/usr/bin/sudo"
private let kOpen = "/usr/bin/open"
private let kSettingsURL = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

// MARK: - Polled snapshot of everything the title + menu need

private struct Snapshot {
    var reading: BatteryReading
    var ioreg: IORegBattery
    var powermode: Int?          // 0 Automatic, 1 Low, 2 High
    var mbTime: String           // menu-bar time string ("1:46", "19h", "--:--", or "")
    var human: String?           // humanized time for the dropdown detail line
    var statusText: String       // "On battery", "Charging", ...
    var usage: Usage24h?
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private var watcher: PowerSourceWatcher!
    private var latest: Snapshot?

    // 24h cache: recomputed off the poll thread, at most every 10 min.
    private var usage24h: Usage24h?
    private var lastUsageComputed: Date?
    private let usageQueue = DispatchQueue(label: "com.nicholaspsmith.BatteryTime.usage")
    private var usageComputing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.poll() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) }
        )
        controller.start()

        // Instant plug/unplug refresh via IOKit power-source notifications,
        // replacing the plugin's power-watch launchd agent.
        watcher = PowerSourceWatcher(onChange: { [weak self] in self?.refreshNow() })
        watcher.start()
    }

    // MARK: Poll

    func refreshNow() { poll() }

    private func poll() {
        let battRaw = Shell.run(kPmset, ["-g", "batt"]) ?? ""
        let ioregRaw = Shell.run(kIoreg, ["-rn", "AppleSmartBattery"]) ?? ""
        let pmRaw = Shell.run(kPmset, ["-g"]) ?? ""

        let reading = parsePmsetBatt(battRaw)
        let ioreg = parseIORegBattery(ioregRaw)
        let powermode = parsePowermode(pmRaw)

        // --- ETA (mirrors plugin 63-121) ---
        var time = ""
        switch reading.state {
        case .discharging:
            if let raw = reading.rawTime {
                // 95% of macOS's estimate (it runs a little optimistic)
                let mins = (hhmmToMinutes(raw) * 95) / 100
                time = minutesToHHMM(mins)
            }
        case .charging:
            if let raw = reading.rawTime { time = raw }
        default:
            break
        }
        // stop-gap right after unplug, before macOS has its own estimate
        if !reading.plugged, time.isEmpty, let rawCur = ioreg.rawCurrentCapacity {
            if let emins = etaStopgapMinutes(rawCurrent: rawCur, voltageMV: ioreg.voltageMV,
                                             instantAmperageRaw: ioreg.instantAmperageRaw) {
                time = minutesToHHMM(emins)
            }
        }

        // humanized for the dropdown
        let human: String? = time.isEmpty ? nil : humanize(time)

        // menu-bar time: plugged -> time (may be empty); else time or "--:--".
        // whole hours render compactly ("19:00" -> "19h").
        var mbTime = reading.plugged ? time : (time.isEmpty ? "--:--" : time)
        if mbTime.hasSuffix(":00") {
            mbTime = String(mbTime.dropLast(3)) + "h"
        }

        let statusText = statusLabel(reading)

        let snap = Snapshot(reading: reading, ioreg: ioreg, powermode: powermode,
                            mbTime: mbTime, human: human, statusText: statusText,
                            usage: usage24h)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.latest = snap
            self.render(snap)
        }
        maybeRecomputeUsage()
    }

    // MARK: Render the status item

    private func render(_ snap: Snapshot) {
        let pct = snap.reading.percent
        let isCharging = snap.reading.state == .charging

        // fill colour (plugin 148-154): mode wins over the low warning.
        let fill: BatteryFill
        if snap.powermode == 2 { fill = .blue }
        else if snap.powermode == 1 { fill = .yellow }
        else if !isCharging, !snap.reading.plugged, let p = pct, p <= 20 { fill = .red }
        else { fill = .none }

        let showIcon = DisplayPrefs.showIcon
        let showPct = DisplayPrefs.showPct
        let showTime = DisplayPrefs.showTime

        let leadTxt = (showPct && pct != nil) ? "\(pct!)%" : ""
        let timeTxt = (showTime && !snap.mbTime.isEmpty) ? snap.mbTime : ""

        // glyph shown when the icon toggle is on and we have a percentage
        let glyph = showIcon && pct != nil

        if glyph {
            // a coloured fill needs a non-template image -> pick ink for the
            // current appearance; a template (fill .none) auto-adapts.
            let ink: NSColor = fill == .none ? .black : appearanceInk()
            let image = BatteryGlyph.image(
                pct: pct!,
                charging: isCharging,
                lead: leadTxt,
                trailing: timeTxt,
                ink: ink,
                fill: fill
            )
            controller.setIcon(image)
        } else {
            // text fallback: % (stands in for the glyph) then time
            var parts: [String] = []
            if let p = pct, showPct || showIcon { parts.append("\(p)%") }
            if showTime, !snap.mbTime.isEmpty { parts.append(snap.mbTime) }
            let text = parts.isEmpty ? "--:--" : parts.joined(separator: " ")
            controller.setTitle(text, warn: false)
        }
    }

    private func appearanceInk() -> NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .white : .black
    }

    // MARK: Build the dropdown

    private func buildMenu(_ menu: NSMenu) {
        guard let snap = latest else {
            menu.addItem(NSMenuItem(title: "…", action: nil, keyEquivalent: ""))
            return
        }
        let plugged = snap.reading.plugged
        let io = snap.ioreg

        // --- Energy Mode selector (first section, plugin 221-238) ---
        let header = NSMenuItem(title: "Energy Mode", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "Energy Mode",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(header)
        let pmSrc = plugged ? "-c" : "-b"
        addModeItem(menu, value: 0, label: "Automatic", current: snap.powermode, src: pmSrc)
        addModeItem(menu, value: 1, label: "Low Power", current: snap.powermode, src: pmSrc)
        addModeItem(menu, value: 2, label: "High Power", current: snap.powermode, src: pmSrc)

        menu.addItem(.separator())

        // --- Battery + detail ---
        let pctStr = snap.reading.percent.map { "\($0)%" } ?? "n/a"
        menu.addItem(NSMenuItem(title: "Battery: \(pctStr)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: detailLine(snap), action: nil, keyEquivalent: ""))

        // Health
        if let h = healthPercent(rawMax: io.rawMaxCapacity, design: io.designCapacity) {
            let cyc = io.cycleCount.map { " (\($0) cycles)" } ?? ""
            menu.addItem(NSMenuItem(title: "Health: \(h)%\(cyc)", action: nil, keyEquivalent: ""))
        }
        // Power (W)
        if let pl = powerLine(snap) {
            menu.addItem(NSMenuItem(title: pl, action: nil, keyEquivalent: ""))
        }
        // Adapter
        if plugged, io.adapterName != nil || io.adapterWatts != nil {
            let name = io.adapterName ?? io.adapterWatts.map { "\($0) W" } ?? ""
            menu.addItem(NSMenuItem(title: "Adapter: \(name)", action: nil, keyEquivalent: ""))
        }
        // extras: temp · V · mAh
        if let extras = extrasLine(snap), !extras.isEmpty {
            menu.addItem(NSMenuItem(title: extras, action: nil, keyEquivalent: ""))
        }
        // temp toggle
        if io.temperatureCentiC != nil {
            let toC = DisplayPrefs.tempUnit == "C"
            let item = NSMenuItem(title: toC ? "Switch to °F" : "Switch to °C",
                                  action: #selector(toggleTempUnit), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        // --- 24h usage ---
        if let usage = snap.usage, let lines = usageLines(usage) {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: lines.0, action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: lines.1, action: nil, keyEquivalent: ""))
        }

        // --- Battery Life Tips (only when a trigger fires) ---
        let tipsUsage = snap.usage ?? Usage24h(batterySeconds: 0, acSeconds: 0,
                                               minCharge: nil, highACSeconds: 0, lowEpisodes: 0)
        let tips = batteryTips(usage: tipsUsage,
                               temperatureCentiC: io.temperatureCentiC,
                               cycleCount: io.cycleCount)
        if !tips.isEmpty {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Battery Life Tips", action: #selector(showTips(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tips
            menu.addItem(item)
        }

        // --- Menu bar shows… (display toggles) ---
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Menu bar shows…", action: nil, keyEquivalent: ""))
        addToggle(menu, title: "Battery icon", on: DisplayPrefs.showIcon, action: #selector(toggleIcon))
        addToggle(menu, title: "Percentage", on: DisplayPrefs.showPct, action: #selector(togglePct))
        addToggle(menu, title: "Time remaining", on: DisplayPrefs.showTime, action: #selector(toggleTime))

        // --- Start at Login ---
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        // --- Open Battery Settings ---
        let settings = NSMenuItem(title: "Open Battery Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        // --- Quit (no target -> standard responder chain) ---
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addModeItem(_ menu: NSMenu, value: Int, label: String, current: Int?, src: String) {
        let item = NSMenuItem(title: label, action: #selector(setPowerMode(_:)), keyEquivalent: "")
        item.target = self
        item.state = (current == value) ? .on : .off
        item.representedObject = [src, String(value)]
        menu.addItem(item)
    }

    private func addToggle(_ menu: NSMenu, title: String, on: Bool, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        menu.addItem(item)
    }

    // MARK: Menu actions

    @objc private func setPowerMode(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        _ = Shell.run(kSudo, [kPmset, pair[0], "powermode", pair[1]])
        poll()
    }

    @objc private func toggleTempUnit() {
        DisplayPrefs.tempUnit = DisplayPrefs.tempUnit == "C" ? "F" : "C"
        poll()
    }

    @objc private func toggleIcon() { DisplayPrefs.showIcon.toggle(); rerender() }
    @objc private func togglePct() { DisplayPrefs.showPct.toggle(); rerender() }
    @objc private func toggleTime() { DisplayPrefs.showTime.toggle(); rerender() }

    private func rerender() { if let s = latest { render(s) } }

    @objc private func toggleLogin() { LoginItem.toggle() }

    @objc private func openSettings() {
        _ = Shell.run(kOpen, [kSettingsURL])
    }

    @objc private func showTips(_ sender: NSMenuItem) {
        guard let tips = sender.representedObject as? [String] else { return }
        let alert = NSAlert()
        alert.messageText = "Battery Life Tips"
        alert.informativeText = tips.map { "💡 \($0)" }.joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: Dropdown helpers

    private func detailLine(_ snap: Snapshot) -> String {
        if snap.reading.plugged {
            if snap.reading.state == .charging {
                if let h = snap.human { return "Charging - \(h) until full" }
                return "Charging"
            }
            return snap.statusText
        } else {
            if let h = snap.human { return "\(h) until empty" }
            return "On battery (estimating...)"
        }
    }

    private func powerLine(_ snap: Snapshot) -> String? {
        let io = snap.ioreg
        guard let v = io.voltageMV, let amp = io.instantAmperageRaw else { return nil }
        let charging = amp.count < 11
        guard let mag = dischargeMagnitude(instantAmperageRaw: amp) else { return nil }
        let watts = Double(v) * Double(mag) / 1_000_000.0
        let w = String(format: "%.1f", watts)
        if snap.reading.plugged, charging {
            return "Charging at \(w) W"
        } else if !snap.reading.plugged {
            return "Using \(w) W"
        }
        return nil
    }

    private func extrasLine(_ snap: Snapshot) -> String? {
        let io = snap.ioreg
        var parts: [String] = []
        if let t = io.temperatureCentiC {
            if DisplayPrefs.tempUnit == "F" {
                parts.append("\(fahrenheit(fromCentiC: t))°F")
            } else {
                parts.append("\(celsius(fromCentiC: t))°C")
            }
        }
        if let v = io.voltageMV {
            parts.append(String(format: "%.1f V", Double(v) / 1000.0))
        }
        if let cur = io.rawCurrentCapacity, let mx = io.rawMaxCapacity {
            parts.append("\(cur) / \(mx) mAh")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func usageLines(_ u: Usage24h) -> (String, String)? {
        let total = u.batterySeconds + u.acSeconds
        guard total > 0 else { return nil }
        let pb = (u.batterySeconds * 100 + total / 2) / total
        let pa = 100 - pb
        let battLine = "24h on battery: \(u.batterySeconds / 3600)h \((u.batterySeconds % 3600) / 60)m (\(pb)%)"
        let acLine = "24h plugged in: \(u.acSeconds / 3600)h \((u.acSeconds % 3600) / 60)m (\(pa)%)"
        return (battLine, acLine)
    }

    // MARK: 24h usage recompute (off the poll thread, <= every 10 min)

    private func maybeRecomputeUsage() {
        let stale: Bool
        if let last = lastUsageComputed {
            stale = Date().timeIntervalSince(last) > 600
        } else {
            stale = true
        }
        guard stale, !usageComputing else { return }
        usageComputing = true
        usageQueue.async { [weak self] in
            let log = Shell.run(kPmset, ["-g", "log"]) ?? ""
            let usage = parsePmsetLog(log, now: Date())
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.usage24h = usage
                self.lastUsageComputed = Date()
                self.usageComputing = false
                if var snap = self.latest {
                    snap.usage = usage
                    self.latest = snap
                }
            }
        }
    }
}

// MARK: - Free helpers

private func statusLabel(_ r: BatteryReading) -> String {
    if r.plugged {
        switch r.state {
        case .notCharging: return "Plugged in (not charging)"
        case .charging: return "Charging"
        case .charged: return "Fully charged"
        default: return "Plugged in"
        }
    }
    return "On battery"
}

private func parsePowermode(_ raw: String) -> Int? {
    // a line like:   powermode            0
    for line in raw.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("powermode") {
            let comps = t.split(separator: " ", omittingEmptySubsequences: true)
            if comps.count >= 2 { return Int(comps[1]) }
        }
    }
    return nil
}

private func hhmmToMinutes(_ hmm: String) -> Int {
    let parts = hmm.split(separator: ":")
    let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
    let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    return h * 60 + m
}

private func minutesToHHMM(_ mins: Int) -> String {
    String(format: "%d:%02d", mins / 60, mins % 60)
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
