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
    targets: [
        .target(
            name: "MeetingRescueCore",
            path: "Sources/MeetingRescueCore"
        ),
        .executableTarget(
            name: "MeetingRescue",
            dependencies: ["MeetingRescueCore"],
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
