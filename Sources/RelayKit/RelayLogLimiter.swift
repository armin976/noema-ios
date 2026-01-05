import Foundation

actor RelayLogLimiter {
    static let shared = RelayLogLimiter()
    private var lastEvents: [String: Date] = [:]

    func shouldLog(key: String, minInterval: TimeInterval) -> Bool {
        let now = Date()
        if let t = lastEvents[key], now.timeIntervalSince(t) < minInterval {
            return false
        }
        lastEvents[key] = now
        return true
    }
}

