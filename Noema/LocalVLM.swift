import Foundation
import Combine
import NoemaPackages

@MainActor
final class LocalVLM: ObservableObject {
    @Published private(set) var baseURL: URL?

    func start() throws {
        // Install any .gguf and .mmproj from the bundle into Caches.
        // If .mmproj exists, it will be passed via --mmproj to enable vision.
        // If not, server still starts as text-only.
        guard let gguf = try Weights.installAny(withExtension: "gguf") else {
            throw NSError(domain: "Noema", code: 100, userInfo: [NSLocalizedDescriptionKey: "No .gguf found in bundle"])
        }
        let mmproj = try Weights.installAny(withExtension: "mmproj")
        let mmPath = mmproj?.url.path
        let port = Int(LlamaServerBridge.start(host: "127.0.0.1", preferredPort: 0, ggufPath: gguf.url.path, mmprojPath: mmPath))
        guard port > 0 else { throw NSError(domain: "Noema", code: 1) }
        baseURL = URL(string: "http://127.0.0.1:\(port)")
        // Surface vision capability to the UI so it can enable the attach button
        let d = UserDefaults.standard
        d.set(true, forKey: "serverVisionEnabled")
        d.set(true, forKey: "currentModelIsRemote")
    }

    func stop() {
        LlamaServerBridge.stop()
        baseURL = nil
        let d = UserDefaults.standard
        d.set(false, forKey: "serverVisionEnabled")
    }

    func send(prompt: String, imagePNG: Data) async throws -> String {
        guard let baseURL else { throw NSError(domain: "Noema", code: 2) }
        let dataURL = "data:image/png;base64," + imagePNG.base64EncodedString()
        let body: [String: Any] = [
            "model": "local-vlm",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
            ]]
        ]
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }
}
