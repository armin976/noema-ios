// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .library(name: "Crew", targets: ["Crew"]),
    .library(name: "CrewTools", targets: ["CrewTools"])
]

#if !os(Linux)
products.append(.library(name: "CrewUI", targets: ["CrewUI"]))
products.append(.library(name: "NoemaPackages", targets: ["NoemaPackages"]))
products.append(.library(name: "Inspector", targets: ["Inspector"]))
#endif

var targets: [Target] = [
    .target(
        name: "NoemaCore",
        dependencies: [],
        path: "Sources/Core"
    ),
    .target(
        name: "NotebookExports",
        dependencies: ["NoemaCore"],
        path: "Sources/Notebook"
    ),
    .target(
        name: "Crew",
        dependencies: [],
        path: "Sources/Crew"
    ),
    .target(
        name: "CrewTools",
        dependencies: ["Crew", "NoemaCore"],
        path: "Sources/Tools"
    ),
    .testTarget(
        name: "CrewTests",
        dependencies: ["Crew", "CrewTools"],
        path: "NoemaTests",
        exclude: [
            "FormatDetectionTests.swift",
            "LeapURLSanitizationTests.swift",
            "ModelReadmeLoaderTests.swift",
            "ModelScannerTests.swift",
            "NoemaTests.swift",
            "NotebookStoreTests.swift",
            "PythonResultCacheTests.swift",
            "PreScanTests.swift",
            "PromptBuilderFamilyTests.swift",
            "SettingsPropagationTests.swift",
            "UsageLimiterTests.swift",
            "InspectorTests.swift"
        ],
        sources: [
            "CrewEngineTests.swift",
            "CrewValidatorTests.swift",
            "CrewToolTests.swift"
        ]
    ),
    .testTarget(
        name: "ReproExportTests",
        dependencies: ["NoemaCore"],
        path: "NoemaTests",
        sources: ["ReproExportTests.swift"]
    ),
    .testTarget(
        name: "NoemaCoreTests",
        dependencies: ["NoemaCore"],
        path: "NoemaTests",
        sources: [
            "ErrorPresenterTests.swift",
            "AppDataPathResolverTests.swift",
            "PyRunKeyRoundTripTests.swift"
        ]
    )
]

#if !os(Linux)
targets.append(
    .target(
        name: "CrewUI",
        dependencies: ["Crew"],
        path: "Sources/CrewUI"
    )
)
targets.append(
    .target(
        name: "InspectorExports",
        dependencies: ["NoemaCore"],
        path: "Sources/Inspector"
    )
)
targets.append(
    .target(
        name: "RollingThought",
        dependencies: [],
        path: "Sources/RollingThought"
    )
)
targets.append(
    .target(
        name: "NoemaPackages",
        dependencies: ["LlamaFramework", "RollingThought"],
        path: "Sources/NoemaPackages"
    )
)
targets.append(
    .target(
        name: "Inspector",
        dependencies: [],
        path: "Sources/Inspector"
    )
)
targets.append(
    .binaryTarget(
        name: "LlamaFramework",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b6390/llama-b6390-xcframework.zip",
        checksum: "aabd82969eddfe7dc6e79b0b6a74e76fc5b48296b653412d290896263225b1af"
    )
)
#endif

let package = Package(
    name: "NoemaPackages",
    platforms: [.iOS(.v15)],
    products: products,
    dependencies: [],
    targets: targets
)
