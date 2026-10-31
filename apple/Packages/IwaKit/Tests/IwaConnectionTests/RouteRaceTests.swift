import IwaConnection
import Testing

/// Records every action a race emits while a test feeds it events.
private struct Race {
    private var race: RouteRace
    private(set) var actions: [RouteRace.Action] = []

    init(_ routes: [Route]) {
        race = RouteRace(routes: routes, expected: .home)
        actions += race.start()
    }

    mutating func headStartEnds() { actions += race.headStartEnded() }
    mutating func probe(_ route: Route, _ result: RouteRace.ProbeResult) { actions += race.probeFinished(route.id, result) }
    mutating func connect(_ route: Route, _ result: RouteRace.ConnectResult) { actions += race.connectFinished(route.id, result) }

    var connects: [Route.ID] {
        actions.compactMap { if case .connect(let verified) = $0 { verified.route.id } else { nil } }
    }

    var patientProbes: [Route.ID] {
        actions.compactMap { if case .probe(let id, .patient) = $0 { id } else { nil } }
    }

    var outcome: RouteRace.Outcome? {
        actions.lazy.compactMap { if case .finish(let outcome) = $0 { outcome } else { nil } }.first
    }
}

struct RouteRaceTests {
    @Test func `probes every route without credentials first`() {
        let race = Race([.lan, .tailnet, .connect])
        #expect(race.actions == [.probe(Route.lan.id, .quick), .probe(Route.tailnet.id, .quick), .probe(Route.connect.id, .quick)])
    }

    @Test func `connects over the first route that answers before the head start`() {
        var race = Race([.lan, .connect])
        race.probe(.connect, .answered(.home))
        #expect(race.connects.isEmpty, "Connect must wait while LAN still has its head start")
        race.probe(.lan, .answered(.home))
        #expect(race.connects == [Route.lan.id])
        race.connect(.lan, .connected)
        #expect(race.outcome == .connected(Route.lan.id))
    }

    @Test func `falls through to a later route once the head start ends`() {
        var race = Race([.lan, .connect])
        race.probe(.connect, .answered(.home))
        race.headStartEnds()
        #expect(race.connects == [Route.connect.id])
    }

    @Test func `never connects to a route that answers as another server`() {
        var race = Race([.lan, .tailnet])
        race.probe(.lan, .answered(.neighbor))
        race.probe(.tailnet, .answered(.home))
        #expect(race.connects == [Route.tailnet.id])
        race.connect(.tailnet, .failed)
        #expect(race.patientProbes.isEmpty)
        #expect(race.outcome == .connectFailed)
    }

    @Test func `reports a mismatch when only another server answered`() {
        var race = Race([.lan])
        race.probe(.lan, .answered(.neighbor))
        #expect(race.connects.isEmpty)
        #expect(race.outcome == .identityMismatch)
    }

    @Test func `retries late answers before silent routes`() {
        var race = Race([.lan, .tailnet, .publicURL])
        race.headStartEnds()
        race.probe(.publicURL, .answered(.home))
        race.probe(.lan, .silent)
        #expect(race.connects.isEmpty, "Waits for every deferred probe to settle")
        race.probe(.tailnet, .silent)
        #expect(race.connects == [Route.publicURL.id])
        race.connect(.publicURL, .failed)
        #expect(race.patientProbes == [Route.lan.id])
    }

    @Test func `gives a silent route one patient probe before connecting`() {
        var race = Race([.lan])
        race.headStartEnds()
        race.probe(.lan, .silent)
        #expect(race.patientProbes == [Route.lan.id])
        #expect(race.connects.isEmpty)
        race.probe(.lan, .answered(.home))
        #expect(race.connects == [Route.lan.id])
    }

    @Test func `is unreachable when every route stays silent`() {
        var race = Race([.lan, .connect])
        race.headStartEnds()
        race.probe(.lan, .silent)
        race.probe(.connect, .silent)
        race.probe(.lan, .silent)
        race.probe(.connect, .silent)
        #expect(race.patientProbes == [Route.lan.id, Route.connect.id])
        #expect(race.outcome == .unreachable)
    }

    @Test func `an unsupported server stops the walk`() {
        var race = Race([.lan, .connect])
        race.probe(.lan, .answered(.home))
        race.probe(.connect, .answered(.home))
        race.connect(.lan, .unsupportedServer)
        #expect(race.connects == [Route.lan.id])
        #expect(race.outcome == .unsupportedServer)
    }

    @Test func `moves on after a failed connect`() {
        var race = Race([.lan, .connect])
        race.probe(.lan, .answered(.home))
        race.probe(.connect, .answered(.home))
        race.connect(.lan, .failed)
        #expect(race.connects == [Route.lan.id, Route.connect.id])
        race.connect(.connect, .connected)
        #expect(race.outcome == .connected(Route.connect.id))
    }

