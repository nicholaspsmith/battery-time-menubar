// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BatteryTimeCore

final class IdleDriverTests: XCTestCase {
    /// Samples `field` every `dt` from `from` to `to`, and returns the spans
    /// where it is nonzero (start, end), merging gaps shorter than `merge`.
    private func episodes(_ d: inout IdleDriver, from: Double, to: Double, dt: Double = 0.01,
                          merge: Double = 0.2, _ field: (IdlePose) -> Double) -> [(Double, Double)] {
        var spans: [(Double, Double)] = []
        var t = from
        while t <= to {
            if abs(field(d.pose(at: t))) > 1e-12 {
                if let last = spans.last, t - last.1 <= merge { spans[spans.count - 1].1 = t }
                else { spans.append((t, t)) }
            }
            t += dt
        }
        return spans
    }

    func testSameSeedSamePoses() {
        var a = IdleDriver(seed: 7, mood: .awake(tired: false), at: 0)
        var b = IdleDriver(seed: 7, mood: .awake(tired: false), at: 0)
        var c = IdleDriver(seed: 8, mood: .awake(tired: false), at: 0)
        var differs = false
        for i in 0...2400 {
            let t = Double(i) * 0.05
            let pa = a.pose(at: t)
            XCTAssertEqual(pa, b.pose(at: t))
            if pa != c.pose(at: t) { differs = true }
        }
        XCTAssertTrue(differs, "a different seed should give a different timeline")
    }

    func testStartsAtItsMoodsRestingPose() {
        for mood in [IdleMood.awake(tired: false), .awake(tired: true), .drinking, .sleepy] {
            var d = IdleDriver(seed: 1, mood: mood, at: 5)
            XCTAssertEqual(d.pose(at: 5), .resting(mood), "\(mood)")
        }
    }

    func testMoodChangeEasesToTheNewRestingPose() {
        var d = IdleDriver(seed: 3, mood: .awake(tired: false), at: 0)
        _ = d.pose(at: 49.9)
        d.setMood(.sleepy, at: 50)
        let mid = d.pose(at: 50.15)
        XCTAssertGreaterThan(mid.doze, 0); XCTAssertLessThan(mid.doze, 1)
        let after = d.pose(at: 50.31)
        XCTAssertEqual(after.doze, 1); XCTAssertEqual(after.gaze, 0)
        XCTAssertEqual(after.blink, 0); XCTAssertEqual(after.yawn, 0)
    }

    func testTiredLidsEaseIn() {
        var d = IdleDriver(seed: 4, mood: .awake(tired: false), at: 0)
        _ = d.pose(at: 9.9)
        d.setMood(.awake(tired: true), at: 10)
        let mid = d.pose(at: 10.15).tired
        XCTAssertGreaterThan(mid, 0); XCTAssertLessThan(mid, 1)
        XCTAssertEqual(d.pose(at: 10.31).tired, 1)
    }

    func testEveryGlanceComesBackToCentre() {
        var d = IdleDriver(seed: 11, mood: .awake(tired: false), at: 0)
        let glances = episodes(&d, from: 0, to: 300) { $0.gaze }
        XCTAssertGreaterThan(glances.count, 12)
        for (start, end) in glances { XCTAssertLessThanOrEqual(end - start, 3.0 + 0.02) }
    }

    func testBlinksComeEveryFiveToNineSecondsUnlessAYawnHoldsThemBack() {
        var d = IdleDriver(seed: 12, mood: .awake(tired: false), at: 0)
        let blinks = episodes(&d, from: 0, to: 300, dt: 0.005) { $0.blink }
        XCTAssertGreaterThan(blinks.count, 25)
        for (a, b) in zip(blinks, blinks.dropFirst()) {
            let gap = b.0 - a.1
            XCTAssertGreaterThanOrEqual(gap, 4.9)
            XCTAssertLessThanOrEqual(gap, 9.0 + 2.6 + 0.1)   // a yawn (2.6 s) can hold a blink back
        }
    }

    func testAYawnNeverOverlapsAGlanceOrABlink() {
        var d = IdleDriver(seed: 13, mood: .awake(tired: true), at: 0)
        var yawns = 0.0
        var t = 0.0
        while t < 900 {
            let p = d.pose(at: t)
            if p.yawn > 0 { yawns += 1; XCTAssertEqual(p.gaze, 0, "t=\(t)"); XCTAssertEqual(p.blink, 0, "t=\(t)") }
            t += 0.01
        }
        XCTAssertGreaterThan(yawns, 0)
    }

