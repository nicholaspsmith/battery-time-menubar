// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// What the menu bar shows where the time goes.
public enum TimeDisplay: Equatable {
    /// Nothing to count down: full, held at a charge limit, or no reading.
    case blank
    case minutes(Int)
    /// The spinning clock: a real time isn't ready yet.
    case clock

    /// This display with the clock turned off: our own number in its place,
    /// or nothing if we have none.
    public func withoutClock(own: Int?) -> TimeDisplay {
        guard self == .clock else { return self }
        if let own, own > 0 { return .minutes(own) }
        return .blank
    }
}

/// Our own estimate (minutes) for when macOS has none: time to full while
/// charging, time to empty on battery, nil when neither applies.
public func ownMinutes(_ r: BatteryReading, _ io: IORegBattery) -> Int? {
    if r.state == .charging {
        return chargeMinutes(rawCurrent: io.rawCurrentCapacity, rawMax: io.rawMaxCapacity,
                             instantAmperageRaw: io.instantAmperageRaw)
    }
    guard r.state == .discharging || !r.plugged, let cur = io.rawCurrentCapacity else { return nil }
    return etaStopgapMinutes(rawCurrent: cur, voltageMV: io.voltageMV, instantAmperageRaw: io.instantAmperageRaw)
}

/// Turns each poll into a `TimeDisplay`. A plug or unplug starts the clock,
/// which runs until macOS has a time for the new direction. Away from a plug
/// change there is never a wait: if macOS has no time, our own stands in.
public struct TimeTracker {
    /// How long the clock waits for macOS before our own number takes over.
    public static let macOSLimit: TimeInterval = 180
    /// How long the clock survives "not charging" after plugging in. macOS
    /// says that for a moment before charging starts, and for good at a
    /// charge limit, and the two read the same.
    public static let notChargingGrace: TimeInterval = 15

    private var lastPlugged: Bool?
    /// When the plug last changed, while the clock is still waiting on it.
    private var changedAt: TimeInterval?

    public init() {}

    /// - Parameters:
    ///   - own: `ownMinutes` for this reading.
    ///   - now: Seconds on a clock that doesn't run during sleep, so a long
    ///     sleep doesn't use up the wait.
    public mutating func update(_ r: BatteryReading, own: Int?, at now: TimeInterval) -> TimeDisplay {
        // A failed read says "not plugged in", which isn't an unplug.
        guard r.percent != nil else { return .blank }
        if let last = lastPlugged, last != r.plugged { changedAt = now }
        lastPlugged = r.plugged

        guard r.state == .charging || r.state == .discharging || !r.plugged else {
            if let t = changedAt, r.state != .charged, now - t < Self.notChargingGrace { return .clock }
            changedAt = nil
            return .blank
        }
        if let m = macOSMinutes(r), m > 0 {
            changedAt = nil
            return .minutes(m)
        }
        if let t = changedAt, now - t < Self.macOSLimit { return .clock }
        changedAt = nil
        if let own, own > 0 { return .minutes(own) }
        return .clock
    }

    /// macOS's time: on battery 95% of it, because it runs a little optimistic.
    private func macOSMinutes(_ r: BatteryReading) -> Int? {
        r.rawTime.map { r.state == .discharging ? hhmmToMinutes($0) * 95 / 100 : hhmmToMinutes($0) }
    }
}
