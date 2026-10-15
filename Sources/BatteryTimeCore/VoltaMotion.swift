// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Volta's idle mood for a reading: charging → drinking; plugged in and not
/// charging → sleepy; on battery → awake, tired at 20% and below.
public func idleMood(charging: Bool, plugged: Bool, pct: Int) -> IdleMood {
    if charging { return .drinking }
    if plugged { return .sleepy }
    return .awake(tired: pct <= 20)
}

/// Whether Volta may move at all: his face is showing, Reduce Motion is off,
/// and someone could be looking (display awake, session active).
public func voltaMayMove(faceShown: Bool, reduceMotion: Bool, displayAsleep: Bool, sessionActive: Bool) -> Bool {
    faceShown && !reduceMotion && !displayAsleep && sessionActive
}

/// How long until Volta next needs drawing: the idle's next tick (nil when
/// the idle is off) or, while he drinks, the sip loop's 1/12 s, whichever is
/// sooner. Nil when nothing moves.
public func animationDelay(idleTick: TimeInterval?, drinking: Bool) -> TimeInterval? {
    [idleTick, drinking ? 1.0 / 12 : nil].compactMap { $0 }.min()
}
