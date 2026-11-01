import Foundation
import Security
import Testing

@testable import FrigateAPI

struct ServerTrustTests {
    private struct Expected: Decodable {
        let publicKeySHA256: String
    }

    private func certificate() throws -> SecCertificate {
        let der = try Data(contentsOf: Fixtures.root.appending(path: "tls/test-p256.der"))
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    private func expectedHash() throws -> Data {
        let json = try Data(contentsOf: Fixtures.root.appending(path: "tls/test-p256.json"))
        let hex = try JSONDecoder().decode(Expected.self, from: json).publicKeySHA256
        return Data(
            stride(from: 0, to: hex.count, by: 2).map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
            })
    }

    private func trust() throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(try certificate(), SecPolicyCreateSSL(true, "iwa-test.invalid" as CFString), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test func `public key hash matches openssl`() throws {
        #expect(ServerTrust.publicKeySHA256(of: try certificate()) == (try expectedHash()))
    }

    @Test func `pinning accepts only the pinned key`() throws {
        #expect(ServerTrust.evaluate(try trust(), policy: .pinnedPublicKey(sha256: try expectedHash())))
        #expect(!ServerTrust.evaluate(try trust(), policy: .pinnedPublicKey(sha256: Data(repeating: 0, count: 32))))
    }

    @Test func `the system policy rejects a self-signed certificate`() throws {
        #expect(!ServerTrust.evaluate(try trust(), policy: .system))
    }
}
