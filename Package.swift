// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NoemaPackages",
    platforms: [.iOS(.v15)],
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
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b6390/llama-b6390-xcframework.zip",
            checksum: "aabd82969eddfe7dc6e79b0b6a74e76fc5b48296b653412d290896263225b1af" // Update via: swift package compute-checksum <path>
        )
    ]
)
