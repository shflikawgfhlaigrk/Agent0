// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Agent0Graph",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Agent0Core", targets: ["Agent0Core"]),
        .executable(name: "Agent0Graph", targets: ["Agent0Graph"])
    ],
    targets: [
        .target(
            name: "Agent0Core",
            path: "Sources/Agent0Core"
        ),
        .executableTarget(
            name: "Agent0Graph",
            dependencies: ["Agent0Core"],
            path: "Sources/Agent0Graph"
        ),
        .testTarget(
            name: "Agent0CoreTests",
            dependencies: ["Agent0Core"],
            path: "Tests/Agent0CoreTests"
        )
    ]
)
