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
}
