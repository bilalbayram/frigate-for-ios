import Foundation
@testable import IwaConnection

extension ServerIdentity {
    static let home = ServerIdentity(rawValue: "instance-home")
    static let neighbor = ServerIdentity(rawValue: "instance-neighbor")
}

extension Route {
    static let lan = direct("https://192.168.1.10:8971")
    static let lan2 = direct("https://10.0.0.5:8971")
    static let tailnet = direct("https://nvr.tail1234.ts.net")
    static let publicURL = direct("https://frigate.example.com")

    static func direct(_ string: String, source: Source = .saved, tailscale: Bool = false) -> Route {
        Route.direct(URL(string: string)!, source: source, confirmedTailscale: tailscale)!
    }
}

/// Deterministic generator so a failing seed reproduces exactly.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
