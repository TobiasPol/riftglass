// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LeagueKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LeagueKit", targets: ["LeagueKit"])],
    dependencies: [],
    targets: [
        .target(
            name: "LeagueKit",
            dependencies: [],
            resources: [.copy("Resources/riotgames.pem")]
        ),
        .testTarget(name: "LeagueKitTests", dependencies: ["LeagueKit"])
    ]
)
