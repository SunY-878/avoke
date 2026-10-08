// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkyIsland",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SkyIsland", targets: ["SkyIsland"])],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "SkyIsland", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
        .testTarget(name: "SkyIslandTests", dependencies: ["SkyIsland", "IslandCore"])
    ],
    swiftLanguageModes: [.v5]
)
