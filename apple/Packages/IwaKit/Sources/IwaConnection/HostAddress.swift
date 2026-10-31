/// Classifies a URL host (hostname, IPv4, or IPv6 literal) by network.
struct HostAddress {
    private let host: String
    private let ipv4: [UInt8]?
    private let ipv6: [UInt16]?

    init(_ rawHost: String) {
        var host = rawHost.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if let zone = host.firstIndex(of: "%") {
            host = String(host[..<zone])
        }
        if host.hasSuffix(".") { host.removeLast() }

        self.host = host
        self.ipv4 = Self.parseIPv4(host)
        self.ipv6 = ipv4 == nil ? Self.parseIPv6(host) : nil
    }

    /// RFC 1918, link-local, and local hostnames (`.local` mDNS, `.lan`, `.home.arpa`, single-label names).
    var isPrivate: Bool {
        if let ipv4 {
            switch (ipv4[0], ipv4[1]) {
            case (10, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        if let ipv6 {
            return ipv6[0] & 0xfe00 == 0xfc00 // fc00::/7 unique local
                || ipv6[0] & 0xffc0 == 0xfe80 // fe80::/10 link local
        }
        let localSuffixes = [".local", ".lan", ".home", ".internal", ".home.arpa"]
        return !host.contains(".") || localSuffixes.contains { host.hasSuffix($0) }
    }

    /// Hostnames and IPv6 addresses that only Tailscale uses.
    var isTailnet: Bool {
        if host.hasSuffix(".ts.net") { return true }
        if let ipv6 { return ipv6[0] == 0xfd7a && ipv6[1] == 0x115c && ipv6[2] == 0xa1e0 }
        return false
    }

    /// `100.64.0.0/10`, shared by Tailscale, Cloudflare WARP, and carrier-grade NAT.
    var isSharedAddressSpace: Bool {
        guard let ipv4 else { return false }
        return ipv4[0] == 100 && (64...127).contains(ipv4[1])
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt8($0) }
        return octets.count == 4 ? octets : nil
    }

    private static func parseIPv6(_ host: String) -> [UInt16]? {
        guard host.contains(":") else { return nil }
        let halves = host.split(separator: "::", omittingEmptySubsequences: false)
        guard halves.count <= 2 else { return nil }

        func groups(_ text: Substring) -> [UInt16]? {
            guard !text.isEmpty else { return [] }
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            let values = parts.compactMap { $0.count <= 4 ? UInt16($0, radix: 16) : nil }
            return values.count == parts.count ? values : nil
        }

        guard let head = groups(halves[0]) else { return nil }
        if halves.count == 1 { return head.count == 8 ? head : nil }
        guard let tail = groups(halves[1]), head.count + tail.count < 8 else { return nil }
        return head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
    }
}
