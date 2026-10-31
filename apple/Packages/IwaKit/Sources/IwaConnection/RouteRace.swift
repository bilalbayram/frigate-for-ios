/// Decides which route to connect over. It does no I/O and keeps no clock: the caller runs its
/// actions and feeds back results, which makes every timing order a deterministic test.
///
/// Adapted from T3 Code's `connectOverRoutes` (`packages/client-runtime/src/connection/driver.ts`):
/// 1. Probe every route at once, without credentials.
/// 2. Walk routes in order. Routes still silent when the shared head start ends are deferred,
///    so leaving home falls through to a later route quickly.
/// 3. Retry deferred routes, those that answered late first.
/// 4. An unsupported server stops the walk: it's the same server on every route.
///
/// Unlike T3, a route is only connected after its probe answered with the expected identity.
/// A route that never answered gets one patient probe instead of a credentialed attempt.
public struct RouteRace: Sendable {
    public enum ProbeUrgency: Sendable, Hashable {
        /// Run with `ConnectionPolicy.probeTimeout`.
        case quick
        /// Run with `ConnectionPolicy.patientProbeTimeout`.
        case patient
    }

    public enum ProbeResult: Sendable, Hashable {
        case answered(ServerIdentity)
        /// Timed out, refused, or failed TLS.
        case silent
    }

    public enum ConnectResult: Sendable, Hashable {
        case connected
        case failed
        case unsupportedServer
    }

    public enum Action: Sendable, Hashable {
        case probe(Route.ID, ProbeUrgency)
        case connect(VerifiedRoute)
        /// The race is over. Cancel any probes still running.
        case finish(Outcome)
    }

    public enum Outcome: Sendable, Hashable {
        case connected(Route.ID)
        case unsupportedServer
        /// At least one connect attempt failed and none succeeded.
        case connectFailed
        /// Something answered as a different server, and nothing else connected.
        case identityMismatch
        case unreachable
    }

    private enum ProbeState: Hashable {
        case pending
        case answered(ServerIdentity)
        case silent
    }

    private enum InFlight: Hashable {
        case connect(Route.ID)
        case patientProbe(Route.ID)
    }

    public let routes: [Route]
    public let expected: ServerIdentity

    private var probes: [Route.ID: ProbeState] = [:]
    private var isPastHeadStart = false
    private var cursor = 0
    private var deferred: [Route.ID] = []
    private var retryQueue: [Route.ID]?
    private var inFlight: InFlight?
    private var sawMismatch = false
    private var sawConnectFailure = false
    private var isFinished = false

    public init(routes: [Route], expected: ServerIdentity) {
        self.routes = routes
        self.expected = expected
    }

    /// Starts quick probes on every route. The caller then reports `headStartEnded()` after
    /// `ConnectionPolicy.headStart`, and each probe's result as it arrives.
    public mutating func start() -> [Action] {
        guard probes.isEmpty, !isFinished else { return [] }
        if routes.isEmpty { return finish(.unreachable) }
        for route in routes { probes[route.id] = .pending }
        return routes.map { .probe($0.id, .quick) } + advance()
    }

    public mutating func headStartEnded() -> [Action] {
        guard !isPastHeadStart else { return [] }
        isPastHeadStart = true
        return advance()
    }

    public mutating func probeFinished(_ id: Route.ID, _ result: ProbeResult) -> [Action] {
        guard !isFinished else { return [] }
        let state: ProbeState = switch result {
        case .answered(let identity): .answered(identity)
        case .silent: .silent
        }
        if inFlight == .patientProbe(id) {
            inFlight = nil
            probes[id] = state
            if state == .answered(expected) { return attemptConnect(id) }
            if case .answered = state { sawMismatch = true }
            return advance()
        }
        guard probes[id] == .pending else { return [] }
        probes[id] = state
        return advance()
    }

    public mutating func connectFinished(_ id: Route.ID, _ result: ConnectResult) -> [Action] {
        guard !isFinished, inFlight == .connect(id) else { return [] }
        inFlight = nil
        switch result {
        case .connected: return finish(.connected(id))
        case .unsupportedServer: return finish(.unsupportedServer)
        case .failed:
            sawConnectFailure = true
            return advance()
        }
    }

    private mutating func advance() -> [Action] {
        guard !isFinished, inFlight == nil else { return [] }

        if retryQueue == nil {
            while cursor < routes.count {
                let id = routes[cursor].id
                switch probes[id] {
                case .answered(let identity) where identity == expected:
                    cursor += 1
                    return attemptConnect(id)
                case .answered:
                    sawMismatch = true
                case .silent:
                    deferred.append(id)
                case .pending, nil:
                    guard isPastHeadStart else { return [] }
                    deferred.append(id)
                }
                cursor += 1
            }
            if deferred.contains(where: { probes[$0] == .pending }) { return [] }
            let lateAnswers = deferred.filter { probes[$0] != .silent }
            retryQueue = lateAnswers + deferred.filter { probes[$0] == .silent }
        }

        while let id = retryQueue?.first {
            retryQueue?.removeFirst()
            switch probes[id] {
            case .answered(let identity) where identity == expected:
                return attemptConnect(id)
            case .answered:
                sawMismatch = true
            case .silent:
                probes[id] = .pending
                inFlight = .patientProbe(id)
                return [.probe(id, .patient)]
            case .pending, nil:
                assertionFailure("Deferred probes settle before the retry pass")
            }
        }

        if sawConnectFailure { return finish(.connectFailed) }
        return finish(sawMismatch ? .identityMismatch : .unreachable)
    }

    private mutating func attemptConnect(_ id: Route.ID) -> [Action] {
        guard let route = routes.first(where: { $0.id == id }) else { return advance() }
        inFlight = .connect(id)
        return [.connect(VerifiedRoute(route: route, identity: expected))]
    }

    private mutating func finish(_ outcome: Outcome) -> [Action] {
        isFinished = true
        return [.finish(outcome)]
    }
}
