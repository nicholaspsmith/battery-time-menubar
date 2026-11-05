// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BatteryTimeCore

final class TimeEstimateTests: XCTestCase {
    private func reading(_ state: PowerState, plugged: Bool, time: String? = nil, percent: Int? = 50) -> BatteryReading {
        BatteryReading(percent: percent, plugged: plugged, state: state, rawTime: time)
    }
    private let onBattery: (String?) -> BatteryReading = { time in
        BatteryReading(percent: 50, plugged: false, state: .discharging, rawTime: time)
    }
    private let charging: (String?) -> BatteryReading = { time in
        BatteryReading(percent: 50, plugged: true, state: .charging, rawTime: time)
    }

    // MARK: Tracking a plug or unplug

    func testUnplugShowsTheClockEvenWhenAnOwnEstimateExists() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(onBattery(nil), own: 120, at: 1), .clock)
    }

    func testPlugInShowsTheClockEvenWhenAnOwnEstimateExists() {
        var t = TimeTracker()
        _ = t.update(onBattery("2:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(charging(nil), own: 90, at: 1), .clock)
    }

    func testTheClockEndsWithMacOSsFirstEstimate() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        _ = t.update(onBattery(nil), own: nil, at: 1)
        XCTAssertEqual(t.update(onBattery("4:00"), own: nil, at: 40), .minutes(228))  // 95% of 240
    }

    func testOnceMacOSHasAnsweredLosingItsEstimateShowsTheOwnNumberNotTheClock() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        _ = t.update(onBattery(nil), own: nil, at: 1)
        _ = t.update(onBattery("4:00"), own: nil, at: 40)
        XCTAssertEqual(t.update(onBattery(nil), own: 120, at: 45), .minutes(120))
    }

    func testAfterThreeMinutesWithoutMacOSTheOwnNumberTakesOver() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(onBattery(nil), own: 120, at: 10), .clock)
        XCTAssertEqual(t.update(onBattery(nil), own: 120, at: 189), .clock)
        XCTAssertEqual(t.update(onBattery(nil), own: 120, at: 190), .minutes(120))
    }

    func testTheClockStaysWhenThereIsNothingToCalculateFrom() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(onBattery(nil), own: nil, at: 500), .clock)
    }

    func testAZeroEstimateFromMacOSIsNoEstimate() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(onBattery("0:00"), own: 120, at: 1), .clock)
    }

    // MARK: No plug change

    func testLaunchWithoutAnEstimateShowsTheOwnNumber() {
        var t = TimeTracker()
        XCTAssertEqual(t.update(onBattery(nil), own: 120, at: 0), .minutes(120))
    }

    func testLaunchWithNothingToCalculateFromShowsTheClock() {
        var t = TimeTracker()
        XCTAssertEqual(t.update(onBattery(nil), own: nil, at: 0), .clock)
    }

    func testChargingTimeIsMacOSsUnscaled() {
        var t = TimeTracker()
        XCTAssertEqual(t.update(charging("1:20"), own: nil, at: 0), .minutes(80))
    }

    // MARK: Plugged in with nothing to count down

    func testFullIsBlank() {
        var t = TimeTracker()
        XCTAssertEqual(t.update(reading(.charged, plugged: true), own: nil, at: 0), .blank)
    }

    func testHeldAtALimitIsBlank() {
        var t = TimeTracker()
        XCTAssertEqual(t.update(reading(.notCharging, plugged: true), own: nil, at: 0), .blank)
    }

    func testPlugInShowsTheClockThroughMacOSsBriefNotCharging() {
        var t = TimeTracker()
        _ = t.update(onBattery("2:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(reading(.notCharging, plugged: true), own: nil, at: 1), .clock)
        XCTAssertEqual(t.update(charging(nil), own: 90, at: 5), .clock)
    }

    func testPlugInAtAChargeLimitGoesBlankAfterTheGrace() {
        var t = TimeTracker()
        _ = t.update(onBattery("2:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(reading(.notCharging, plugged: true), own: nil, at: 1), .clock)
        XCTAssertEqual(t.update(reading(.notCharging, plugged: true), own: nil, at: 15), .clock)
        XCTAssertEqual(t.update(reading(.notCharging, plugged: true), own: nil, at: 16), .blank)
    }

    func testPluggingInWhenFullIsBlankAtOnce() {
        var t = TimeTracker()
        _ = t.update(onBattery("2:00"), own: nil, at: 0)
        XCTAssertEqual(t.update(reading(.charged, plugged: true), own: nil, at: 1), .blank)
    }

    // MARK: A failed reading

    func testAFailedReadingIsBlankAndIsNotAnUnplug() {
        var t = TimeTracker()
        _ = t.update(charging("1:00"), own: nil, at: 0)
        let failed = BatteryReading(percent: nil, plugged: false, state: .pluggedOther, rawTime: nil)
        XCTAssertEqual(t.update(failed, own: nil, at: 5), .blank)
        XCTAssertEqual(t.update(charging("1:00"), own: nil, at: 10), .minutes(60))
    }

    // MARK: With the clock turned off

    func testWithoutTheClockOurOwnNumberStandsIn() {
        XCTAssertEqual(TimeDisplay.clock.withoutClock(own: 120), .minutes(120))
    }

    func testWithoutTheClockOrANumberTheSpotIsBlank() {
        XCTAssertEqual(TimeDisplay.clock.withoutClock(own: nil), .blank)
        XCTAssertEqual(TimeDisplay.clock.withoutClock(own: 0), .blank)
    }

    func testTurningTheClockOffLeavesOtherDisplaysAlone() {
        XCTAssertEqual(TimeDisplay.minutes(60).withoutClock(own: 120), .minutes(60))
        XCTAssertEqual(TimeDisplay.blank.withoutClock(own: 120), .blank)
    }

    // MARK: Our own numbers

    func testChargeMinutes() {
        // 1,000 mAh to go at 2,000 mA is half an hour.
        XCTAssertEqual(chargeMinutes(rawCurrent: 3000, rawMax: 4000, instantAmperageRaw: "2000"), 30)
    }

    func testChargeMinutesWithoutACharge() {
        XCTAssertNil(chargeMinutes(rawCurrent: 3000, rawMax: 4000, instantAmperageRaw: "0"))
        XCTAssertNil(chargeMinutes(rawCurrent: 3000, rawMax: 4000, instantAmperageRaw: nil))
        XCTAssertNil(chargeMinutes(rawCurrent: 3000, rawMax: nil, instantAmperageRaw: "2000"))
    }

    func testChargeMinutesWhileTheBatteryIsDraining() {
        XCTAssertNil(chargeMinutes(rawCurrent: 3000, rawMax: 4000, instantAmperageRaw: "18446744073709550616"))
    }

    func testOwnMinutesPicksTheDirection() {
        let io = IORegBattery(cycleCount: nil, designCapacity: nil, rawMaxCapacity: 4000, rawCurrentCapacity: 3000,
                              voltageMV: 12000, temperatureCentiC: nil, instantAmperageRaw: "2000",
                              adapterName: nil, adapterWatts: nil)
        XCTAssertEqual(ownMinutes(charging(nil), io), 30)
        // 3,000 mAh at 2,000 mA is 90 min; the ~12 W cap is 180.
        XCTAssertEqual(ownMinutes(onBattery(nil), io), 90)
        XCTAssertNil(ownMinutes(reading(.charged, plugged: true), io))
    }

    func testFinishingChargeCountsAsCharging() {
        let raw = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t99%; finishing charge; 0:14 remaining present: true
        """
        let r = parsePmsetBatt(raw)
        XCTAssertEqual(r.state, .charging)
        XCTAssertEqual(r.rawTime, "0:14")
    }
}
