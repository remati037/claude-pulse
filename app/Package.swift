// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudePulse",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudePulse",
            path: "Sources/ClaudePulse"
        )
    ]
)