    func testTiredYawnsComeMoreOften() {
        var tired = IdleDriver(seed: 14, mood: .awake(tired: true), at: 0)
        var fresh = IdleDriver(seed: 14, mood: .awake(tired: false), at: 0)
        let t = episodes(&tired, from: 0, to: 3600, dt: 0.05) { $0.yawn }.count
        let f = episodes(&fresh, from: 0, to: 3600, dt: 0.05) { $0.yawn }.count
        XCTAssertGreaterThanOrEqual(t, 35)
        XCTAssertLessThanOrEqual(f, 30)
    }

    func testSleepyMostlyDozes() {
        var d = IdleDriver(seed: 15, mood: .sleepy, at: 0)
        var dozing = 0, total = 0
        var t = 0.0
        while t < 1800 { if d.pose(at: t).doze == 1 { dozing += 1 }; total += 1; t += 0.05 }
        XCTAssertGreaterThanOrEqual(Double(dozing) / Double(total), 0.85)
        var again = IdleDriver(seed: 15, mood: .sleepy, at: 0)
        XCTAssertGreaterThan(episodes(&again, from: 0, to: 600, dt: 0.05) { $0.yawn }.count, 5, "he stirs and yawns")
    }

    func testDrinkingPeeksAndNeverBlinksOrYawns() {
        var d = IdleDriver(seed: 16, mood: .drinking, at: 0)
        var peeks = 0.0, t = 0.0
        while t < 300 {
            let p = d.pose(at: t)
            XCTAssertEqual(p.blink, 0); XCTAssertEqual(p.yawn, 0)
            if p.peek > 0 { peeks += 1 }
            t += 0.02
        }
        XCTAssertGreaterThan(peeks, 0)
    }

    func testTheCueCentresHisGazeAndStartsNothing() {
        var d = IdleDriver(seed: 17, mood: .awake(tired: false), at: 0)
        var t = 0.0
        while abs(d.pose(at: t).gaze) < 1 { t += 0.01; XCTAssertLessThan(t, 120, "no held glance found") }
        d.setCue(playing: true, at: t)
        XCTAssertEqual(d.pose(at: t + 0.25).gaze, 0)
        var u = t + 0.25
        while u < t + 20 {
            let p = d.pose(at: u)
            XCTAssertEqual(p.gaze, 0); XCTAssertEqual(p.blink, 0); XCTAssertEqual(p.yawn, 0)
            u += 0.05
        }
        d.setCue(playing: false, at: t + 20)
        XCTAssertFalse(episodes(&d, from: t + 20, to: t + 30) { $0.blink }.isEmpty, "gestures resume")
    }

    func testNextTickSleepsUntilTheNextGesture() {
        var d = IdleDriver(seed: 18, mood: .awake(tired: false), at: 0)
        XCTAssertEqual(d.pose(at: 0.5), .resting(.awake(tired: false)), "nothing moves between gestures")
        let n = d.nextTick(after: 0.5)
        XCTAssertGreaterThanOrEqual(n, 4.5)   // the first blink is 5 s or more away
        let p = d.pose(at: 0.5 + n + 0.05)
        XCTAssertTrue(p.blink > 0 || p.gaze != 0 || p.breath > 0, "the tick lands on the gesture")
    }

    func testBreathOnlyMovesDuringASigh() {
        var d = IdleDriver(seed: 23, mood: .awake(tired: false), at: 0)
        let sighs = episodes(&d, from: 0, to: 600, dt: 0.02) { $0.breath }
        XCTAssertGreaterThanOrEqual(sighs.count, 6)
        for (start, end) in sighs { XCTAssertLessThanOrEqual(end - start, 3.0 + 0.04) }
    }

    func testOnBatteryHeDrawsAboutOnceASecond() {
        var d = IdleDriver(seed: 24, mood: .awake(tired: false), at: 0)
        var t = 0.0, ticks = 0
        while t < 3600 { _ = d.pose(at: t); t += d.nextTick(after: t); ticks += 1 }
        XCTAssertLessThanOrEqual(Double(ticks) / 3600, 1.2)
    }

    func testARestingTickLandsOneFrameIntoTheNextGesture() {
        var d = IdleDriver(seed: 25, mood: .awake(tired: false), at: 0)
        let n = d.nextTick(after: 0.5)
        var probe = d
        var start = 0.5
        while probe.pose(at: start).blink == 0 && probe.pose(at: start).gaze == 0 && probe.pose(at: start).breath == 0 { start += 0.001 }
        XCTAssertEqual(0.5 + n, start - 0.001 + IdleDriver.movingTick, accuracy: 0.003, "first visible frame, not the gesture's still first instant")
    }

