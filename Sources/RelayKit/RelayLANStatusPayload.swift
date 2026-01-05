import Foundation

public enum RelayLANInterface: String, Codable, Sendable {
    case wifi
    case ethernet
}

public struct RelayLANStatusPayload: Codable, Sendable {
    public var lanURL: String?
    public var wifiSSID: String?
    public var serveOnLAN: Bool
    public var hostStatus: RelayHostStatus?
    public var updatedAt: Date
    public var interface: RelayLANInterface?

    public init(lanURL: String?,
                wifiSSID: String?,
                serveOnLAN: Bool,
                hostStatus: RelayHostStatus?,
                updatedAt: Date = Date(),
                interface: RelayLANInterface? = nil) {
        self.lanURL = lanURL
        self.wifiSSID = wifiSSID
        self.serveOnLAN = serveOnLAN
        self.hostStatus = hostStatus
        self.updatedAt = updatedAt
        self.interface = interface
    }
}
