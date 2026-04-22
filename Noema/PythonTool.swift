// PythonTool.swift
import Foundation

public struct PythonTool: Tool {
    public let name = "noema.python.execute"
    public let description = "Execute Python code and return stdout/stderr output. Use for calculations, data processing, text manipulation, or any task that benefits from code execution. The code runs in a sandboxed environment with a 30-second timeout."
    public let schema = #"""
    { "type":"object", "properties":{
        "code":{"type":"string","description":"Python 3 code to execute. Use print() to produce output."}
    }, "required":["code"] }
    """#

    public func call(args: Data) async throws -> Data {
        struct PythonArgs: Decodable {
            let code: String
        }

        let input = try JSONDecoder().decode(PythonArgs.self, from: args)

        #if DEBUG
        await logger.log(
            """
            [PythonTool] \u{21E2} request
              code length: \(input.code.count) chars
              first 200 chars: \(String(input.code.prefix(200)))
            """
        )
        #endif

        let runtimeStatus = PythonRuntime.status()

        // Guard global availability
        guard PythonToolGate.isAvailable() else {
            if runtimeStatus.isAvailable == false, let reason = runtimeStatus.reason, !reason.isEmpty {
                let errorPayload = ["error": reason]
                return try JSONSerialization.data(withJSONObject: errorPayload)
            }
            let errorPayload = ["error": "Python execution is disabled."]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }

        guard let executor = PythonRuntime.makeExecutor() else {
            let errorPayload = ["error": runtimeStatus.reason ?? "Python is not available on this platform."]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }

        do {
            let result = try await executor.execute(code: input.code, timeout: 30.0)

            #if DEBUG
            await logger.log(
                """
                [PythonTool] \u{21E0} response
                  exitCode: \(result.exitCode)
                  timedOut: \(result.timedOut)
                  stdout: \(result.stdout.prefix(200))
                  stderr: \(result.stderr.prefix(200))
                  time: \(result.executionTimeMs)ms
                """
            )
            #endif

            return try JSONEncoder().encode(result)

        } catch {
            #if DEBUG
            await logger.log(
                """
                [PythonTool] \u{274C} error
                  message: \(error.localizedDescription)
                """
            )
            #endif

            let message: String
            if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                message = localized
            } else {
                let desc = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                message = desc.isEmpty ? "Python execution failed." : desc
            }

            let errorPayload = ["error": message]
            return try JSONSerialization.data(withJSONObject: errorPayload)
        }
    }
}
