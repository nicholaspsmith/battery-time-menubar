// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit
import SwiftUI

/// Battery Time's Preferences window (menu ▸ Preferences…, ⌘,): what the menu
/// bar shows, Volta's idle, the temperature unit and Start at Login. It
/// replaced the Settings submenu, as Mac Daddy's and Panes's windows did.
final class PreferencesModel: ObservableObject {
    @Published var showIcon = DisplayPrefs.showIcon { didSet { DisplayPrefs.showIcon = showIcon; onChange() } }
    @Published var showFace = DisplayPrefs.showFace { didSet { DisplayPrefs.showFace = showFace; onChange() } }
    @Published var showPct = DisplayPrefs.showPct { didSet { DisplayPrefs.showPct = showPct; onChange() } }
    @Published var showTime = DisplayPrefs.showTime { didSet { DisplayPrefs.showTime = showTime; onChange() } }
    @Published var animateFace = DisplayPrefs.animateFace { didSet { DisplayPrefs.animateFace = animateFace; onChange() } }
    @Published var tempUnit = DisplayPrefs.tempUnit { didSet { DisplayPrefs.tempUnit = tempUnit; onChange() } }
    @Published var loginEnabled = LoginItem.isEnabled

    /// Redraws the menu-bar item after any change.
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Re-reads Start at Login, which System Settings can change behind our back.
    func refresh() { loginEnabled = LoginItem.isEnabled }

    func setLogin(_ on: Bool) {
        LoginItem.set(on)
        loginEnabled = LoginItem.isEnabled
    }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Form {
            Section("Menu Bar Shows") {
                Toggle("Battery icon", isOn: $model.showIcon)
                Toggle("Battery face", isOn: $model.showFace).disabled(!model.showIcon)
                Toggle("Percentage", isOn: $model.showPct)
                Toggle("Time remaining", isOn: $model.showTime)
            }
            Section {
                Toggle("Animate Volta", isOn: $model.animateFace).disabled(!model.showIcon || !model.showFace)
            } footer: {
                Text("Off, Volta still sips while charging and does his twice-a-minute turn; only his idle glances, blinks and yawns stop.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("General") {
                Picker("Temperature", selection: $model.tempUnit) {
                    Text("°C").tag("C")
                    Text("°F").tag("F")
                }
                .pickerStyle(.segmented)
                Toggle("Start at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            }
            Section {
                Text("Version \(AppVersion.string)").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.vertical, 8)
    }
}

final class PreferencesWindowController {
    private var window: NSWindow?
    let model: PreferencesModel

    init(model: PreferencesModel) { self.model = model }

    func show() {
        model.refresh()
        if window == nil {
            let hosting = NSHostingController(rootView: PreferencesView(model: model))
            // NSWindow(contentViewController:) doesn't size itself to a hosted
            // SwiftUI view on its own; without this it opens as a title bar.
            hosting.sizingOptions = [.preferredContentSize]
            let w = EscClosableWindow(contentViewController: hosting)
            w.title = "Battery Time Preferences"
            w.styleMask.remove(.resizable)
            w.isReleasedWhenClosed = false
            window = w
            w.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Esc closes the window, as in Mac Daddy's Preferences.
private final class EscClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    // With no text field first responder, Esc arrives as a plain keyDown.
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad])
        if event.keyCode == 53 && mods.isEmpty {
            performClose(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    // ⌘W closes it too; an accessory app has no main menu to supply it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
