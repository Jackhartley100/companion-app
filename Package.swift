// swift-tools-version: 6.0
import PackageDescription

// Companion is structured as a Swift package so that the domain layer and the
// SwiftUI feature layer can be compiled and unit-tested from the command line
// (building for macOS) without requiring a full Xcode installation. The iOS
// application target is a thin shell that imports `CompanionUI`.
//
// See DECISIONS.md ADR-0002 for why the package, rather than a monolithic Xcode
// target, is the unit of source organisation.
let package = Package(
    name: "Companion",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CompanionCore", targets: ["CompanionCore"]),
        .library(name: "CompanionUI", targets: ["CompanionUI"])
    ],
    targets: [
        .target(
            name: "CompanionCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CompanionUI",
            dependencies: ["CompanionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Exercises whole user journeys through `AppModel` — onboarding, adding
        // a dog, recording a walk, saving it, seeing it in history. These are
        // the smoke tests; XCUITest coverage needs Xcode and is listed in the
        // README as outstanding.
        .testTarget(
            name: "CompanionUITests",
            dependencies: ["CompanionUI", "CompanionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
