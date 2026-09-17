// swift-tools-version: 6.0
import PackageDescription

let msfRoot = "/Users/schwa/Projects/Vendor/msf"

let package = Package(
    name: "smetal",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CMSF", path: "Sources/CMSF"),
        .target(name: "MSFStubs"),
        .executableTarget(
            name: "smetal",
            dependencies: ["CMSF", "MSFStubs"],
            linkerSettings: [
                .unsafeFlags(["-L\(msfRoot)/build/native", "-lMiniSwiftFrontend"])
            ]
        ),
        .testTarget(name: "SMetalTests", dependencies: ["smetal"]),
    ]
)
