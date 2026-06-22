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
