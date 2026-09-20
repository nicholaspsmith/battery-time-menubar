// swift-tools-version:5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import PackageDescription

let package = Package(
    name: "BatteryTime",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BatteryTime", targets: ["BatteryTime"]),
        .library(name: "BatteryTimeCore", targets: ["BatteryTimeCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
    ],
    targets: [
        .target(name: "BatteryTimeCore"),
        .executableTarget(
            name: "BatteryTime",
            dependencies: ["BatteryTimeCore", .product(name: "StatusItemKit", package: "StatusItemKit")]
        ),
        .testTarget(name: "BatteryTimeCoreTests", dependencies: ["BatteryTimeCore"]),
    ]
)
