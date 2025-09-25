import Foundation

struct PythonExecuteParams: Codable {
    let code: String
    let file_ids: [String]?
    let timeout_ms: Int?
    let force: Bool?
}

struct PythonExecuteResult: Codable {
    let stdout: String
    let stderr: String
    let tables: [String]
    let images: [String]
}

@MainActor
private final class PythonRuntimeManager {
    static let shared = PythonRuntimeManager()
    private let runner = PythonRunner()
    private var isStarted = false

    func run(code: String, files: [PythonMountFile], timeout: Int) async throws -> PythonResult {
        if !isStarted {
            try await runner.start()
            isStarted = true
        }
        return try await runner.run(code: code, files: files, timeoutMs: timeout)
    }

    func interrupt() {
        runner.interrupt()
    }

    func teardown() {
        runner.teardown()
        isStarted = false
    }
}

final class PythonExecuteTool: Tool {
    static let toolVersion = "1.0.0"

    let name = "python.execute"
    let description = "Execute Python code in the embedded Pyodide runtime."
    private let cache: PythonResultCache

    init(cache: PythonResultCache = .shared) {
        self.cache = cache
    }

    let schema: String = {
        let dict: [String: Any] = [
            "type": "object",
            "properties": [
                "code": ["type": "string", "description": "Python source code to execute."],
                "file_ids": [
                    "type": "array",
                    "description": "Optional dataset file identifiers to mount.",
                    "items": ["type": "string"]
                ],
                "timeout_ms": [
                    "type": "integer",
                    "description": "Execution timeout in milliseconds.",
                    "minimum": 1000,
                    "maximum": 60000,
                    "default": 15000
                ],
                "force": [
                    "type": "boolean",
                    "description": "Skip result cache and re-run the code.",
                    "default": false
                ]
            ],
            "required": ["code"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }()

    func call(args: Data) async throws -> Data {
        let params = try JSONDecoder().decode(PythonExecuteParams.self, from: args)
        if UserDefaults.standard.object(forKey: "pythonEnabled") as? Bool == false {
            throw ToolError.executionFailed("Python execution is disabled in settings.")
        }
        let timeout = params.timeout_ms ?? 15_000
        let mountFiles = resolveFiles(for: params.file_ids ?? [])
        let key = PyRunKey(code: params.code, files: mountFiles, runnerVersion: Self.toolVersion)

        if params.force != true, let entry = cache.lookup(key), let cached = try? entry.loadResult() {
            let payload = buildPayload(from: cached)
            let data = try JSONEncoder().encode(payload)
            NotificationCenter.default.post(name: .pythonExecutionDidComplete, object: payload)
            return data
        }

        let result = try await MainActor.run {
            try await PythonRuntimeManager.shared.run(code: params.code, files: mountFiles, timeout: timeout)
        }

        do {
            try cache.write(key, from: result)
        } catch {
            Task { await logger.log("[PythonExecuteTool] Failed to persist cache: \(error.localizedDescription)") }
        }

        let payload = buildPayload(from: result)
        let data = try JSONEncoder().encode(payload)
        NotificationCenter.default.post(name: .pythonExecutionDidComplete, object: payload)
        return data
    }

    private func buildPayload(from result: PythonResult) -> PythonExecuteResult {
        PythonExecuteResult(
            stdout: result.stdout,
            stderr: result.stderr,
            tables: result.tables.map { $0.base64EncodedString() },
            images: result.images.map { $0.base64EncodedString() }
        )
    }

    private func resolveFiles(for ids: [String]) -> [PythonMountFile] {
        var files: [PythonMountFile] = []
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let datasetRoot = root.appendingPathComponent("Datasets", isDirectory: true)
        for id in ids {
            let url = datasetRoot.appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url) {
                files.append(PythonMountFile(url: url, data: data))
            }
        }
        return files
    }
}

extension Notification.Name {
    static let pythonExecutionDidComplete = Notification.Name("pythonExecutionDidComplete")
    static let pythonSettingsDidChange = Notification.Name("pythonSettingsDidChange")
}
