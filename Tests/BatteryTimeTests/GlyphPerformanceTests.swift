// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import AppKit
@testable import BatteryTime

final class GlyphPerformanceTests: XCTestCase {
    /// The idle redraws ~6 times a second on average; each frame must stay
    /// cheap for the energy budget (< 0.5% of a core).
    func testAFrameDrawsInUnderTwoMilliseconds() {
        let frames = 300
        let start = Date()
        for i in 0..<frames {
            let idle = BatteryGlyph.Idle(gaze: sin(Double(i) / 10), breath: cos(Double(i) / 7), blink: i % 30 == 0 ? 1 : 0)
            let img = BatteryGlyph.image(pct: 40 + i % 50, charging: false, lead: "62%", trailing: "1:10", ink: .white,
                                         fill: .none, face: true, age: 0.5, idle: idle)
            _ = rasterize(img, scale: 2)
        }
        let perFrame = Date().timeIntervalSince(start) / Double(frames)
        print("glyph frame: \(String(format: "%.3f", perFrame * 1000)) ms")
        XCTAssertLessThan(perFrame, 0.002)
    }
}
