// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "schmetal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "schmetal"),
        .testTarget(name: "SchmetalTests", dependencies: ["schmetal"]),
    ]
)
