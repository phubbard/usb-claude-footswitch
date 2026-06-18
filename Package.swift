// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeFootswitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeFootswitch",
            path: "Sources/ClaudeFootswitch"
        )
    ]
)
