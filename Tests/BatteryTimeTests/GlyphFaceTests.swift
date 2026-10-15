// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import AppKit
@testable import BatteryTime

final class GlyphFaceTests: XCTestCase {
    private let cx: CGFloat = 17

    private func volta(charging: Bool = false, plugged: Bool = false, age: CGFloat = 0,
                       idle: BatteryGlyph.Idle = .still) -> NSImage {
        BatteryGlyph.image(pct: 0, charging: charging, plugged: plugged, lead: "", trailing: "",
                           ink: .black, fill: .none, face: true, age: age, idle: idle)
    }
    private func cy(_ img: NSImage) -> CGFloat { img.size.height / 2 }
    private func interior(_ img: NSImage) -> NSRect { NSRect(x: 3.1, y: cy(img) - 5.4, width: 27.8, height: 10.8) }
    /// The band the eyes sit in, clear of the mouth (and of the straw while charging).
    private func eyeBand(_ img: NSImage, from: CGFloat = 0.3, x: ClosedRange<CGFloat> = 3.1...30.9) -> NSRect {
        NSRect(x: x.lowerBound, y: cy(img) + from, width: x.upperBound - x.lowerBound, height: 3.6 - from)
    }

    func testEyesAreSmallDotsSetWide() {
        let img = volta()
        let left = ink(img, in: eyeBand(img, x: 3.1...cx)), right = ink(img, in: eyeBand(img, x: cx...30.9))
        XCTAssertEqual(right.cx - left.cx, 13.0, accuracy: 0.4)
        for eye in [left, right] { XCTAssertEqual(eye.count, 4.9, accuracy: 0.9) }   // a 2.4 × 2.6 dot
    }

    func testMouthIsWideAndShallow() {
        let img = volta()   // 0% charge: a frown 0.9 deep
        let mouth = ink(img, in: NSRect(x: 3.1, y: cy(img) - 3.0, width: 27.8, height: 3.2))
        XCTAssertEqual(mouth.width, 9.1, accuracy: 0.5)   // 8 across plus round caps
        XCTAssertLessThan(mouth.height, 2.4)
    }

    func testGazeTurnsTheWholeFace() {
        let img = volta()
        let still = ink(img, in: interior(img)).cx
        XCTAssertEqual(ink(volta(idle: .init(gaze: 1)), in: interior(img)).cx - still, 2.0, accuracy: 0.15)
        XCTAssertEqual(ink(volta(idle: .init(gaze: -1)), in: interior(img)).cx - still, -2.0, accuracy: 0.15)
    }

    func testBreathLiftsTheFace() {
        let img = volta()
        XCTAssertEqual(ink(volta(idle: .init(breath: 1)), in: interior(img)).cy - ink(img, in: interior(img)).cy,
                       0.25, accuracy: 0.06)
        let full = volta(plugged: true)
        let band = NSRect(x: cx - 8.5, y: cy(full) - 4.0, width: 17, height: 7.6)   // clear of the glow
        XCTAssertEqual(ink(volta(plugged: true, idle: .init(breath: 1)), in: band).cy - ink(full, in: band).cy,
                       0.35, accuracy: 0.06)
    }

    func testBlinkAndYawnShutTheEyes() {
        let img = volta()
        let open = ink(img, in: eyeBand(img)).height
        XCTAssertLessThan(ink(volta(idle: .init(blink: 1)), in: eyeBand(img)).height, open * 0.7)
        XCTAssertLessThan(ink(volta(idle: .init(yawn: 1)), in: eyeBand(img)).height, open * 0.7)
    }

    func testYawnOpensTheMouthDown() {
        let img = volta()
        let band = NSRect(x: 3.1, y: cy(img) - 6.0, width: 27.8, height: 6.2)
        XCTAssertLessThan(ink(volta(idle: .init(yawn: 1)), in: band).cy, ink(img, in: band).cy - 1.0)
    }

    func testTiredLidsCutTheTopsOffTheDots() {
        let img = volta()
        let open = ink(img, in: eyeBand(img)), tired = ink(volta(idle: .init(tired: 1)), in: eyeBand(img))
        XCTAssertLessThan(tired.height, open.height * 0.8)
        XCTAssertLessThan(tired.count, open.count)
    }

    func testPeekingOpensHisDrinkingEyes() {
        let img = volta(charging: true, plugged: true)
        let band = eyeBand(img, from: 0.9)
        XCTAssertLessThan(ink(volta(charging: true, plugged: true, idle: .init(peek: 1)), in: band).count,
                          ink(img, in: band).count * 0.8)   // dots are less ink than ^ ^
    }

    func testStirringOpensHisSleepyEyes() {
        let img = volta(plugged: true)
        let band = eyeBand(img, x: (cx - 8.5)...(cx + 8.5))
        XCTAssertGreaterThan(ink(volta(plugged: true, idle: .init(doze: 0)), in: band).cy,
                             ink(img, in: band).cy + 0.25)   // dots sit higher than ‿ ‿
    }

    func testTheCasingStaysPutWhenHisFaceTurns() {
        let age = BatteryGlyph.age(health: 60)   // cracked, band-aid, dripping
        let img = volta(age: age)
        let casing = NSRect(x: 2, y: cy(img) - 6, width: 3.5, height: 12)
        XCTAssertEqual(ink(volta(age: age, idle: .init(gaze: 1)), in: casing).count, ink(img, in: casing).count,
                       accuracy: ink(img, in: casing).count * 0.01)
    }
}
