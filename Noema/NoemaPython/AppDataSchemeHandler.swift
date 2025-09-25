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
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let datasets = docs.appendingPathComponent("Datasets", isDirectory: true)
        let canonical = datasets.standardizedFileURL.resolvingSymlinksInPath()
        if !fileManager.fileExists(atPath: canonical.path) {
            try? fileManager.createDirectory(at: canonical, withIntermediateDirectories: true)
        }
        return canonical
    }()
    private lazy var cacheDirectory: URL = {
        PythonResultCache.shared.rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }()
    private lazy var bundlePyodideRoot: URL? = {
        Bundle.main.resourceURL?
            .appendingPathComponent("pyodide", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
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
            Task { await logger.log("[AppDataScheme] \(ErrorPresenter.present(error)) :: \(error.message)") }
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
        let sanitizedPath = normalize(decodedPath)
        let allowedRoots: [URL]
        let relativePath: String
        switch source {
        case .bundle:
            guard let bundlePyodideRoot else {
                throw AppError(code: .pathDenied, message: "Bundle resources unavailable")
            }
            allowedRoots = [bundlePyodideRoot]
            guard !sanitizedPath.isEmpty else {
                return bundlePyodideRoot
            }
            let components = sanitizedPath.split(separator: "/")
            guard components.first == "pyodide" else {
                throw AppError(code: .pathDenied, message: "Bundle path must start with pyodide/: \(decodedPath)")
            }
            relativePath = components.dropFirst().joined(separator: "/")
        case .datasets:
            allowedRoots = [datasetsDirectory]
            if sanitizedPath == "Datasets" {
                relativePath = ""
            } else if sanitizedPath.hasPrefix("Datasets/") {
                relativePath = String(sanitizedPath.dropFirst("Datasets/".count))
            } else {
                relativePath = sanitizedPath
            }
        case .cache:
            allowedRoots = [cacheDirectory]
            relativePath = sanitizedPath
        }
        let resolved = try AppDataPathResolver.resolve(path: relativePath, allowedRoots: allowedRoots, fileManager: fileManager)
        return resolved.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "" }
        let parts = trimmed.split(separator: "/").filter { $0 != "." }
        return parts.joined(separator: "/")
    }
}
