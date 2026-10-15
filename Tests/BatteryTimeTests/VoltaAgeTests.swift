// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BatteryTime

final class VoltaAgeTests: XCTestCase {
    func testNewDownTo92Point5() {
        XCTAssertEqual(BatteryGlyph.age(health: 100), 0)
        XCTAssertEqual(BatteryGlyph.age(health: 92.6), 0)
        XCTAssertEqual(BatteryGlyph.age(health: 92.5), 0)
    }
    func testAgesJustBelow92Point5() {
        let a = BatteryGlyph.age(health: 92.4)
        XCTAssertGreaterThan(a, 0)
        XCTAssertLessThan(a, 0.01)
    }
    func testHalfwayBetween92Point5And40() {
        XCTAssertEqual(BatteryGlyph.age(health: 66.25), 0.5, accuracy: 0.0001)
    }
    func testWreckedAt40AndBelow() {
        XCTAssertEqual(BatteryGlyph.age(health: 40), 1)
        XCTAssertEqual(BatteryGlyph.age(health: 0), 1)
    }
    func testUnknownHealthLooksNew() {
        XCTAssertEqual(BatteryGlyph.age(health: nil), 0)
    }
}
