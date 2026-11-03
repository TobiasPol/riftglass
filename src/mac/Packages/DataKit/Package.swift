// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DataKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DataKit", targets: ["DataKit"])],
    dependencies: [],
    targets: [
        .target(
            name: "DataKit",
            dependencies: []
        ),
        .testTarget(name: "DataKitTests", dependencies: ["DataKit"])
    ]
)
