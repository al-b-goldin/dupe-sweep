// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DupeSweep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DupeSweep", targets: ["DupeSweep"]),
        .library(name: "DupeEngine", targets: ["DupeEngine"]),
    ],
    targets: [
        .target(name: "DupeEngine"),
        .executableTarget(name: "DupeSweep", dependencies: ["DupeEngine"]),
        .executableTarget(name: "dupecheck", dependencies: ["DupeEngine"]),
        .testTarget(name: "DupeEngineTests", dependencies: ["DupeEngine"]),
    ]
)
