import Foundation

/// A Frigate release version as reported by `GET /api/version`, e.g. `0.16.2-4d58206`.
public struct FrigateVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Build suffix after the first `-`, such as a commit hash or `beta1`.
    public let build: String?

    public init(major: Int, minor: Int, patch: Int = 0, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
    }

    /// Parses `0.16.2`, `0.16.2-4d58206`, or `v0.17.0-beta1`. Returns `nil` for anything else.
    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" { text = text.dropFirst() }

        let parts = text.split(separator: "-", maxSplits: 1)
        guard let numbers = parts.first else { return nil }
        let components = numbers.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count) else { return nil }

        let values = components.map { Int($0) }
        guard let major = values[0], let minor = values[1] else { return nil }
        let patch: Int
        if components.count == 3 {
            guard let value = values[2] else { return nil }
            patch = value
        } else {
            patch = 0
        }

        self.init(
            major: major,
            minor: minor,
            patch: patch,
            build: parts.count == 2 ? String(parts[1]) : nil
        )
    }

    /// The `major.minor` release line this version belongs to.
    public var releaseLine: FrigateVersion { FrigateVersion(major: major, minor: minor) }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        return build.map { "\(base)-\($0)" } ?? base
    }

    /// Orders by release number only; build suffixes don't affect ordering.
    public static func < (lhs: FrigateVersion, rhs: FrigateVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Iwa supports the current stable Frigate minor release and the one before it.
public struct FrigateSupportPolicy: Sendable, Hashable {
    /// The newest stable release line Iwa is tested against.
    public let current: FrigateVersion

    public init(current: FrigateVersion) {
        self.current = current.releaseLine
    }

    public enum Support: Sendable, Hashable {
        case supported
        /// Older than the previous minor release; the user should update Frigate.
        case tooOld(minimum: FrigateVersion)
        /// Newer than the release Iwa was built against. Usually works; features are gated per server.
        case newerThanTested
    }

    public var minimum: FrigateVersion {
        FrigateVersion(major: current.major, minor: max(current.minor - 1, 0))
    }

    public func support(for version: FrigateVersion) -> Support {
        let line = version.releaseLine
        if line < minimum { return .tooOld(minimum: minimum) }
        if line > current { return .newerThanTested }
        return .supported
    }
}

extension FrigateSupportPolicy {
    /// The release line Iwa is built and tested against (fixtures in `fixtures/frigate/`).
    public static let iwa = FrigateSupportPolicy(current: FrigateVersion(major: 0, minor: 18))
}
