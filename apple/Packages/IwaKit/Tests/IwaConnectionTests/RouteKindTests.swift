import IwaConnection
import Testing

struct RouteKindTests {
    @Test(arguments: [
        ("192.168.1.10", RouteKind.lan),
        ("10.0.0.42", .lan),
        ("172.20.1.1", .lan),
        ("169.254.10.1", .lan),
        ("frigate.local", .lan),
        ("nvr", .lan),
        ("frigate.home.arpa", .lan),
        ("[fe80::1%en0]", .lan),
        ("fd12:3456::1", .lan),
        ("nvr.tail1234.ts.net", .tailnet),
        ("NVR.Tail1234.TS.NET.", .tailnet),
        ("[fd7a:115c:a1e0::1]", .tailnet),
        ("100.101.102.103", .vpn),
        ("100.64.0.1", .vpn),
        ("100.128.0.1", .public),
        ("172.32.0.1", .public),
        ("frigate.example.com", .public),
        ("8.8.8.8", .public),
        ("2001:db8::1", .public),
    ])
    func `classifies hosts`(host: String, expected: RouteKind) {
        #expect(RouteKind.classify(host: host) == expected)
    }

    @Test func `confirmed Tailscale overrides shared address space`() {
        #expect(RouteKind.classify(host: "100.101.102.103", confirmedTailscale: true) == .tailnet)
    }

    @Test func `inserts by rank and keeps user order within a rank`() {
        let routes: [RouteKind] = [.lan, .vpn, .public, .connect]
        #expect(insertingByRank(.tailnet, into: routes) { $0 } == [.lan, .vpn, .tailnet, .public, .connect])
        #expect(insertingByRank(.lan, into: routes) { $0 } == [.lan, .lan, .vpn, .public, .connect])
        #expect(insertingByRank(.connect, into: []) { $0 } == [.connect])
    }
}
