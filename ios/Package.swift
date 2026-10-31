// swift-tools-version: 6.0
import PackageDescription

// SkazochnikCore: models and API client, no UI. Builds and tests on macOS without Xcode.
// SkazochnikUI: SwiftUI design system and screens, shared by the iPhone app (and the iPad app later).
let package = Package(
    name: "Skazochnik",
    defaultLocalization: "ru",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkazochnikCore", targets: ["SkazochnikCore"]),
        .library(name: "SkazochnikUI", targets: ["SkazochnikUI"]),
    ],
    targets: [
        .target(name: "SkazochnikCore"),
        .target(name: "SkazochnikUI", dependencies: ["SkazochnikCore"]),
        .testTarget(name: "SkazochnikUITests", dependencies: ["SkazochnikUI", "SkazochnikCore"]),
        .testTarget(
            name: "SkazochnikCoreTests",
            dependencies: ["SkazochnikCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
