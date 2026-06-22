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
