import Foundation

/// Who answers on a route: the sidecar's signed instance ID, or the pinned TLS key of a server without one.
public struct ServerIdentity: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One way to reach a server.
public struct Route: Identifiable, Hashable, Sendable, Codable {
    public enum Endpoint: Hashable, Sendable, Codable {
        /// A Frigate or sidecar base URL reached directly.
        case direct(URL)
        /// Iwa Connect, through the relay.
        case connect
    }

    public enum Source: Hashable, Sendable, Codable {
        /// Added by the user, by pairing, or by subscribing to Connect.
        case saved
        /// Reported by the sidecar while connected over another route; it borrows that route's credential.
        case learned(via: Route.ID)
    }

    public let id: String
    public let endpoint: Endpoint
    public let source: Source
    /// The sidecar confirmed this address is on its tailnet, which `100.64.0.0/10` alone can't show.
    public let confirmedTailscale: Bool

    public static let connect = Route(id: "connect", endpoint: .connect, source: .saved, confirmedTailscale: false)

    /// A direct route to `url`'s origin. Returns `nil` for anything but an http(s) URL with a host.
    public static func direct(_ url: URL, source: Source = .saved, confirmedTailscale: Bool = false) -> Route? {
        guard let origin = Origin(url) else { return nil }
        let prefix = if case .learned = source { "learned" } else { "direct" }
        return Route(
            id: "\(prefix):\(origin.string)",
            endpoint: .direct(origin.url),
            source: source,
            confirmedTailscale: confirmedTailscale
        )
    }

    public var kind: RouteKind {
        switch endpoint {
        case .connect: .connect
        case .direct(let url): RouteKind.classify(host: Origin(url)?.host ?? "", confirmedTailscale: confirmedTailscale)
        }
    }

    public var url: URL? {
        if case .direct(let url) = endpoint { url } else { nil }
    }

    /// The route whose credential this route uses.
    public var credentialRouteID: Route.ID {
        if case .learned(let via) = source { via } else { id }
    }

    var origin: Origin? { url.flatMap(Origin.init) }

    func withConfirmedTailscale(_ confirmed: Bool) -> Route {
        Route(id: id, endpoint: endpoint, source: source, confirmedTailscale: confirmed)
    }
}

/// A route whose identity check matched the saved server.
///
/// Only `RouteRace` creates these, so a transport that takes a `VerifiedRoute`
/// can't be handed a credential for a route nobody checked.
public struct VerifiedRoute: Hashable, Sendable {
    public let route: Route
    public let identity: ServerIdentity

    init(route: Route, identity: ServerIdentity) {
        self.route = route
        self.identity = identity
    }
}

/// Scheme, host, and port of an http(s) URL, normalized so equal origins compare equal.
struct Origin: Hashable {
    let scheme: String
    let host: String
    let port: Int?

    init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        self.scheme = scheme
        self.host = host
        let defaultPort = scheme == "https" ? 443 : 80
        self.port = components.port == defaultPort ? nil : components.port
    }

    var isPlainHTTP: Bool { scheme == "http" }

    var string: String {
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(bracketed)" + (port.map { ":\($0)" } ?? "")
    }

    var url: URL { URL(string: string + "/")! }
}
