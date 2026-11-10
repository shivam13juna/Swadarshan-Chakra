// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwadarshanChakra",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SwadarshanChakra", targets: ["SwadarshanChakra"]),
        .library(name: "MeditationCore", targets: ["MeditationCore"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"])
    ],
    targets: [
        .target(name: "MeditationCore"),
        .executableTarget(
            name: "SwadarshanChakra",
            dependencies: ["MeditationCore"],
            resources: [.copy("Resources/Artwork"), .copy("Resources/Branding")]
        ),
        // Runnable with Command Line Tools alone; no Xcode/XCTest installation required.
        .executableTarget(name: "CoreChecks", dependencies: ["MeditationCore"], path: "Tests/MeditationCoreTests")
    ]
)
