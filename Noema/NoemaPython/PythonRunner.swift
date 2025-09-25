import Foundation
import WebKit

struct PythonResult: Codable {
    var stdout: String
    var stderr: String
    var tables: [Data]
    var images: [Data]
    var artifacts: [String: Data]
}

@MainActor
final class PythonRunner: NSObject {
    enum RunnerError: Error {
        case notStarted
        case alreadyRunning
        case runtimeUnavailable
        case javascriptError(String)
        case timeout
        case cancelled
    }

    private var webView: WKWebView?
    private var ready = false
    private var continuation: CheckedContinuation<PythonResult, Error>?
    private var currentStdout = ""
    private var currentStderr = ""
    private var navigationHandler: NavigationHandler?

    func start() async throws {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.javaScriptEnabled = true
        configuration.setURLSchemeHandler(AppDataSchemeHandler(), forURLScheme: "appdata")
        configuration.userContentController.add(self, name: "pyOut")
        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.isHidden = true
        self.webView = wv
        try await loadRunnerHTML(in: wv)
        ready = true
    }

    func run(code: String, files: [PythonMountFile] = [], timeoutMs: Int = 15000) async throws -> PythonResult {
        guard ready, let webView else { throw RunnerError.notStarted }
        guard continuation == nil else { throw RunnerError.alreadyRunning }
        currentStdout = ""
        currentStderr = ""

        let payload: [String: Any] = [
            "code": code,
            "files": files.map { file in
                [
                    "name": file.name,
                    "data": file.data.base64EncodedString()
                ]
            },
            "timeoutMs": timeoutMs
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: json, encoding: .utf8) else {
            throw RunnerError.javascriptError("Failed to encode payload")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.evaluateJavaScript("runPython(\(jsonString.debugDescription))") { [weak self] _, error in
                guard let self else { return }
                if let error {
                    finish(with: .failure(error))
                }
            }
        }
    }

    func interrupt() {
        guard let webView else { return }
        webView.evaluateJavaScript("interruptPython()", completionHandler: nil)
    }

    func teardown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pyOut")
        webView = nil
        ready = false
        continuation = nil
        navigationHandler = nil
    }

    private func finish(with result: Result<PythonResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func loadRunnerHTML(in webView: WKWebView) async throws {
        guard let url = Bundle.main.url(forResource: "pyodide_runner", withExtension: "html") else {
            throw RunnerError.runtimeUnavailable
        }
        let base = url.deletingLastPathComponent()
        let handler = NavigationHandler()
        navigationHandler = handler
        handler.onFinish = { [weak self] _ in
            self?.navigationHandler = nil
        }
        webView.navigationDelegate = handler
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handler.continuation = continuation
            webView.loadFileURL(url, allowingReadAccessTo: base)
        }
    }
}

extension PythonRunner: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pyOut" else { return }
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "stdout":
            if let data = dict["data"] as? String { currentStdout += data }
        case "stderr":
            if let data = dict["data"] as? String { currentStderr += data }
        case "error":
            let err = (dict["data"] as? String).map { RunnerError.javascriptError($0) } ?? RunnerError.javascriptError("Unknown error")
            finish(with: .failure(err))
        case "result":
            guard let data = dict["data"] as? [String: Any] else { return }
            let tables = (data["tables"] as? [String] ?? []).compactMap { $0.data(using: .utf8) }
            let images = (data["images"] as? [[NSNumber]] ?? []).map { nums in
                Data(nums.map { UInt8(truncating: $0) })
            }
            var artifacts: [String: Data] = [:]
            if let dict = data["artifacts"] as? [String: [NSNumber]] {
                for (key, value) in dict {
                    artifacts[key] = Data(value.map { UInt8(truncating: $0) })
                }
            }
            let result = PythonResult(stdout: currentStdout,
                                      stderr: currentStderr,
                                      tables: tables,
                                      images: images,
                                      artifacts: artifacts)
            finish(with: .success(result))
        default:
            break
        }
    }
}

private final class NavigationHandler: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Error>?
    var onFinish: ((Result<Void, Error>) -> Void)?

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        continuation.resume(with: result)
        self.continuation = nil
        onFinish?(result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(PythonRunner.RunnerError.runtimeUnavailable))
    }
}
