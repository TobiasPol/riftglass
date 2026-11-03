// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OverlayKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OverlayKit", targets: ["OverlayKit"])],
    dependencies: [],
    targets: [
        .target(
            name: "OverlayKit",
            dependencies: []
        ),
        .testTarget(name: "OverlayKitTests", dependencies: ["OverlayKit"])
    ]
)
