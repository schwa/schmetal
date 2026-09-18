// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "schmetal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Schmetal", targets: ["Schmetal"]),
        .executable(name: "schmetal", targets: ["schmetal-cli"]),
    ],
    targets: [
        .target(name: "Schmetal"),
        .executableTarget(name: "schmetal-cli", dependencies: ["Schmetal"]),
        .testTarget(name: "SchmetalTests", dependencies: ["Schmetal"]),
    ]
)
