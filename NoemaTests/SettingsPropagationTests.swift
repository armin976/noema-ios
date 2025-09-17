// SettingsPropagationTests.swift
import XCTest
@testable import Noema

final class SettingsPropagationTests: XCTestCase {
    @MainActor func testEnvironmentVariables() {
        var s = ModelSettings()
        s.contextLength = 1234
        s.gpuLayers = 2
        s.cpuThreads = 6
        s.kvCacheOffload = false
        s.keepInMemory = false
        s.useMmap = false
        s.seed = 42
        s.kCacheQuant = .q4_0
        s.vCacheQuant = .q4_1
        s.tokenizerPath = "/tmp/tok"

        let vm = ChatVM()
        vm.applyEnvironmentVariables(from: s)

        XCTAssertEqual(String(cString: getenv("LLAMA_CONTEXT_SIZE")), "1234")
        XCTAssertEqual(String(cString: getenv("LLAMA_N_GPU_LAYERS")), "2")
        XCTAssertEqual(String(cString: getenv("LLAMA_THREADS")), "6")
        XCTAssertEqual(String(cString: getenv("LLAMA_KV_OFFLOAD")), "0")
        XCTAssertEqual(String(cString: getenv("LLAMA_MMAP")), "0")
        XCTAssertEqual(String(cString: getenv("LLAMA_KEEP")), "0")
        XCTAssertEqual(String(cString: getenv("LLAMA_SEED")), "42")
        // Flash Attention removed from settings; ensure var is unset
        XCTAssertTrue(getenv("LLAMA_FLASH_ATTENTION") == nil || String(cString: getenv("LLAMA_FLASH_ATTENTION")).isEmpty)
        XCTAssertEqual(String(cString: getenv("LLAMA_K_QUANT")), "Q4_0")
        XCTAssertTrue(getenv("LLAMA_V_QUANT") == nil || String(cString: getenv("LLAMA_V_QUANT")).isEmpty)
        XCTAssertEqual(String(cString: getenv("LLAMA_TOKENIZER_PATH")), "/tmp/tok")
    }
}
