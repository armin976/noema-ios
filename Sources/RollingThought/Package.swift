// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RollingThought",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "RollingThought", targets: ["RollingThought"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RollingThought",
            dependencies: [],
            path: "."
        )
    ]
)
