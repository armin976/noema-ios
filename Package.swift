// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NoemaPackages",
    platforms: [
        .iOS(.v16),
        .visionOS(.v1),
        .macOS(.v12),          // Align with SwiftUI APIs used in RollingThought
        .macCatalyst(.v13)
    ],
    products: [
        .library(name: "NoemaPackages", targets: ["NoemaPackages"]),
        .library(name: "RelayKit", targets: ["RelayKit"]),
        .library(name: "LlamaFrameworkProduct", targets: ["LlamaFramework"]),
    ],
    dependencies: [
        .package(path: "Sources/RollingThought"),
        .package(path: "../NoemaLLamaServer"),
    ],
    targets: [
        .target(
            name: "NoemaPackages",
            dependencies: [
                "RollingThought",
                .target(
                    name: "LlamaFramework",
                    condition: .when(platforms: [.iOS, .visionOS, .macOS, .macCatalyst])
                ),
                .product(name: "NoemaLLamaServer", package: "NoemaLLamaServer"),
            ],
            path: "Sources/NoemaPackages"
        ),
        .target(
            name: "RelayKit",
            dependencies: [],
            path: "Sources/RelayKit"
        ),
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b7313/llama-b7313-xcframework.zip",
            checksum: "423b0eba7ec5e3a41e678c896e2207dba9df93584d0bf567899867cf9f2c4a4f"
        )
    ]
)
