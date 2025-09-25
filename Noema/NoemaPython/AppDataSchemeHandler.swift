import Foundation
import WebKit
import NoemaCore

/// Handles the custom `appdata://` scheme that exposes bundled Pyodide assets and
/// user-provided datasets to the in-process WKWebView runtime.
@MainActor
final class AppDataSchemeHandler: NSObject, WKURLSchemeHandler {
    enum Source {
        case bundle
        case datasets
        case cache

        init?(url: URL) {
            switch url.host?.lowercased() {
            case "bundle": self = .bundle
            case "datasets": self = .datasets
            case "cache": self = .cache
            default: return nil
            }
        }
    }

    private let fileManager: FileManager = .default
    private lazy var datasetsDirectory: URL = {
        var url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url.appendingPathComponent("Datasets", isDirectory: true)
    }()
    private lazy var cacheDirectory: URL = {
        PythonResultCache.shared.rootURL
    }()
    private lazy var bundlePyodideRoot: URL? = {
        Bundle.main.resourceURL?.appendingPathComponent("pyodide", isDirectory: true)
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let source = Source(url: url) else {
            respondNotFound(for: urlSchemeTask)
            return
        }

        do {
            let fileURL = try resolve(url, for: source)
            let data = try Data(contentsOf: fileURL)
            let response = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": mimeType(for: fileURL.pathExtension)])
            urlSchemeTask.didReceive(response!)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch let error as AppError {
            respondForbidden(for: urlSchemeTask)
            Task { await logger.log("[AppDataScheme] \(error.message)") }
        } catch {
            respondNotFound(for: urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func respondNotFound(for task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)
        task.didReceive(response!)
        task.didFinish()
    }

    private func respondForbidden(for task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)
        task.didReceive(response!)
        task.didFinish()
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "html": return "text/html"
        case "csv", "tsv": return "text/csv"
        case "png": return "image/png"
        case "whl": return "application/octet-stream"
        case "tar": return "application/x-tar"
        default: return "application/octet-stream"
        }
    }

    private func resolve(_ url: URL, for source: Source) throws -> URL {
        guard let decodedPath = url.path.removingPercentEncoding else {
            throw AppError(code: .pathDenied, message: "Invalid path encoding for \(url.absoluteString)")
        }
        let allowedRoots: [URL]
        let normalizedPath: String
        switch source {
        case .bundle:
            guard let bundlePyodideRoot else {
                throw AppError(code: .pathDenied, message: "Bundle resources unavailable")
            }
            allowedRoots = [bundlePyodideRoot]
            let trimmed = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if trimmed.hasPrefix("pyodide/") {
                normalizedPath = String(trimmed.dropFirst("pyodide/".count))
            } else if trimmed == "pyodide" {
                normalizedPath = ""
            } else {
                normalizedPath = trimmed
            }
        case .datasets:
            allowedRoots = [datasetsDirectory]
            normalizedPath = decodedPath
        case .cache:
            allowedRoots = [cacheDirectory]
            normalizedPath = decodedPath
        }
        return try AppDataPathResolver.resolve(path: normalizedPath, allowedRoots: allowedRoots, fileManager: fileManager)
    }
}
