import Foundation
import Testing
@testable import NoemaLLamaServer

@_silgen_name("noema_llama_server_normalize_cache_type_for_test")
private func noema_llama_server_normalize_cache_type_for_test(
    _ rawValue: UnsafePointer<CChar>?
) -> UnsafePointer<CChar>?

private struct StartDiagnostics: Decodable {
    let code: String
    let message: String
    let lastHTTPStatus: Int?
    let elapsedMs: Int
    let progress: Double
    let httpReady: Bool
}

private func normalizeCacheType(_ rawValue: String?) -> String? {
    guard let rawValue else {
        return noema_llama_server_normalize_cache_type_for_test(nil).map {
            String(cString: $0)
        }
    }
    return rawValue.withCString { pointer in
        noema_llama_server_normalize_cache_type_for_test(pointer).map {
            String(cString: $0)
        }
    }
}

@Test func cacheTypeNormalizationLowercasesSupportedTokens() {
    #expect(normalizeCacheType("F16") == "f16")
    #expect(normalizeCacheType(" Q4_1\t") == "q4_1")
    #expect(normalizeCacheType("IQ4_NL") == "iq4_nl")
}

@Test func cacheTypeNormalizationRejectsBlankOrUnsupportedTokens() {
    #expect(normalizeCacheType(nil) == nil)
    #expect(normalizeCacheType("") == nil)
    #expect(normalizeCacheType("   ") == nil)
    #expect(normalizeCacheType("Q3_K_M") == nil)
}

@Test func startupFailureExposesDiagnostics() async throws {
    let port = noema_llama_server_start("127.0.0.1", 0, "/tmp/does-not-exist.gguf", "")
    #expect(port == 0)

    let raw = String(cString: noema_llama_server_last_start_diagnostics_json())
    #expect(!raw.isEmpty)

    let data = try #require(raw.data(using: .utf8))
    let diagnostics = try JSONDecoder().decode(StartDiagnostics.self, from: data)

    #expect([
        "port_allocation_failed",
        "listener_timeout",
        "ready_timeout",
        "http_init_failed",
        "model_load_failed",
        "server_exited_early"
    ].contains(diagnostics.code))
    #expect(!diagnostics.message.isEmpty)
    #expect(diagnostics.elapsedMs >= 0)
    #expect(diagnostics.progress >= 0)
    #expect(diagnostics.progress <= 1)
}

@Test func manualMacOSLoopbackVerification() async throws {
    guard ProcessInfo.processInfo.environment["NOEMA_MANUAL_LOOPBACK_VERIFY"] == "1" else {
        return
    }

    let modelPath = "/Users/arminstamate/Desktop/untitled folder 3/untitled folder/Noema/.models/gemma-3-4b-it-Q3_K_M.gguf"
    guard FileManager.default.fileExists(atPath: modelPath) else {
        return
    }

    let port = noema_llama_server_start("127.0.0.1", 0, modelPath, "")
    #expect(port > 0)
    noema_llama_server_stop()
}
