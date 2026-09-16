import XCTest
@testable import G9Core

final class SwitchPolicyTests: XCTestCase {

    private func makePolicy(_ mode: AutomationMode, _ clock: FakeClock) -> SwitchPolicy {
        var a = Configuration.g95ncDefault.automation
        a.mode = mode
        let p = SwitchPolicy(config: a, clock: clock)
        p.begin()
        return p
    }

    @discardableResult
    private func feedStableConnected(_ p: SwitchPolicy, _ clock: FakeClock) -> [PolicyDecision] {
        var out = p.handle(observation: ConnectionObservation(state: .connected, timestamp: clock.now))
        clock.advance(by: 1.0)   // arrival debounce = 1s
        out += p.handle(observation: ConnectionObservation(state: .connected, timestamp: clock.now))
        return out
    }

    @discardableResult
    private func feedStableDisconnected(_ p: SwitchPolicy, _ clock: FakeClock) -> [PolicyDecision] {
        var out = p.handle(observation: ConnectionObservation(state: .disconnected, timestamp: clock.now))
        clock.advance(by: 3.0)   // departure debounce = 3s
        out += p.handle(observation: ConnectionObservation(state: .disconnected, timestamp: clock.now))
        return out
    }

    // (a) startup while disconnected never switches
    func test_a_startupDisconnectedNeverSwitches() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        let d = feedStableDisconnected(p, clock)
        XCTAssertTrue(d.isEmpty)
        XCTAssertFalse(p.armed)
    }

    // (b) the first Mac connection arms but sends no command
    func test_b_firstMacConnectionArmsNoCommand() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        let d = feedStableConnected(p, clock)
        XCTAssertTrue(d.isEmpty)
        XCTAssertTrue(p.armed)
        XCTAssertEqual(p.state, .connected)
    }

    // (c) the next stable departure requests Windows in Follow both ways
    func test_c_departureRequestsWindows_inFollowBoth() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)
        clock.advance(by: 1)
        let dep = feedStableDisconnected(p, clock)
        XCTAssertEqual(dep.map { $0.target }, [.windows])
    }

    // (d) the next stable return requests Mac
    func test_d_returnRequestsMac() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)
        clock.advance(by: 1)
        feedStableDisconnected(p, clock)   // Windows
        clock.advance(by: 5)               // clear cooldown
        let ret = feedStableConnected(p, clock)
        XCTAssertEqual(ret.map { $0.target }, [.mac])
    }

    // (e) startup while already connected arms only after fresh stability, no command
    func test_e_startupAlreadyConnectedArmsNoCommand() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        // First observation alone must not arm (needs stability).
        let first = p.handle(observation: ConnectionObservation(state: .connected, timestamp: clock.now))
        XCTAssertTrue(first.isEmpty)
        XCTAssertFalse(p.armed)
        clock.advance(by: 1)
        let second = p.handle(observation: ConnectionObservation(state: .connected, timestamp: clock.now))
        XCTAssertTrue(second.isEmpty)
        XCTAssertTrue(p.armed)
    }

    // (f) restart, pause/resume, provider failure, and sleep/wake reset arming
    func test_f_lifecycleResetsArming() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)
        XCTAssertTrue(p.armed)

        p.pause()
        XCTAssertFalse(p.armed)
        p.resume()
        XCTAssertFalse(p.armed)

        feedStableConnected(p, clock)          // re-arm
        XCTAssertTrue(p.armed)

        _ = p.handle(lifecycle: .willSleep, at: clock.now)
        XCTAssertFalse(p.armed)
        _ = p.handle(lifecycle: .didWake, at: clock.now)
        clock.advance(by: 10)                  // resume settle
        _ = p.tick(now: clock.now)
        XCTAssertFalse(p.armed)
        XCTAssertEqual(p.state, .waitingForMac)
    }

    // (g) repeated disconnected observations after a reset cannot trigger until a new Mac connection
    func test_g_disconnectedAfterResetCannotTrigger() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)          // arm
        _ = p.handle(observation: ConnectionObservation(state: .unknown, timestamp: clock.now))
        XCTAssertFalse(p.armed)

        for _ in 0..<5 {
            let d = feedStableDisconnected(p, clock)
            XCTAssertTrue(d.isEmpty)
            XCTAssertFalse(p.armed)
        }

        clock.advance(by: 1)
        feedStableConnected(p, clock)          // re-arm, no command
        XCTAssertTrue(p.armed)
        clock.advance(by: 1)
        let dep = feedStableDisconnected(p, clock)
        XCTAssertEqual(dep.map { $0.target }, [.windows])
    }

    func test_returnToMac_noWindowsOnDeparture_macOnReturn() {
        let clock = FakeClock()
        let p = makePolicy(.returnToMac, clock)
        feedStableConnected(p, clock)          // arm
        clock.advance(by: 1)
        let dep = feedStableDisconnected(p, clock)
        XCTAssertTrue(dep.isEmpty)              // no Windows in returnToMac
        clock.advance(by: 1)
        let ret = feedStableConnected(p, clock)
        XCTAssertEqual(ret.map { $0.target }, [.mac])
    }

    func test_manual_neverActsAutomatically() {
        let clock = FakeClock()
        let p = makePolicy(.manual, clock)
        feedStableConnected(p, clock)          // arm
        clock.advance(by: 1)
        XCTAssertTrue(feedStableDisconnected(p, clock).isEmpty)
        clock.advance(by: 1)
        XCTAssertTrue(feedStableConnected(p, clock).isEmpty)
    }

    func test_interruptedDepartureDebounce_noCommand() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)          // arm
        // Disconnected for 1s only, then reconnect — must not accept departure.
        var d = p.handle(observation: ConnectionObservation(state: .disconnected, timestamp: clock.now))
        clock.advance(by: 1)
        d += p.handle(observation: ConnectionObservation(state: .connected, timestamp: clock.now))
        XCTAssertTrue(d.isEmpty)
        XCTAssertTrue(p.armed)
    }

    func test_unknownDisarmsAndCancelsPending() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)
        XCTAssertTrue(p.armed)
        _ = p.handle(observation: ConnectionObservation(state: .unknown, timestamp: clock.now, providerHealthy: false))
        XCTAssertFalse(p.armed)
        XCTAssertEqual(p.state, .waitingForMac)
    }

    func test_cooldownDefersOppositeTransition_thenApplies() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)          // arm
        clock.advance(by: 1)
        let dep = feedStableDisconnected(p, clock)   // Windows at T
        XCTAssertEqual(dep.map { $0.target }, [.windows])
        clock.advance(by: 1)
        let ret = feedStableConnected(p, clock)      // within cooldown -> deferred
        XCTAssertTrue(ret.isEmpty)
        clock.advance(by: 5)                         // past cooldown
        let applied = p.tick(now: clock.now)
        XCTAssertEqual(applied.map { $0.target }, [.mac])
    }

    func test_manualHoldoffBlocksAutomaticReversal() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)          // arm
        p.manualSwitch(to: .mac, at: clock.now)   // holdoff 10s
        clock.advance(by: 1)
        let dep = feedStableDisconnected(p, clock)   // Windows deferred by holdoff
        XCTAssertTrue(dep.isEmpty)
        XCTAssertTrue(p.tick(now: clock.now).isEmpty)   // still within holdoff
        clock.advance(by: 10)
        let applied = p.tick(now: clock.now)
        XCTAssertEqual(applied.map { $0.target }, [.windows])
    }

    func test_followBoth_twentyRoundTrips_noOscillation() {
        let clock = FakeClock()
        let p = makePolicy(.followBoth, clock)
        feedStableConnected(p, clock)          // arm
        var decisions: [PolicyDecision] = []
        for _ in 0..<20 {
            clock.advance(by: 6)               // clear cooldown before each transition
            decisions += feedStableDisconnected(p, clock)
            decisions += p.tick(now: clock.now)
            clock.advance(by: 6)
            decisions += feedStableConnected(p, clock)
            decisions += p.tick(now: clock.now)
        }
        let targets = decisions.map { $0.target }
        XCTAssertEqual(targets.count, 40)
        XCTAssertEqual(targets.last, .mac)              // ended connected -> Mac
        // Strict alternation windows, mac, windows, mac, ...
        for (i, t) in targets.enumerated() {
            XCTAssertEqual(t, i % 2 == 0 ? .windows : .mac)
        }
    }
}
