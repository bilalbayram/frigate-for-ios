import IwaConnection
import Testing

struct ConnectionPolicyTests {
    @Test(arguments: [
        (0, 0.0, Duration.seconds(1)),
        (0, 1.0, .seconds(2)),
        (1, 0.0, .seconds(2)),
        (1, 1.0, .seconds(4)),
        (7, 0.0, .seconds(128)),
        (8, 0.0, .seconds(150)),
        (8, 1.0, .seconds(300)),
        (10_000, 1.0, .seconds(300)),
        (0, 7.0, .seconds(2)),
    ])
    func `retry delay doubles with jitter in the upper half, capped at five minutes`(failures: Int, random: Double, expected: Duration) {
        #expect(ConnectionPolicy.retryDelay(afterFailures: failures, random: random) == expected)
    }

    @Test(arguments: [
        (0, Duration.seconds(60)),
        (1, .seconds(120)),
        (4, .seconds(960)),
        (5, .seconds(1_800)),
        (10_000, .seconds(1_800)),
    ])
    func `silent routes are checked half as often each time, up to every 30 minutes`(failures: Int, expected: Duration) {
        #expect(ConnectionPolicy.silentRouteBackoff(failures: failures) == expected)
    }
}
