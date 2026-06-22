// swift-tools-version:5.9
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
