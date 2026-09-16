import XCTest
@testable import G9Core

private actor FakeExecutor: DisplayCommandExecutor {
    struct Call: Equatable { let value: UInt8 }
    private(set) var calls: [Call] = []
    private var scripted: [SwitchOutcome]
    private var index = 0

    init(outcomes: [SwitchOutcome]) { self.scripted = outcomes }

    func setInput(displayUUID: String, vcpFeature: UInt8, value: UInt8) async -> SwitchOutcome {
        calls.append(Call(value: value))
        let outcome = index < scripted.count ? scripted[index] : .transportCompleted
        index += 1
        return outcome
    }

    func listDisplays() async -> [ResolvedDisplay] { [] }
    func callValues() -> [UInt8] { calls.map { $0.value } }
}

final class CommandCoordinatorTests: XCTestCase {

    func test_staleRequestDropped() async {
        let exec = FakeExecutor(outcomes: [.transportCompleted, .transportCompleted])
        let c = CommandCoordinator(executor: exec, clock: FakeClock(), displayUUID: "U", vcpFeature: 96)
        await c.request(target: .mac, value: 7, generation: 5)      // newest = 5, executes
        let out = await c.request(target: .windows, value: 5, generation: 2) // stale
        XCTAssertEqual(out, .cancelled)
        let values = await exec.callValues()
        XCTAssertEqual(values, [7])                                  // value 5 never sent
    }

    func test_retryOnceOnTransportFailure() async {
        let exec = FakeExecutor(outcomes: [.transportFailed("boom"), .transportCompleted])
        let c = CommandCoordinator(executor: exec, clock: FakeClock(), displayUUID: "U", vcpFeature: 96)
        let out = await c.request(target: .windows, value: 5, generation: 1)
        XCTAssertEqual(out, .transportCompleted)
        let values = await exec.callValues()
        XCTAssertEqual(values, [5, 5])                               // one retry
    }

    func test_noRetryOnTimeout() async {
        let exec = FakeExecutor(outcomes: [.timedOut])
        let c = CommandCoordinator(executor: exec, clock: FakeClock(), displayUUID: "U", vcpFeature: 96)
        let out = await c.request(target: .windows, value: 5, generation: 1)
        XCTAssertEqual(out, .timedOut)
        let values = await exec.callValues()
        XCTAssertEqual(values, [5])                                  // no retry on timeout
    }

    func test_noDuplicateWriteAtSteadyState() async {
        let exec = FakeExecutor(outcomes: [.transportCompleted, .transportCompleted])
        let c = CommandCoordinator(executor: exec, clock: FakeClock(), displayUUID: "U", vcpFeature: 96)
        await c.request(target: .mac, value: 7, generation: 1)
        await c.request(target: .mac, value: 7, generation: 1)      // identical -> skipped
        let values = await exec.callValues()
        XCTAssertEqual(values, [7])
    }
}
