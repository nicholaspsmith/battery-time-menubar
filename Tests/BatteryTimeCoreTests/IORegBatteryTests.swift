// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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
    func testInstantAmperageRawKept() {
        let b = parseIORegBattery(fixture)
        XCTAssertEqual(b.instantAmperageRaw, "18446744073709550000")
    }
    // Newer macOS has no AppleRaw capacity keys; BatteryData carries them.
    func testBatteryDataCapacities() {
        let raw = """
          | {
            "CycleCount" = 73
            "BatteryData" = {"FullChargeCapacity"=8464,"NominalChargeCapacity"=8708,"RemainingCapacity"=6675,"DesignCapacity"=8579,"TrueRemainingCapacity"=0}
          | }
        """
        let b = parseIORegBattery(raw)
        XCTAssertEqual(b.designCapacity, 8579)
        XCTAssertEqual(b.rawMaxCapacity, 8708)
        XCTAssertEqual(b.rawCurrentCapacity, 6675)
        XCTAssertEqual(healthPercent(rawMax: b.rawMaxCapacity, design: b.designCapacity), 100)
    }
}
