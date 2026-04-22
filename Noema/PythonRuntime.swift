import Foundation

struct PythonRuntimeStatus: Equatable, Sendable {
    let backend: String
    let isAvailable: Bool
    let reason: String?
}

enum PythonRuntime {
    static let embeddedPythonVersion = "python3.14"

    static func makeExecutor() -> (any PythonExecutor)? {
        #if targetEnvironment(macCatalyst)
        return ProcessPythonExecutor()
        #elseif os(macOS)
        let embedded = embeddedExecutor()
        let process = ProcessPythonExecutor()
        if embedded.isAvailable || process.isAvailable {
            return FallbackPythonExecutor(primary: embedded, fallback: process)
        }
        return nil
        #elseif os(iOS) || os(visionOS)
        let embedded = embeddedExecutor()
        return embedded.isAvailable ? embedded : nil
        #else
        return nil
        #endif
    }

    static func status() -> PythonRuntimeStatus {
        #if targetEnvironment(macCatalyst)
        let process = ProcessPythonExecutor()
        if process.isAvailable {
            return PythonRuntimeStatus(backend: "process", isAvailable: true, reason: nil)
        }
        return PythonRuntimeStatus(
            backend: "unavailable",
            isAvailable: false,
            reason: "System Python 3 is not available on this Mac."
        )
        #elseif os(macOS)
        let embedded = embeddedExecutor()
        if embedded.isAvailable {
            return PythonRuntimeStatus(backend: "embedded", isAvailable: true, reason: nil)
        }

        let process = ProcessPythonExecutor()
        if process.isAvailable {
            return PythonRuntimeStatus(
                backend: "process",
                isAvailable: true,
                reason: embedded.unavailableReason ?? "Embedded Python runtime unavailable. Falling back to system Python 3."
            )
        }

        return PythonRuntimeStatus(
            backend: "unavailable",
            isAvailable: false,
            reason: embedded.unavailableReason ?? "Python runtime unavailable."
        )
        #elseif os(iOS) || os(visionOS)
        let embedded = embeddedExecutor()
        return PythonRuntimeStatus(
            backend: "embedded",
            isAvailable: embedded.isAvailable,
            reason: embedded.unavailableReason
        )
        #else
        return PythonRuntimeStatus(
            backend: "unavailable",
            isAvailable: false,
            reason: "Python is not available on this platform."
        )
        #endif
    }

    static var canSurfaceTool: Bool {
        status().isAvailable
    }

    static var isAvailable: Bool {
        status().isAvailable
    }

    #if targetEnvironment(macCatalyst)
    private static func embeddedExecutor() -> FallbackEmbeddedUnavailableExecutor {
        FallbackEmbeddedUnavailableExecutor()
    }
    #elseif os(macOS) || os(iOS) || os(visionOS)
    private static func embeddedExecutor() -> EmbeddedPythonExecutor {
        let bundle = Bundle.main
        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent("noema-python-embedded", isDirectory: true)

        #if os(macOS)
        let frameworkURL = bundle.privateFrameworksURL?
            .appendingPathComponent("Python.framework", isDirectory: true)
        let runtimeRootURL = frameworkURL?.appendingPathComponent("Versions/Current", isDirectory: true)
        let stdlibURL = runtimeRootURL?.appendingPathComponent("lib/\(embeddedPythonVersion)", isDirectory: true)
        #else
        let frameworkURL = bundle.privateFrameworksURL?
            .appendingPathComponent("Python.framework", isDirectory: true)
        let runtimeRootURL = bundle.bundleURL.appendingPathComponent("python", isDirectory: true)
        let stdlibURL = runtimeRootURL.appendingPathComponent("lib/\(embeddedPythonVersion)", isDirectory: true)
        #endif

        return EmbeddedPythonExecutor(
            runtimeRootURL: runtimeRootURL,
            stdlibURL: stdlibURL,
            tempRootURL: tempRootURL,
            executableURL: bundle.executableURL,
            timeoutClock: { Date() }
        )
    }
    #endif
}

#if os(macOS) && !targetEnvironment(macCatalyst)
private struct FallbackPythonExecutor: PythonExecutor, Sendable {
    let primary: EmbeddedPythonExecutor
    let fallback: ProcessPythonExecutor

    var isAvailable: Bool {
        primary.isAvailable || fallback.isAvailable
    }

    func execute(code: String, timeout: TimeInterval) async throws -> PythonExecutionResult {
        if primary.isAvailable {
            do {
                return try await primary.execute(code: code, timeout: timeout)
            } catch {
                await logger.log("[PythonRuntime] Embedded runtime failed: \(error.localizedDescription)")
            }
        }
        return try await fallback.execute(code: code, timeout: timeout)
    }
}
#elseif targetEnvironment(macCatalyst)
private struct FallbackEmbeddedUnavailableExecutor: Sendable {
    var isAvailable: Bool { false }
    var unavailableReason: String? { "Embedded Python runtime is not configured for Mac Catalyst." }
}
#endif
