// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BatteryTimeCore

final class VoltaMotionTests: XCTestCase {
    func testMoodFollowsThePowerState() {
        XCTAssertEqual(idleMood(charging: true, plugged: true, pct: 50), .drinking)
        XCTAssertEqual(idleMood(charging: false, plugged: true, pct: 100), .sleepy)
        XCTAssertEqual(idleMood(charging: false, plugged: false, pct: 21), .awake(tired: false))
        XCTAssertEqual(idleMood(charging: false, plugged: false, pct: 20), .awake(tired: true))
    }

    func testNothingMovesWhenHeCantBeSeen() {
        XCTAssertTrue(voltaMayMove(faceShown: true, reduceMotion: false, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(voltaMayMove(faceShown: false, reduceMotion: false, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(voltaMayMove(faceShown: true, reduceMotion: false, displayAsleep: true, sessionActive: true))
        XCTAssertFalse(voltaMayMove(faceShown: true, reduceMotion: false, displayAsleep: false, sessionActive: false))
        XCTAssertNil(animationDelay(idleTick: nil, drinking: false))
    }

    func testReduceMotionStillsHim() {
        XCTAssertFalse(voltaMayMove(faceShown: true, reduceMotion: true, displayAsleep: false, sessionActive: true))
    }

    func testSipLoopRunsWithoutTheIdle() {
        XCTAssertEqual(animationDelay(idleTick: nil, drinking: true), 1.0 / 12)
    }

    func testTheSoonerOfIdleAndSipWins() {
        XCTAssertEqual(animationDelay(idleTick: 0.25, drinking: false), 0.25)
        XCTAssertEqual(animationDelay(idleTick: 0.25, drinking: true), 1.0 / 12)
        XCTAssertEqual(animationDelay(idleTick: 1.0 / 15, drinking: true), 1.0 / 15)
    }

    func testTimersFireNearlyOnTime() {
        // macOS fires a timer at the far end of its tolerance, and a blink lasts 0.18 s.
        XCTAssertEqual(timerTolerance(for: 4.6), 0.01)
        XCTAssertEqual(timerTolerance(for: 0.05), 0.005, accuracy: 1e-12)
    }

    func testTheMinuteCueWaitsForSomeoneToSeeIt() {
        XCTAssertTrue(minuteCueMayPlay(faceShown: true, iconShown: true, charging: false, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(minuteCueMayPlay(faceShown: true, iconShown: true, charging: false, displayAsleep: true, sessionActive: true))
        XCTAssertFalse(minuteCueMayPlay(faceShown: true, iconShown: true, charging: false, displayAsleep: false, sessionActive: false))
        XCTAssertFalse(minuteCueMayPlay(faceShown: true, iconShown: true, charging: true, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(minuteCueMayPlay(faceShown: false, iconShown: true, charging: false, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(minuteCueMayPlay(faceShown: true, iconShown: false, charging: false, displayAsleep: false, sessionActive: true))
    }
}
