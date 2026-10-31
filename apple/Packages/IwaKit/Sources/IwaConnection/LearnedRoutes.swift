import Foundation

/// An address the sidecar reports Frigate is reachable on.
public struct ReportedAddress: Hashable, Sendable, Codable {
    public let url: URL
    public let isTailscale: Bool

    public init(url: URL, isTailscale: Bool = false) {
        self.url = url
        self.isTailscale = isTailscale
    }
}

extension Array where Element == Route {
    /// Applies the addresses the sidecar reported while connected over `activeRoute`.
    ///
    /// Adapted from T3 Code's `mergeLearnedRoutes`:
    /// - learned routes the sidecar stops reporting are dropped, so a changed LAN address replaces the old one;
    /// - saved routes are never removed, and an address that is already saved isn't learned again;
    /// - a credential never travels over plain HTTP off the tailnet unless it was obtained over plain HTTP.
    public func mergingReported(_ reported: [ReportedAddress], activeRoute: Route) -> [Route] {
        var reportedByOrigin: [Origin: ReportedAddress] = [:]
        var reportedOrder: [Origin] = []
        for address in reported {
            guard let origin = Origin(address.url), !HostAddress(origin.host).isLoopback else { continue }
            if reportedByOrigin.updateValue(address, forKey: origin) == nil { reportedOrder.append(origin) }
        }

        let savedOrigins = Set(compactMap { $0.source == .saved ? $0.origin : nil })
        var known = savedOrigins
        var next: [Route] = []
        for route in self {
            let address = route.origin.flatMap { reportedByOrigin[$0] }
            if route.source == .saved {
                next.append(address.map { route.withConfirmedTailscale($0.isTailscale) } ?? route)
                continue
            }
            guard let origin = route.origin, let address, !known.contains(origin),
                  !sendsCredentialInClear(origin: origin, isTailscale: address.isTailscale, credentialRouteID: route.credentialRouteID)
            else { continue }
            known.insert(origin)
            next.append(route.withConfirmedTailscale(address.isTailscale))
        }

        let credentialRouteID = activeRoute.credentialRouteID
        for origin in reportedOrder where !known.contains(origin) {
            let address = reportedByOrigin[origin]!
            guard !sendsCredentialInClear(origin: origin, isTailscale: address.isTailscale, credentialRouteID: credentialRouteID),
                  let route = Route.direct(origin.url, source: .learned(via: credentialRouteID), confirmedTailscale: address.isTailscale)
            else { continue }
            known.insert(origin)
            next = insertingByRank(route, into: next) { $0.kind }
        }
        return next
    }

    /// Removes a route and every learned route that borrows its credential.
    public func removing(_ id: Route.ID) -> [Route] {
        filter { $0.id != id && $0.credentialRouteID != id }
    }

    /// A credential obtained over HTTPS, the tailnet, or Connect must not be sent over plain HTTP off the tailnet.
    private func sendsCredentialInClear(origin: Origin, isTailscale: Bool, credentialRouteID: Route.ID) -> Bool {
        guard origin.isPlainHTTP, !isTailscale, !HostAddress(origin.host).isTailnet else { return false }
        guard let credentialRoute = first(where: { $0.id == credentialRouteID }),
              let credentialOrigin = credentialRoute.origin
        else { return true }
        let plainOverLANOrPublic = credentialOrigin.isPlainHTTP && [.lan, .public].contains(credentialRoute.kind)
        return !plainOverLANOrPublic
    }
}
