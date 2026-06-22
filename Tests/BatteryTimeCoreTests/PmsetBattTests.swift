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
