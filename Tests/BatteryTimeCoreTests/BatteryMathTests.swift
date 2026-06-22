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
