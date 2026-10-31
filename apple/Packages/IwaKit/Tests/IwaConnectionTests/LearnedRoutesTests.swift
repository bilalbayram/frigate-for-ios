import Foundation
import IwaConnection
import Testing

struct RouteTests {
    @Test(arguments: [
        ("HTTPS://NVR.Local:443/api/", "direct:https://nvr.local"),
        ("http://192.168.1.10:5000", "direct:http://192.168.1.10:5000"),
        ("http://192.168.1.10:80/", "direct:http://192.168.1.10"),
        ("https://[fd7a:115c:a1e0::1]:8971", "direct:https://[fd7a:115c:a1e0::1]:8971"),
    ])
    func `normalizes the origin into the route id`(url: String, id: String) {
        #expect(Route.direct(url).id == id)
    }

    @Test(arguments: ["ftp://nvr.local", "file:///tmp/x", "nvr.local"])
    func `rejects non-http URLs`(url: String) {
        #expect(Route.direct(URL(string: url)!) == nil)
    }

    @Test func `classifies kinds`() {
        #expect(Route.lan.kind == .lan)
        #expect(Route.tailnet.kind == .tailnet)
        #expect(Route.direct("https://[fd7a:115c:a1e0::1]:8971").kind == .tailnet)
        #expect(Route.direct("http://100.101.102.103:5000").kind == .vpn)
        #expect(Route.direct("http://100.101.102.103:5000", tailscale: true).kind == .tailnet)
        #expect(Route.publicURL.kind == .public)
        #expect(Route.connect.kind == .connect)
    }
}

struct LearnedRoutesTests {
    private func reported(_ url: String, tailscale: Bool = false) -> ReportedAddress {
        ReportedAddress(url: URL(string: url)!, isTailscale: tailscale)
    }

    @Test func `learns an HTTPS LAN address ahead of Connect`() {
        let routes = [Route.connect].mergingReported([reported("https://192.168.1.10:8971")], activeRoute: .connect)
        #expect(routes.map(\.id) == ["learned:https://192.168.1.10:8971", "connect"])
        #expect(routes.first?.source == .learned(via: "connect"))
        #expect(routes.first?.kind == .lan)
    }

    @Test(arguments: [Route.connect, Route.lan, Route.tailnet])
    func `never learns plain HTTP off the tailnet from an encrypted credential`(active: Route) {
        let routes = [active].mergingReported([reported("http://192.168.1.10:5000")], activeRoute: active)
        #expect(routes == [active])
    }

    @Test func `learns plain HTTP when the credential came over plain HTTP`() {
        let plain = Route.direct("http://192.168.1.10:5000")
        let routes = [plain].mergingReported([reported("http://10.0.0.5:5000")], activeRoute: plain)
        #expect(routes.map(\.id) == ["direct:http://192.168.1.10:5000", "learned:http://10.0.0.5:5000"])
    }

    @Test func `learns plain HTTP on the tailnet`() {
        let routes = [Route.connect].mergingReported([reported("http://100.101.102.103:5000", tailscale: true)], activeRoute: .connect)
        #expect(routes.first?.kind == .tailnet)
        #expect(routes.count == 2)
    }

    @Test func `drops learned routes the sidecar stops reporting`() {
        let first = [Route.connect].mergingReported([reported("https://192.168.1.10:8971")], activeRoute: .connect)
        let moved = first.mergingReported([reported("https://10.0.0.42:8971")], activeRoute: .connect)
        #expect(moved.map(\.id) == ["learned:https://10.0.0.42:8971", "connect"])
    }

    @Test func `keeps saved routes and does not learn them again`() {
        let saved = [Route.lan, Route.publicURL, Route.connect]
        let routes = saved.mergingReported([reported("https://192.168.1.10:8971")], activeRoute: .connect)
        #expect(routes == saved)
        #expect(saved.mergingReported([], activeRoute: .connect) == saved)
    }

    @Test func `ignores loopback and non-http addresses`() {
        let routes = [Route.connect].mergingReported(
            [reported("https://127.0.0.1:8971"), reported("http://localhost:5000"), reported("ftp://192.168.1.10")],
            activeRoute: .connect
        )
        #expect(routes == [.connect])
    }

    @Test func `confirms Tailscale on a saved VPN-range route`() {
        let saved = Route.direct("https://100.101.102.103:8971")
        #expect(saved.kind == .vpn)
        let routes = [saved].mergingReported([reported("https://100.101.102.103:8971", tailscale: true)], activeRoute: saved)
        #expect(routes.first?.kind == .tailnet)
    }

    @Test func `a route learned over a learned route borrows the original credential`() {
        let learned = [Route.connect].mergingReported([reported("https://192.168.1.10:8971")], activeRoute: .connect)
        let viaLearned = learned.mergingReported(
            [reported("https://192.168.1.10:8971"), reported("https://nvr.tail1234.ts.net")],
            activeRoute: learned[0]
        )
        #expect(viaLearned.allSatisfy { $0.credentialRouteID == "connect" })
    }

    @Test func `removing a route removes routes that borrow its credential`() {
        let routes = [Route.publicURL, Route.connect].mergingReported([reported("https://192.168.1.10:8971")], activeRoute: .connect)
        #expect(routes.count == 3)
        #expect(routes.removing("connect") == [Route.publicURL])
    }
}
