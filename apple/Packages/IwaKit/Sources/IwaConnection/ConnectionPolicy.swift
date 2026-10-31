/// Timing for route selection and the connection supervisor.
///
/// Values come from T3 Code's client runtime (`driver.ts`, `supervisor.ts`), where they were tuned
/// against LAN, Tailscale DERP, VPN, and relay connections.
public enum ConnectionPolicy {
    /// Unauthenticated identity probe on every route.
    public static let probeTimeout: Duration = .milliseconds(2_500)
    /// One last probe on a route that never answered, before giving up on it.
    public static let patientProbeTimeout: Duration = .seconds(15)
    /// Shared head start for earlier routes before a silent one is skipped.
    public static let headStart: Duration = .milliseconds(500)
    /// How often a session on a worse route checks whether a better one works again.
    public static let betterRouteCheckInterval: Duration = .seconds(60)
    /// A better route that answered but then failed to connect isn't tried again for this long,
    /// so a flaky LAN can't bounce the connection.
    public static let failedUpgradeCooldown: Duration = .seconds(300)
    /// Upper bound for a route that keeps not answering.
    public static let maxSilentRouteBackoff: Duration = .seconds(1_800)
    public static let maxRetryDelay: Duration = .seconds(300)

    /// Delay before reconnect attempt `failures + 1`: exponential from 1 s, capped at five minutes,
    /// with the upper half jittered so a restarted server isn't hit by every client in the same second.
    ///
    /// - Parameter random: A value in `0...1`.
    public static func retryDelay(afterFailures failures: Int, random: Double) -> Duration {
        let ceiling = min(maxRetryDelay, .seconds(1) * power(of: 2, failures + 1))
        return ceiling / 2 + (ceiling / 2) * min(max(random, 0), 1)
    }

    /// How long to wait before checking a route that has been silent `failures` times in a row.
    public static func silentRouteBackoff(failures: Int) -> Duration {
        min(maxSilentRouteBackoff, betterRouteCheckInterval * power(of: 2, failures))
    }

    /// `base^exponent`, saturating at 2^20 so multiplying a `Duration` by it can't overflow.
    /// Every caller hits its cap long before that.
    private static func power(of base: Int, _ exponent: Int) -> Int {
        let limit = 1 << 20
        var result = 1
        for _ in 0..<max(exponent, 0) {
            result *= base
            if result >= limit { return limit }
        }
        return result
    }
}
