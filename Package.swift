// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetingRescue",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetingRescue", targets: ["MeetingRescue"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "MeetingRescueCore",
            path: "Sources/MeetingRescueCore"
        ),
        .executableTarget(
            name: "MeetingRescue",
            dependencies: [
                "MeetingRescueCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MeetingRescue",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MeetingRescueCoreTests",
            dependencies: ["MeetingRescueCore"],
            path: "Tests/MeetingRescueCoreTests"
        )
    ]
)
