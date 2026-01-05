import Foundation
import Darwin

#if os(iOS) || os(visionOS)
@MainActor
final class _BonjourNoemaResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var completion: ((String?) -> Void)?
    private var didFinish = false
    private let timeout: TimeInterval

    init(timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.timeout = timeout
        self.completion = completion
        super.init()
    }

    private static var keepAlive: Set<ObjectIdentifier> = []

    private func retainSelf() { Self.keepAlive.insert(ObjectIdentifier(self)) }
    private func releaseSelf() { Self.keepAlive.remove(ObjectIdentifier(self)) }

    func start() {
        retainSelf()
        browser.delegate = self
        // Search in local domain for the Noema relay HTTP service.
        browser.searchForServices(ofType: "_noema._tcp.", inDomain: "local.")
        // Hard timeout to avoid hanging the caller.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(nil)
        }
    }

    private func resolve(_ service: NetService) {
        service.delegate = self
        service.resolve(withTimeout: timeout)
    }

    private func finish(_ urlString: String?) {
        guard !didFinish else { return }
        didFinish = true
        browser.stop()
        services.forEach { $0.stop() }
        services.removeAll()
        completion?(urlString)
        completion = nil
        releaseSelf()
    }

    // MARK: NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        resolve(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        finish(nil)
    }

    // MARK: NetServiceDelegate
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        // Try next service if available; otherwise finish with nil.
        if let next = services.first(where: { $0 != sender }) {
            resolve(next)
        } else {
            finish(nil)
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.port > 0 else { finish(nil); return }
        // Prefer IPv4 address if present.
        if let addresses = sender.addresses {
            for addrData in addresses {
                let urlString = addrData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) -> String? in
                    guard let base = rawPtr.baseAddress else { return nil }
                    let sa = base.bindMemory(to: sockaddr.self, capacity: 1)
                    if sa.pointee.sa_family == sa_family_t(AF_INET) {
                        var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let ipPtr = inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                        if let ipPtr {
                            let ip = String(cString: ipPtr)
                            return "http://\(ip):\(sender.port)"
                        }
                    }
                    return nil
                }
                if let urlString { finish(urlString); return }
            }
        }
        // Fall back to hostname.local if no raw IPv4 was found.
        if let host = sender.hostName, !host.isEmpty {
            let url = "http://\(host):\(sender.port)"
            finish(url)
        } else {
            finish(nil)
        }
    }
}

actor LANServiceDiscovery {
    static let shared = LANServiceDiscovery()

    // Discover the first Noema relay on the LAN and return its base URL.
    func discoverNoemaLANURL(timeout: TimeInterval = 3.0) async -> String? {
        await LocalNetworkPermissionRequester.shared.ensurePrompt()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let resolver = _BonjourNoemaResolver(timeout: timeout) { url in
                    continuation.resume(returning: url)
                }
                resolver.start()
            }
        }
    }
}
#endif
