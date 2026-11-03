// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatsKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "StatsKit", targets: ["StatsKit"])],
    dependencies: [],
    targets: [
        .target(
            name: "StatsKit",
            dependencies: [],
            resources: [.copy("Resources/placeholder-builds.json")]
        ),
        .testTarget(name: "StatsKitTests", dependencies: ["StatsKit"])
    ]
)
