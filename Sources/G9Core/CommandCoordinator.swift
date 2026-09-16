import Foundation

/// Serializes display writes. Coalesces to the newest request, drops requests
/// whose generation is stale before executing, avoids duplicate steady-state
/// writes, and retries exactly once on an explicit transport failure.
public actor CommandCoordinator {
    private let executor: DisplayCommandExecutor
    private let clock: Clock
    private let displayUUID: String
    private let vcpFeature: UInt8

    private var newestGeneration = 0
    private var lastApplied: (value: UInt8, generation: Int)?
    private var outcomes: [SwitchOutcome] = []

    public init(executor: DisplayCommandExecutor, clock: Clock, displayUUID: String, vcpFeature: UInt8) {
        self.executor = executor
        self.clock = clock
        self.displayUUID = displayUUID
        self.vcpFeature = vcpFeature
    }

    public var lastOutcome: SwitchOutcome? { outcomes.last }
    public func currentGeneration() -> Int { newestGeneration }
    public func recordedOutcomes() -> [SwitchOutcome] { outcomes }

    /// Request a monitor-input write. `generation` tags the policy decision;
    /// a request older than the newest generation observed is discarded.
    @discardableResult
    public func request(target: TargetComputer, value: UInt8, generation: Int) async -> SwitchOutcome {
        if generation > newestGeneration { newestGeneration = generation }

        // Stale: a newer decision has superseded this one.
        guard generation >= newestGeneration else {
            outcomes.append(.cancelled)
            return .cancelled
        }

        // Duplicate steady-state write: same value already applied for a
        // current-or-newer generation — skip.
        if let applied = lastApplied, applied.value == value, applied.generation >= generation {
            return .transportCompleted
        }

        var outcome = await executor.setInput(displayUUID: displayUUID, vcpFeature: vcpFeature, value: value)

        // Retry once only on an explicit transport failure, and only if this
        // request is still the current one.
        if case .transportFailed = outcome, generation >= newestGeneration {
            outcome = await executor.setInput(displayUUID: displayUUID, vcpFeature: vcpFeature, value: value)
        }

        if outcome == .transportCompleted {
            lastApplied = (value, generation)
        }
        outcomes.append(outcome)
        return outcome
    }
}
