// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit
import SwiftUI

/// Battery Time's Preferences window (menu ▸ Preferences…, ⌘,), on
/// StatusItemKit's shared `PreferencesPane`: what the menu bar shows, Volta's
/// idle, the temperature unit and Start at Login.
final class PreferencesModel: ObservableObject {
    @Published var showIcon = DisplayPrefs.showIcon { didSet { DisplayPrefs.showIcon = showIcon; onChange() } }
    @Published var showFace = DisplayPrefs.showFace { didSet { DisplayPrefs.showFace = showFace; onChange() } }
    @Published var showPct = DisplayPrefs.showPct { didSet { DisplayPrefs.showPct = showPct; onChange() } }
    @Published var showTime = DisplayPrefs.showTime { didSet { DisplayPrefs.showTime = showTime; onChange() } }
    @Published var animateFace = DisplayPrefs.animateFace { didSet { DisplayPrefs.animateFace = animateFace; onChange() } }
    @Published var tempUnit = DisplayPrefs.tempUnit { didSet { DisplayPrefs.tempUnit = tempUnit; onChange() } }

    /// Redraws the menu-bar item after any change.
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        PreferencesForm {
            Section("General") {
                StartAtLoginToggle()
                Picker("Temperature", selection: $model.tempUnit) {
                    Text("°C").tag("C")
                    Text("°F").tag("F")
                }
                .pickerStyle(.segmented)
            }
            Section("Menu Bar Shows") {
                Toggle("Battery icon", isOn: $model.showIcon)
                Toggle("Battery face", isOn: $model.showFace).disabled(!model.showIcon)
                Toggle("Percentage", isOn: $model.showPct)
                Toggle("Time remaining", isOn: $model.showTime)
            }
            Section {
                Toggle("Animate Volta", isOn: $model.animateFace).disabled(!model.showIcon || !model.showFace)
            } footer: {
                PreferencesNote("Off, Volta still sips while charging and does his twice-a-minute turn; only his idle glances, blinks and yawns stop.")
            }
        }
    }
}

func makePreferences(onChange: @escaping () -> Void) -> PreferencesPane {
    let model = PreferencesModel(onChange: onChange)
    return PreferencesPane(appName: "Battery Time") { PreferencesView(model: model) }
}
