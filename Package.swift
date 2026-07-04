// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Agent0Graph",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Agent0Graph",
            path: "Sources/Agent0Graph"
        )
    ]
)
