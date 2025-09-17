// NetworkKillSwitch.swift
import Foundation

/// - Localhost traffic is also blocked to ensure zero network activity.
final class LockIsolated<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    @discardableResult
    func withValue<R>(_ body: (Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(value)
    }

    @discardableResult
    func withMutableValue<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

/// URLProtocol that denies all HTTP/HTTPS requests when the kill switch is enabled.
final class NetworkBlockedURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard NetworkKillSwitch.isEnabled else { return false }
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Fail immediately without performing any network I/O
        let error = URLError(.notConnectedToInternet)
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
enum NetworkKillSwitch {
    private static let enabledState = LockIsolated(false)

    /// Weakly-held set of URLSession instances to cancel when the switch is enabled
    private static let trackedSessions = LockIsolated(NSHashTable<AnyObject>.weakObjects())

    static var isEnabled: Bool {
        enabledState.withValue { $0 }
    }

    /// Register a session to be cancelled if off-grid is turned on while it's active.
    static func track(session: URLSession) {
        trackedSessions.withMutableValue { $0.add(session) }
    }

    /// Enable or disable the global kill switch.
    static func setEnabled(_ enabled: Bool) {
        let wasEnabled = enabledState.withValue { $0 }
        guard enabled != wasEnabled else { return }
        enabledState.withMutableValue { $0 = enabled }

        if enabled {
            URLProtocol.registerClass(NetworkBlockedURLProtocol.self)

            // Cancel tasks on shared session
            URLSession.shared.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
            }

            // Cancel tasks on tracked sessions
            let sessions = trackedSessions.withValue { $0.allObjects.compactMap { $0 as? URLSession } }
            for session in sessions {
                session.getAllTasks { tasks in
                    tasks.forEach { $0.cancel() }
                }
                session.invalidateAndCancel()
            }

            // Cancel inflight hub requests
            Task { await HFHubRequestManager.shared.cancelAll() }

            // Cancel Leap polling tasks (LeapModelDownloader handles its own lifecycle)
            Task { LeapBundleDownloader.shared.cancelAll() }
        } else {
            URLProtocol.unregisterClass(NetworkBlockedURLProtocol.self)
        }
    }
}