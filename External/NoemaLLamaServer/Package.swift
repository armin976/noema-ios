// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoemaLLamaServer",
    platforms: [
        .iOS(.v17),
        .macOS(.v12),
        .visionOS(.v1),
        .macCatalyst(.v13)
    ],
    products: [
        // Build as a dynamic library so we can ship a newer llama.cpp build for the
        // loopback server without colliding with the app's in-process llama.framework.
        .library(name: "NoemaLLamaServer", type: .dynamic, targets: ["NoemaLLamaServer"])
    ],
    targets: [
        .target(
            name: "NoemaLLamaServer",
            path: "Sources/NoemaLLamaServer",
            exclude: [
                // previous vendored snapshot (kept for reference)
                "upstream_b7634",
                // Finder-style duplicate upstream directories; keep them out of
                // the target so SwiftPM does not discover extra CLI main() files.
                "upstream/common 2",
                "upstream/ggml/cmake 2",
                "upstream/ggml/include 2",
                "upstream/ggml/src 2",
                "upstream/tools/cli 2",
                "upstream/tools/completion 2",
                "upstream/tools/cvector-generator 2",
                "upstream/tools/gguf-split 2",
                "upstream/tools/llama-bench 2",
                "upstream/tools/quantize 2",
                "upstream/tools/rpc 2",
                "upstream/tools/server 2",
                "upstream/tools/tokenize 2",
                "upstream/tools/tts 2",
                "upstream/vendor/cpp-httplib 2",
                "upstream/vendor/miniaudio 2",
                "upstream/vendor/sheredom 2",
                "upstream/vendor/stb 2",
                // compile server.cpp only via bridge/server_embed.cpp inclusion
                "upstream/tools/server/server.cpp",
                // exclude mtmd CLI entrypoints
                "upstream/tools/mtmd/mtmd-cli.cpp",
                "upstream/tools/mtmd/deprecation-warning.cpp",
                "upstream/tools/mtmd/debug",
                // exclude non-server tool binaries that define their own main()
                "upstream/tools/batched-bench",
                "upstream/tools/cli",
                "upstream/tools/completion",
                "upstream/tools/cvector-generator",
                "upstream/tools/export-lora",
                "upstream/tools/fit-params",
                "upstream/tools/gguf-split",
                "upstream/tools/imatrix",
                "upstream/tools/llama-bench",
                "upstream/tools/perplexity",
                "upstream/tools/parser",
                "upstream/tools/quantize",
                "upstream/tools/results",
                "upstream/tools/rpc",
                "upstream/tools/tokenize",
                "upstream/tools/tts",
                // exclude backends we don't ship in the iOS loopback build
                "upstream/ggml/src/ggml-webgpu",
                "upstream/ggml/src/ggml-zendnn",
                "upstream/ggml/src/ggml-zdnn",
                "upstream/ggml/src/ggml-hexagon",
                "upstream/ggml/src/ggml-cuda",
                "upstream/ggml/src/ggml-opencl",
                "upstream/ggml/src/ggml-openvino",
                "upstream/ggml/src/ggml-vulkan",
                "upstream/ggml/src/ggml-cann",
                "upstream/ggml/src/ggml-musa",
                "upstream/ggml/src/ggml-sycl",
                "upstream/ggml/src/ggml-hip",
                "upstream/ggml/src/ggml-rpc",
                "upstream/ggml/src/ggml-virtgpu",
                // CPU backend contains architecture-specific kernels not gated for non-target builds.
                "upstream/ggml/src/ggml-cpu/spacemit",
                // Optional dependency; only built when enabled via CMake + headers present.
                "upstream/ggml/src/ggml-cpu/kleidiai",
                // Only build CPU arch backends we need (Apple arm64 + simulator x86_64).
                "upstream/ggml/src/ggml-cpu/arch/loongarch",
                "upstream/ggml/src/ggml-cpu/arch/powerpc",
                "upstream/ggml/src/ggml-cpu/arch/riscv",
                "upstream/ggml/src/ggml-cpu/arch/s390",
                "upstream/ggml/src/ggml-cpu/arch/wasm",
                // We embed the Metal shader source via bridge/ggml_metal_embed.cpp.
                // Prevent SwiftPM/Xcode from trying to compile ggml-metal.metal directly.
                "upstream/ggml/src/ggml-metal/ggml-metal.metal"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_VERSION", to: "\"0.9.11\""),
                .define("GGML_COMMIT", to: "\"009a1133\""),
                .define("LLAMA_USE_HTTPLIB", to: "1"),
                .define("LLAMA_SHARED", to: "1"),
                .define("GGML_USE_CPU", to: "1"),
                .define("GGML_USE_METAL", to: "1"),
                .define("GGML_METAL_EMBED_LIBRARY", to: "1"),
                .define("GGML_USE_ACCELERATE", to: "1"),
                .define("GGML_BLAS_USE_ACCELERATE", to: "1"),
                .define("ACCELERATE_NEW_LAPACK", to: "1"),
                .define("ACCELERATE_LAPACK_ILP64", to: "1"),
                .define("NOEMA_LLAMA_SERVER_TEST_HOOKS", .when(configuration: .debug)),
                // ggml-metal sources are written for manual retain/release.
                .unsafeFlags([
                    "-fno-objc-arc",
                    // Avoid ODR/symbol collisions with the app's in-process llama.framework.
                    // Only the Noema entry points are meant to be public.
                    "-fvisibility=hidden",
                    // Xcode coverage instrumentation does not link the profiling runtime
                    // for package framework products, so keep vendored llama.cpp uninstrumented.
                    "-fno-profile-instr-generate",
                    "-fno-coverage-mapping"
                ]),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream/src"),
                .headerSearchPath("upstream/common"),
                .headerSearchPath("upstream/tools/server"),
                .headerSearchPath("upstream/vendor"),
                .headerSearchPath("upstream/vendor/cpp-httplib"),
                .headerSearchPath("upstream/vendor/nlohmann"),
                .headerSearchPath("upstream/vendor/miniaudio"),
                .headerSearchPath("upstream/vendor/sheredom"),
                .headerSearchPath("upstream/vendor/stb"),
                .headerSearchPath("upstream/include"),
                .headerSearchPath("upstream/ggml/include"),
                .headerSearchPath("upstream/ggml/src"),
                .headerSearchPath("upstream/ggml/src/ggml-cpu"),
                .headerSearchPath("upstream/tools/mtmd")
            ],
            cxxSettings: [
                .define("GGML_VERSION", to: "\"0.9.11\""),
                .define("GGML_COMMIT", to: "\"009a1133\""),
                .define("LLAMA_USE_HTTPLIB", to: "1"),
                .define("LLAMA_SHARED", to: "1"),
                .define("GGML_USE_CPU", to: "1"),
                .define("GGML_USE_METAL", to: "1"),
                .define("GGML_METAL_EMBED_LIBRARY", to: "1"),
                .define("GGML_USE_ACCELERATE", to: "1"),
                .define("GGML_BLAS_USE_ACCELERATE", to: "1"),
                .define("ACCELERATE_NEW_LAPACK", to: "1"),
                .define("ACCELERATE_LAPACK_ILP64", to: "1"),
                .define("NOEMA_LLAMA_SERVER_TEST_HOOKS", .when(configuration: .debug)),
                // Keep ObjC++ sources consistent with the ggml-metal (non-ARC) build.
                .unsafeFlags([
                    "-fno-objc-arc",
                    // Avoid ODR/symbol collisions with the app's in-process llama.framework.
                    // Only the Noema entry points are meant to be public.
                    "-fvisibility=hidden",
                    "-fvisibility-inlines-hidden",
                    // Xcode coverage instrumentation does not link the profiling runtime
                    // for package framework products, so keep vendored llama.cpp uninstrumented.
                    "-fno-profile-instr-generate",
                    "-fno-coverage-mapping"
                ]),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream/src"),
                .headerSearchPath("upstream/common"),
                .headerSearchPath("upstream/tools/server"),
                .headerSearchPath("upstream/vendor"),
                .headerSearchPath("upstream/vendor/cpp-httplib"),
                .headerSearchPath("upstream/vendor/nlohmann"),
                .headerSearchPath("upstream/vendor/miniaudio"),
                .headerSearchPath("upstream/vendor/sheredom"),
                .headerSearchPath("upstream/vendor/stb"),
                .headerSearchPath("upstream/include"),
                .headerSearchPath("upstream/ggml/include"),
                .headerSearchPath("upstream/ggml/src"),
                .headerSearchPath("upstream/ggml/src/ggml-cpu"),
                .headerSearchPath("upstream/tools/mtmd")
            ],
            linkerSettings: [
                // If Xcode reuses an already instrumented package object while coverage
                // is enabled on the app scheme, make the package framework link resilient.
                .unsafeFlags(["-fprofile-instr-generate"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "NoemaLLamaServerTests",
            dependencies: ["NoemaLLamaServer"]
        )
    ],
    cLanguageStandard: .gnu11,
    cxxLanguageStandard: .cxx17
)