    func testNextTickHurriesMidGestureAndThroughAMoodChange() {
        var d = IdleDriver(seed: 19, mood: .awake(tired: false), at: 0)
        var t = 0.0
        while d.pose(at: t).blink == 0 { t += 0.005 }
        XCTAssertEqual(d.nextTick(after: t), IdleDriver.movingTick)
        d.setMood(.drinking, at: t + 1)
        XCTAssertEqual(d.nextTick(after: t + 1.1), IdleDriver.movingTick)
    }

    func testTickDrivenDrawingNeverMissesAGesture() {
        var dense = IdleDriver(seed: 20, mood: .awake(tired: false), at: 0)
        var ticked = IdleDriver(seed: 20, mood: .awake(tired: false), at: 0)
        let denseBlinks = episodes(&dense, from: 0, to: 600, dt: 0.005, merge: 3.5) { $0.blink }.count
        var dense2 = IdleDriver(seed: 20, mood: .awake(tired: false), at: 0)
        let denseGlances = episodes(&dense2, from: 0, to: 600, dt: 0.005, merge: 3.5) { $0.gaze }.count
        // Merge across gaps up to 3.5 s: a held glance (up to 2.5 s) is drawn once.
        var blinks: [(Double, Double)] = [], glances: [(Double, Double)] = []
        var t = 0.0
        while t <= 600 {
            let p = ticked.pose(at: t)
            for (value, list) in [(p.blink, 0), (p.gaze, 1)] where abs(value) > 1e-12 {
                if list == 0 { if let l = blinks.last, t - l.1 <= 3.5 { blinks[blinks.count - 1].1 = t } else { blinks.append((t, t)) } }
                else { if let l = glances.last, t - l.1 <= 3.5 { glances[glances.count - 1].1 = t } else { glances.append((t, t)) } }
            }
            let step = ticked.nextTick(after: t)
            XCTAssertGreaterThanOrEqual(step, IdleDriver.minimumTick)
            XCTAssertLessThanOrEqual(step, IdleDriver.longestTick)
            t += step
        }
        XCTAssertEqual(blinks.count, denseBlinks)
        XCTAssertEqual(glances.count, denseGlances)
    }

    func testWakingFromALongPauseReplaysNothing() {
        var d = IdleDriver(seed: 21, mood: .awake(tired: false), at: 0)
        var t = 0.0
        while t < 100 { _ = d.pose(at: t); t += 0.05 }
        let woke = d.pose(at: 3700)
        XCTAssertEqual(woke.gaze, 0); XCTAssertEqual(woke.blink, 0); XCTAssertEqual(woke.yawn, 0)
        XCTAssertLessThanOrEqual(episodes(&d, from: 3700, to: 3710, dt: 0.005) { $0.blink }.count, 3)
    }

    func testMoodFlappingStaysInRange() {
        var d = IdleDriver(seed: 22, mood: .awake(tired: false), at: 0)
        var t = 0.0
        var flip = false
        while t < 10 {
            if Int(t * 1000) % 100 == 0 { flip.toggle(); d.setMood(flip ? .drinking : .awake(tired: false), at: t) }
            let p = d.pose(at: t)
            XCTAssertGreaterThanOrEqual(p.gaze, -1); XCTAssertLessThanOrEqual(p.gaze, 1)
            for v in [p.breath, p.blink, p.yawn, p.doze, p.peek, p.tired] { XCTAssertGreaterThanOrEqual(v, 0); XCTAssertLessThanOrEqual(v, 1) }
            let n = d.nextTick(after: t)
            XCTAssertGreaterThanOrEqual(n, IdleDriver.minimumTick); XCTAssertLessThanOrEqual(n, IdleDriver.longestTick)
            t += 0.01
        }
    }

    func testTickDrivenFramesAreAlmostNeverRepeats() {
        // Every redraw costs ~5 ms of CPU, so one that changes nothing is waste.
        for mood in [IdleMood.awake(tired: false), .awake(tired: true), .sleepy, .drinking] {
            var d = IdleDriver(seed: 26, mood: mood, at: 0)
            var t = 0.0, frames = 0, repeats = 0
            var last: IdlePose?
            while t < 3600 {
                let p = d.pose(at: t)
                if p == last { repeats += 1 }
                last = p; frames += 1
                t += d.nextTick(after: t)
            }
            XCTAssertLessThanOrEqual(Double(repeats) / Double(frames), 0.03, "\(mood)")
        }
    }
}
