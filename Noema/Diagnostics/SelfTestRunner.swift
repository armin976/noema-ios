import Foundation
import NoemaCore

public struct SelfTestItem: Sendable {
    public let name: String
    public let passed: Bool
    public let ms: Int
    public let note: String?
}

public struct SelfTestResult: Sendable {
    public let items: [SelfTestItem]
    public let startedAt: Date
    public let endedAt: Date
    public let markdown: String
    public let reportURL: URL
}

public actor SelfTestRunner {
    private let cache: PythonResultCache
    private let fileManager: FileManager
    private let diagnosticsDirectoryName = "Diagnostics"
    private let reportFileName = "last_report.md"

    public init(cache: PythonResultCache = .shared, fileManager: FileManager = .default) {
        self.cache = cache
        self.fileManager = fileManager
    }

    @discardableResult
    public func runAll() async -> SelfTestResult {
        let started = Date()
        var items: [SelfTestItem] = []

        let runtimeItem = await runRuntimeCheck()
        items.append(runtimeItem)

        let cacheItem = await runCacheCheck()
        items.append(cacheItem)

        let pathItem = await runPathSafetyCheck()
        items.append(pathItem)

        let ended = Date()
        let markdown = buildMarkdown(items: items, started: started, ended: ended)
        let reportURL = await writeReport(markdown: markdown)
        return SelfTestResult(items: items, startedAt: started, endedAt: ended, markdown: markdown, reportURL: reportURL)
    }

    private func runRuntimeCheck() async -> SelfTestItem {
        let start = Date()
        let name = "Runtime"
        do {
            let code = """
import sys, json
try:
    import pandas
except Exception as exc:
    print(json.dumps({"error": f"pandas import failed: {exc}"}))
    raise
info = {
    "sys_version": sys.version.split()[0],
    "pandas_version": getattr(pandas, "__version__", "unknown"),
}
print(json.dumps(info))
"""
            let result = try await MainActor.run {
                try await PythonRuntimeManager.shared.run(code: code, files: [], timeout: 10_000)
            }
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let ms = durationMilliseconds(since: start)
            return SelfTestItem(name: name, passed: true, ms: ms, note: trimmed.isEmpty ? "stdout empty" : trimmed)
        } catch {
            let ms = durationMilliseconds(since: start)
            let note = errorNote(from: error)
            return SelfTestItem(name: name, passed: false, ms: ms, note: note)
        }
    }

    private func runCacheCheck() async -> SelfTestItem {
        let start = Date()
        let name = "Cache"
        let code = """
import base64
from pathlib import Path
import pandas as pd
from js import __noema_emit_table, __noema_emit_image

df = pd.DataFrame({"value": [1, 2, 3]})
__noema_emit_table(df.to_json(orient="records"))
img_data = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAuMB9o7XKf8AAAAASUVORK5CYII=")
output = Path("/tmp/noema-self-test.png")
output.write_bytes(img_data)
__noema_emit_image(str(output))
"""
        do {
            let result = try await MainActor.run {
                try await PythonRuntimeManager.shared.run(code: code, files: [], timeout: 15_000)
            }
            let key = PyRunKey(code: code, files: [], runnerVersion: PythonExecuteTool.toolVersion)
            try cache.write(key, from: result)
            let cached = try cache.loadCachedResult(for: key)
            let ms = durationMilliseconds(since: start)
            let note = "tables: \(cached.tables.count), images: \(cached.images.count)"
            let passed = cached.tables.count == 1 && cached.images.count == 1
            return SelfTestItem(name: name, passed: passed, ms: ms, note: note)
        } catch {
            let ms = durationMilliseconds(since: start)
            return SelfTestItem(name: name, passed: false, ms: ms, note: errorNote(from: error))
        }
    }

    private func runPathSafetyCheck() async -> SelfTestItem {
        let start = Date()
        let name = "Path safety"
        do {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let datasetRoot = docs.appendingPathComponent("Datasets", isDirectory: true)
            _ = try AppDataPathResolver.resolve(path: "../illegal", allowedRoots: [datasetRoot], fileManager: fileManager)
            return SelfTestItem(name: name, passed: false, ms: durationMilliseconds(since: start), note: "Traversal unexpectedly allowed")
        } catch let error as AppError {
            let ms = durationMilliseconds(since: start)
            return SelfTestItem(name: name, passed: error.code == .pathDenied, ms: ms, note: ErrorPresenter.present(error))
        } catch {
            let ms = durationMilliseconds(since: start)
            return SelfTestItem(name: name, passed: false, ms: ms, note: error.localizedDescription)
        }
    }

    private func durationMilliseconds(since start: Date) -> Int {
        let elapsed = Date().timeIntervalSince(start)
        return max(0, Int((elapsed * 1000.0).rounded()))
    }

    private func buildMarkdown(items: [SelfTestItem], started: Date, ended: Date) -> String {
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        lines.append("# Self-Test Report")
        lines.append("")
        lines.append("- Started: \(formatter.string(from: started))")
        lines.append("- Ended: \(formatter.string(from: ended))")
        let totalMs = Int((ended.timeIntervalSince(started) * 1000.0).rounded())
        lines.append("- Duration: \(totalMs) ms")
        lines.append("")
        lines.append("| Check | Result | Duration (ms) | Note |")
        lines.append("| --- | --- | --- | --- |")
        for item in items {
            let result = item.passed ? "✅" : "❌"
            let note = item.note?.replacingOccurrences(of: "|", with: "\\|") ?? ""
            lines.append("| \(item.name) | \(result) | \(item.ms) | \(note) |")
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private func ensureDiagnosticsDirectory() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let diagnosticsDir = documents.appendingPathComponent(diagnosticsDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: diagnosticsDir.path) {
            try? fileManager.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)
        }
        return diagnosticsDir
    }

    private func writeReport(markdown: String) async -> URL {
        await MainActor.run {
            let diagnosticsDir = ensureDiagnosticsDirectory()
            let url = diagnosticsDir.appendingPathComponent(reportFileName)
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    private func errorNote(from error: Error) -> String {
        if let appError = error as? AppError {
            return ErrorPresenter.present(appError)
        }
        return error.localizedDescription
    }
}
