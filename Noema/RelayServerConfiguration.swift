import Foundation
import Security
import RelayKit

struct RelayServerConfiguration: Codable, Equatable {
    static let storageKey = "relay.server.configuration"

    var port: UInt16
    var serveOnLocalNetwork: Bool
    var enableCORS: Bool
    var allowedOrigins: [String]
    var apiToken: String
    var advertiseBonjour: Bool
    var justInTimeLoading: Bool
    var autoUnloadJIT: Bool
    var maxIdleTTLMinutes: Int
    var onlyKeepLastJITModel: Bool
    var requestLoggingEnabled: Bool

    init(port: UInt16 = 12345,
         serveOnLocalNetwork: Bool = true,
         enableCORS: Bool = false,
         allowedOrigins: [String] = [],
         apiToken: String = RelayServerConfiguration.makeToken(),
         advertiseBonjour: Bool = true,
         justInTimeLoading: Bool = true,
         autoUnloadJIT: Bool = true,
         maxIdleTTLMinutes: Int = 20,
         onlyKeepLastJITModel: Bool = false,
         requestLoggingEnabled: Bool = true) {
        self.port = port
        self.serveOnLocalNetwork = serveOnLocalNetwork
        self.enableCORS = enableCORS
        self.allowedOrigins = allowedOrigins
        self.apiToken = apiToken
        self.advertiseBonjour = advertiseBonjour
        self.justInTimeLoading = justInTimeLoading
        self.autoUnloadJIT = autoUnloadJIT
        self.maxIdleTTLMinutes = max(1, maxIdleTTLMinutes)
        self.onlyKeepLastJITModel = onlyKeepLastJITModel
        self.requestLoggingEnabled = requestLoggingEnabled
    }

    var bindHost: String {
        serveOnLocalNetwork ? "0.0.0.0" : "127.0.0.1"
    }

    var idleTTL: TimeInterval {
        TimeInterval(max(1, maxIdleTTLMinutes) * 60)
    }

    func corsAllowedOrigin(for requestOrigin: String?) -> String? {
        guard enableCORS, let origin = requestOrigin?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty else {
            return nil
        }
        if allowedOrigins.contains(where: { $0.caseInsensitiveCompare(origin) == .orderedSame }) {
            return origin
        }
        return nil
    }

    func requiresAuth(for path: String) -> Bool {
        switch path {
        case "/health", "/v1/health", "/api/v0/health":
            return false
        default:
            return true
        }
    }

    mutating func regenerateToken() {
        apiToken = Self.makeToken()
    }

    func saving() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            RelayLog.record(category: "RelayServer", message: "Failed to save server configuration: \(error.localizedDescription)")
        }
    }

    static func load() -> RelayServerConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            UserDefaults.standard.set(true, forKey: "relay.server.configuration.hasInitializedServeOnLocalNetwork")
            return RelayServerConfiguration()
        }
        do {
            var config = try JSONDecoder().decode(RelayServerConfiguration.self, from: data)
            if config.apiToken.isEmpty {
                config.apiToken = makeToken()
                config.saving()
            }
            if !UserDefaults.standard.bool(forKey: "relay.server.configuration.hasInitializedServeOnLocalNetwork") {
                config.serveOnLocalNetwork = true
                config.saving()
                UserDefaults.standard.set(true, forKey: "relay.server.configuration.hasInitializedServeOnLocalNetwork")
            }
            return config
        } catch {
            RelayLog.record(category: "RelayServer", message: "Failed to decode server configuration: \(error.localizedDescription)")
            return RelayServerConfiguration()
        }
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        for idx in bytes.indices {
            bytes[idx] = UInt8.random(in: .min ... .max)
        }
        return Data(bytes).base64EncodedString()
    }
}
