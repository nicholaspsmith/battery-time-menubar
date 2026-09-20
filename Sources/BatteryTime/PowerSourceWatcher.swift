// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import IOKit.ps

/// Fires `onChange` on the main run loop whenever the power source changes
/// (AC plug/unplug), replacing the plugin's pmset -g pslog launchd watcher.
public final class PowerSourceWatcher {
    private let onChange: () -> Void
    private var source: CFRunLoopSource?

    public init(onChange: @escaping () -> Void) { self.onChange = onChange }

    public func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let me = Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue()
            me.onChange()
        }, ctx)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }
}
