// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "smetal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "smetal"),
        .testTarget(name: "SMetalTests", dependencies: ["smetal"]),
    ]
)
