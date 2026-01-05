import Foundation

#if os(iOS) || os(visionOS)
import Darwin

enum LANSubnet {
    private struct HostAddress {
        let family: Int32
        let address: Data
    }

    private struct InterfaceAddress {
        let name: String
        let family: Int32
        let address: Data
        let netmask: Data
    }

    /// Returns true when any resolved IP for the host is on the same subnet
    /// as one of the device's active interfaces. Supports IPv4 and IPv6.
    static func isSameSubnet(host: String) -> Bool {
        let normalizedHost = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        let hostAddresses = resolveHostAddresses(host: normalizedHost)
        guard !hostAddresses.isEmpty else { return false }
        let interfaces = activeInterfaces()
        guard !interfaces.isEmpty else { return false }

        for hostAddress in hostAddresses {
            for interface in interfaces where interface.family == hostAddress.family {
                if networkIDMatches(host: hostAddress.address,
                                    local: interface.address,
                                    mask: interface.netmask) {
                    return true
                }
            }
        }
        return false
    }

    static func normalizedSSID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale.current)
    }

    static func ssidsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return normalizedSSID(lhs) == normalizedSSID(rhs)
    }

    private static func resolveHostAddresses(host: String) -> [HostAddress] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &res)
        guard status == 0, let start = res else {
            if let resPointer = res { freeaddrinfo(resPointer) }
            return []
        }
        defer { freeaddrinfo(start) }

        var output: [HostAddress] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = start
        while let current = ptr {
            let family = current.pointee.ai_family
            guard family == AF_INET || family == AF_INET6,
                  let addr = current.pointee.ai_addr else {
                ptr = current.pointee.ai_next
                continue
            }
            if let data = data(from: addr, family: family) {
                output.append(HostAddress(family: family, address: data))
            }
            ptr = current.pointee.ai_next
        }
        return output
    }

    private static func activeInterfaces() -> [InterfaceAddress] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var interfaces: [InterfaceAddress] = []
        var ptr = start
        while true {
            let iface = ptr.pointee
            guard let addr = iface.ifa_addr else {
                if let next = iface.ifa_next { ptr = next } else { break }
                continue
            }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                if let next = iface.ifa_next { ptr = next } else { break }
                continue
            }
            guard let addressData = data(from: addr, family: family),
                  let netmaskPtr = iface.ifa_netmask,
                  let maskData = data(from: netmaskPtr, family: family) else {
                if let next = iface.ifa_next { ptr = next } else { break }
                continue
            }
            let name = String(cString: iface.ifa_name)
            interfaces.append(InterfaceAddress(name: name,
                                               family: family,
                                               address: addressData,
                                               netmask: maskData))
            if let next = iface.ifa_next {
                ptr = next
            } else {
                break
            }
        }

        // Prioritize Wi-Fi interfaces (en*) before others to increase match likelihood.
        return interfaces.sorted { lhs, rhs in
            priority(for: lhs.name) < priority(for: rhs.name)
        }
    }

    private static func networkIDMatches(host: Data, local: Data, mask: Data) -> Bool {
        let count = min(host.count, local.count, mask.count)
        guard count > 0 else { return false }
        for index in 0..<count {
            if (host[index] & mask[index]) != (local[index] & mask[index]) {
                return false
            }
        }
        return true
    }

    private static func data(from sockaddr: UnsafePointer<sockaddr>, family: Int32) -> Data? {
        switch family {
        case AF_INET:
            return sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin_addr) { Data($0) }
            }
        case AF_INET6:
            return sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin6_addr) { Data($0) }
            }
        default:
            return nil
        }
    }

    private static func priority(for name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("awdl") { return 2 }
        if name.hasPrefix("pdp_ip") { return 3 }
        return 4
    }
}
#endif
