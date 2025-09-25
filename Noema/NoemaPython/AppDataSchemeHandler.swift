import Foundation
import WebKit

/// Handles the custom `appdata://` scheme that exposes bundled Pyodide assets and
/// user-provided datasets to the in-process WKWebView runtime.
@MainActor
final class AppDataSchemeHandler: NSObject, WKURLSchemeHandler {
    enum Source {
        case bundle
        case datasets

        init?(url: URL) {
            switch url.host?.lowercased() {
            case "bundle": self = .bundle
            case "datasets": self = .datasets
            default: return nil
            }
        }
    }

    private let fileManager: FileManager = .default
    private lazy var datasetsDirectory: URL = {
        var url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url.appendingPathComponent("Datasets", isDirectory: true)
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let source = Source(url: url) else {
            respondNotFound(for: urlSchemeTask)
            return
        }

        let fileURL: URL
        switch source {
        case .bundle:
            guard let resourceURL = Bundle.main.resourceURL else {
                respondNotFound(for: urlSchemeTask)
                return
            }
            var path = url.path
            if path.hasPrefix("/") { path.removeFirst() }
            fileURL = resourceURL.appendingPathComponent(path)
        case .datasets:
            var path = url.path
            if path.hasPrefix("/") { path.removeFirst() }
            fileURL = datasetsDirectory.appendingPathComponent(path)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let response = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": mimeType(for: fileURL.pathExtension)])
            urlSchemeTask.didReceive(response!)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
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

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "html": return "text/html"
        case "csv": return "text/csv"
        case "png": return "image/png"
        case "whl": return "application/octet-stream"
        case "tar": return "application/x-tar"
        default: return "application/octet-stream"
        }
    }
}
