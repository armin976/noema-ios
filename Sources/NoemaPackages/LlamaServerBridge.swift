import Foundation
import NoemaLLamaServer

public enum LlamaServerBridge {
    @discardableResult
    public static func start(host: String = "127.0.0.1",
                              preferredPort: Int32 = 0,
                              ggufPath: String,
                              mmprojPath: String?) -> Int32 {
        let mm = mmprojPath ?? ""
        return noema_llama_server_start(host, preferredPort, ggufPath, mm)
    }

    public static func stop() {
        noema_llama_server_stop()
    }

    public static func port() -> Int32 {
        return noema_llama_server_port()
    }
}