    @Test func `ignores events after it finishes`() {
        var race = Race([.lan, .connect])
        race.probe(.lan, .answered(.home))
        race.connect(.lan, .connected)
        let finished = race.actions
        race.probe(.connect, .answered(.home))
        race.headStartEnds()
        race.connect(.connect, .connected)
        #expect(race.actions == finished)
    }

    @Test func `finishes immediately with no routes`() {
        #expect(Race([]).outcome == .unreachable)
    }
}

/// Random routes, behaviors, and event orders. Every order the network could produce must keep the invariants.
struct RouteRacePropertyTests {
    private enum Behavior {
        case answers(ServerIdentity)
        /// Silent on the quick probe, answers the patient one.
        case answersSlowly(ServerIdentity)
        case silent

        var identity: ServerIdentity? {
            switch self {
            case .answers(let identity), .answersSlowly(let identity): identity
            case .silent: nil
            }
        }
    }

    private enum Pending: Equatable {
        case headStart
        case probe(Route.ID, RouteRace.ProbeUrgency)
        case connect(Route.ID)
    }

    @Test(arguments: 0..<2_000)
    func `keeps its invariants for any event order`(seed: UInt64) throws {
        var rng = SplitMix64(state: seed)
        let pool: [Route] = [.lan, .lan2, .tailnet, .publicURL, .connect]
        let routes = Array(pool.shuffled(using: &rng).prefix(Int.random(in: 1...pool.count, using: &rng)))
        var behavior: [Route.ID: Behavior] = [:]
        var connectResult: [Route.ID: RouteRace.ConnectResult] = [:]
        for route in routes {
            let identity: ServerIdentity = Int.random(in: 0..<5, using: &rng) == 0 ? .neighbor : .home
            behavior[route.id] = [.answers(identity), .answersSlowly(identity), .silent].randomElement(using: &rng)!
            connectResult[route.id] = [.connected, .connected, .failed, .failed, .unsupportedServer].randomElement(using: &rng)!
        }

        var race = RouteRace(routes: routes, expected: .home)
        var pending: [Pending] = [.headStart]
        var connected: [Route.ID] = []
        var patient: [Route.ID] = []
        var outcome: RouteRace.Outcome?

        func handle(_ actions: [RouteRace.Action]) {
            for action in actions {
                #expect(outcome == nil, "No actions after finish (seed \(seed))")
                switch action {
                case .probe(let id, let urgency):
                    if urgency == .patient {
                        #expect(!patient.contains(id), "One patient probe per route (seed \(seed))")
                        patient.append(id)
                    }
                    pending.append(.probe(id, urgency))
                case .connect(let verified):
                    let id = verified.route.id
                    #expect(verified.identity == .home)
                    #expect(behavior[id]?.identity == .home, "Credential sent to an unverified route (seed \(seed))")
                    #expect(!connected.contains(id), "Connected the same route twice (seed \(seed))")
                    #expect(!pending.contains { if case .connect = $0 { true } else { false } }, "Two connects at once (seed \(seed))")
                    connected.append(id)
                    pending.append(.connect(id))
                case .finish(let result):
                    outcome = result
                }
            }
        }

        handle(race.start())
        while !pending.isEmpty {
            let event = pending.remove(at: Int.random(in: 0..<pending.count, using: &rng))
            let before = outcome
            switch event {
            case .headStart:
                handle(race.headStartEnded())
            case .probe(let id, let urgency):
                let result: RouteRace.ProbeResult = switch (behavior[id]!, urgency) {
                case (.answers(let identity), _), (.answersSlowly(let identity), .patient): .answered(identity)
                case (.answersSlowly, .quick), (.silent, _): .silent
                }
                handle(race.probeFinished(id, result))
            case .connect(let id):
                handle(race.connectFinished(id, connectResult[id]!))
            }
            if before != nil { #expect(outcome == before) }
        }

        let final = try #require(outcome, "Race never finished (seed \(seed))")
        let homeRoutes = routes.filter { behavior[$0.id]?.identity == .home }.map(\.id)
        switch final {
        case .connected(let id):
            #expect(connectResult[id] == .connected)
            #expect(connected.last == id)
        case .unsupportedServer:
            #expect(connectResult[connected.last!] == .unsupportedServer)
        case .connectFailed, .identityMismatch, .unreachable:
            #expect(Set(connected) == Set(homeRoutes), "Gave up before trying every verified route (seed \(seed))")
            #expect(connected.allSatisfy { connectResult[$0] == .failed })
            if final == .unreachable { #expect(routes.allSatisfy { behavior[$0.id]?.identity == nil }) }
            if final == .identityMismatch { #expect(homeRoutes.isEmpty) }
        }
    }
}
