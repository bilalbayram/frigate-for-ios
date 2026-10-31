/// How a route reaches a Frigate server. Ordered by expected speed, fastest first.
///
/// Adapted from T3 Code's `ConnectionRouteKind` (`packages/client-runtime/src/connection/routes.ts`),
/// without loopback and SSH, which don't apply to a phone reaching an NVR.
public enum RouteKind: String, Sendable, Hashable, Codable, CaseIterable {
    case lan
    case tailnet
    /// A non-Tailscale address in `100.64.0.0/10`, a range Tailscale shares with other VPNs such as Cloudflare WARP.
    case vpn
    /// A public hostname, typically a reverse proxy, optionally behind Cloudflare Access or mTLS.
    case `public`
    /// Iwa Connect: WebRTC through the hosted relay.
    case connect

    /// Lower ranks are tried first. `tailnet` and `vpn` tie.
    public var rank: Int {
        switch self {
        case .lan: 1
        case .tailnet, .vpn: 2
        case .public: 3
        case .connect: 4
        }
    }

    public var label: String {
        switch self {
        case .lan: "LAN"
        case .tailnet: "Tailscale"
        case .vpn: "VPN"
        case .public: "Public"
        case .connect: "Iwa Connect"
        }
    }

    /// Classifies a direct route from its host.
    ///
    /// - Parameter confirmedTailscale: Set when the server confirmed the address is on its tailnet,
    ///   which is the only way to tell Tailscale from another VPN using `100.64.0.0/10`.
    public static func classify(host: String, confirmedTailscale: Bool = false) -> RouteKind {
        let host = HostAddress(host)
        if confirmedTailscale || host.isTailnet { return .tailnet }
        if host.isSharedAddressSpace { return .vpn }
        if host.isPrivate { return .lan }
        return .public
    }
}

/// Inserts `route` before the first route with a higher rank, keeping the user's order within a rank.
public func insertingByRank<Route>(
    _ route: Route,
    into routes: [Route],
    kind: (Route) -> RouteKind
) -> [Route] {
    let rank = kind(route).rank
    var result = routes
    let index = result.firstIndex { kind($0).rank > rank } ?? result.endIndex
    result.insert(route, at: index)
    return result
}
