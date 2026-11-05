// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import AppKit
@testable import BatteryTime

final class ClockGlyphTests: XCTestCase {
    private func glyph(trailing: String = "", clock: CGFloat? = nil) -> NSImage {
        BatteryGlyph.image(pct: 50, charging: false, lead: "", trailing: trailing, ink: .white,
                           fill: .none, face: true, clock: clock)
    }

    /// The square the clock is drawn in: the right-hand end of the glyph.
    private func clockRect(_ img: NSImage) -> NSRect {
        let s = BatteryGlyph.clockSize
        return NSRect(x: img.size.width - s, y: (img.size.height - s) / 2, width: s, height: s)
    }

    func testTheClockTakesTheSlotRightOfTheBattery() {
        XCTAssertEqual(glyph(clock: 0).size.width, ceil(glyph().size.width + 4 + BatteryGlyph.clockSize))
    }

    func testTheClockIsDrawnAtDigitHeight() {
        let img = glyph(clock: 0)
        let found = ink(img, in: clockRect(img))
        XCTAssertEqual(BatteryGlyph.clockSize, 11)
        XCTAssertEqual(found.height, 11, accuracy: 1)
        XCTAssertEqual(found.width, 11, accuracy: 1)
    }

    func testTheClockReplacesAnyTimeText() {
        XCTAssertEqual(glyph(trailing: "4:23", clock: 0).size.width, glyph(clock: 0).size.width)
    }

    func testTheMinuteHandGoesRoundOncePerTurn() {
        let right = glyph(clock: 0.25), left = glyph(clock: 0.75)
        XCTAssertGreaterThan(ink(right, in: clockRect(right)).cx, ink(left, in: clockRect(left)).cx)
    }

    func testTheHourHandTakesTwelveTurns() {
        // Turn 3 and turn 9: the minute hand sits at 12 for both, so only the
        // hour hand differs, at 3 and at 9.
        let three = glyph(clock: 3), nine = glyph(clock: 9)
        XCTAssertGreaterThan(ink(three, in: clockRect(three)).cx, ink(nine, in: clockRect(nine)).cx)
    }

    func testTheStillClockReadsTenPastTen() {
        let turns = BatteryGlyph.stillClockTurns
        XCTAssertEqual(turns.truncatingRemainder(dividingBy: 1) * 60, 10, accuracy: 0.001)
        XCTAssertEqual(floor(turns), 10)
    }

    func testTheTextFallbackKeepsItsLeadBesideTheClock() {
        let bare = BatteryGlyph.clockImage(lead: "", turns: 0, ink: .white)
        let led = BatteryGlyph.clockImage(lead: "62%", turns: 0, ink: .white)
        XCTAssertEqual(bare.size.width, BatteryGlyph.clockSize)
        XCTAssertGreaterThan(led.size.width, bare.size.width + 4)
        XCTAssertTrue(led.isTemplate)
        XCTAssertGreaterThan(ink(led, in: clockRect(led)).count, 0)
    }

    func testAClockFrameDrawsInUnderTwoMilliseconds() {
        let frames = 300
        let start = Date()
        for i in 0..<frames {
            _ = rasterize(glyph(clock: CGFloat(i) / 24), scale: 2)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start) / Double(frames), 0.002)
    }
}
