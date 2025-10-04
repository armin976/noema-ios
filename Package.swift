// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NoemaPackages",
    platforms: [
        .iOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        // Expose the library through this package product
        .library(name: "NoemaPackages", targets: ["NoemaPackages"]),
    ],
    dependencies: [
        .package(path: "Sources/RollingThought"),
    ],
    targets: [
        // Regular target that wraps the binary framework
        .target(
            name: "NoemaPackages",
            dependencies: ["LlamaFramework", "RollingThought"],
            path: "Sources/NoemaPackages"
        ),
        // Binary framework target
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b6653/llama-b6653-xcframework.zip",
            checksum: "b39bf4e4a626130d81fff23cb3f4529c1cb807f87d6e81ccbd30ab191ca13095" // Update via: swift package compute-checksum <path>
        )
    ]
)
