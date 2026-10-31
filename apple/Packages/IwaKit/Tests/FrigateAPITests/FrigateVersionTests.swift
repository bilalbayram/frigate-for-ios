import FrigateAPI
import Testing

struct FrigateVersionTests {
    @Test(arguments: [
        ("0.16.2", FrigateVersion(major: 0, minor: 16, patch: 2)),
        ("0.16.2-4d58206", FrigateVersion(major: 0, minor: 16, patch: 2, build: "4d58206")),
        ("v0.17.0-beta1", FrigateVersion(major: 0, minor: 17, patch: 0, build: "beta1")),
        ("0.15", FrigateVersion(major: 0, minor: 15)),
        (" 0.16.0\n", FrigateVersion(major: 0, minor: 16)),
    ])
    func `parses Frigate version strings`(input: String, expected: FrigateVersion) throws {
        let version = try #require(FrigateVersion(input))
        #expect(version == expected)
    }

    @Test(arguments: ["", "dev", "0", "0.x.1", "0.16.2.1", "0..1"])
    func `rejects malformed versions`(input: String) {
        #expect(FrigateVersion(input) == nil)
    }

    @Test func `build suffix does not affect ordering`() throws {
        let a = try #require(FrigateVersion("0.16.2-aaaa"))
        let b = try #require(FrigateVersion("0.16.2-bbbb"))
        #expect(!(a < b) && !(b < a))
        #expect(try #require(FrigateVersion("0.16.10")) > b)
    }
}

struct FrigateSupportPolicyTests {
    let policy = FrigateSupportPolicy(current: FrigateVersion(major: 0, minor: 17, patch: 3))

    @Test(arguments: ["0.17.0", "0.17.9-abc", "0.16.0", "0.16.4"])
    func `supports current and previous minor`(input: String) throws {
        #expect(policy.support(for: try #require(FrigateVersion(input))) == .supported)
    }

    @Test func `flags versions older than the previous minor`() throws {
        let support = policy.support(for: try #require(FrigateVersion("0.15.9")))
        #expect(support == .tooOld(minimum: FrigateVersion(major: 0, minor: 16)))
    }

    @Test func `flags versions newer than tested`() throws {
        #expect(policy.support(for: try #require(FrigateVersion("0.18.0-beta1"))) == .newerThanTested)
    }
}
