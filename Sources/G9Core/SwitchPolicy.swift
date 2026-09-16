import Foundation

/// The pure switching brain. No hardware calls. Deterministic given observations,
/// lifecycle events, and the injected clock.
///
/// Mandatory Mac-first activation gate (spec §9): starts unarmed; the first
/// stable Mac connection arms WITHOUT emitting a command; only a departure from
/// an armed `Connected` state can auto-request Windows; only a return after an
/// accepted armed departure can auto-request Mac. The armed flag lives in memory
/// only — restart, pause, provider fault, or any lifecycle suspension disarms.
public final class SwitchPolicy {
    private let config: AutomationConfig
    private let clock: Clock

    public private(set) var state: PolicyState = .initializing
    public private(set) var armed: Bool = false

    /// The current generation counter. Manual actions read this after
    /// `manualSwitch(...)` (which bumps it) to tag their command so it
    /// supersedes any queued automatic request.
    public var currentGeneration: Int { generation }

    /// Changing the mode disarms and cancels pending actions.
    public var mode: AutomationMode {
        didSet {
            guard mode != oldValue else { return }
            disarmAndReset()
        }
    }

    // MARK: Internal bookkeeping
    private var enabled = false
    private var paused = false
    private var hardSuspended = false
    private var settleUntil: Date?
    private var holdoffUntil: Date?
    private var lastAutomaticCommandAt: Date?
    private var deferredTarget: TargetComputer?

    private var accumulatingState: ConnectionState?
    private var accumulatingSince: Date?
    private var generation = 0

    public init(config: AutomationConfig, clock: Clock) {
        self.config = config
        self.clock = clock
        self.mode = config.mode   // setting in init does not trigger didSet
    }

    // MARK: Enable / pause / resume

    /// Enable automation processing. Enters `waitingForMac` (still unarmed).
    public func begin() {
        enabled = true
        if state == .initializing || state == .suspended {
            state = .waitingForMac
        }
    }

    public func pause() {
        paused = true
        cancelPending()
        armed = false
        state = .suspended
        clearAccumulation()
    }

    public func resume() {
        paused = false
        hardSuspended = false
        settleUntil = nil
        cancelPending()
        armed = false
        state = enabled ? .waitingForMac : .initializing
        clearAccumulation()
    }

    // MARK: Keyboard observations

    public func handle(observation obs: ConnectionObservation) -> [PolicyDecision] {
        let now = obs.timestamp

        // Provider fault / unknown => disarm, suspend detection, cancel pending.
        if !obs.providerHealthy || obs.state == .unknown {
            return enterUnknown()
        }

        // While lifecycle-suspended or settling, ignore observations.
        if isSuspended(at: now) { return [] }
        guard enabled else { return [] }

        // Accumulate consecutive same-state observations.
        if accumulatingState != obs.state {
            accumulatingState = obs.state
            accumulatingSince = now
        }
        let elapsed = now.timeIntervalSince(accumulatingSince ?? now)

        switch obs.state {
        case .connected:
            if elapsed >= config.arrivalDebounceSeconds {
                return handleStableConnected(at: now)
            }
            reflectPending(.connected)
        case .disconnected:
            if elapsed >= config.departureDebounceSeconds {
                return handleStableDisconnected(at: now)
            }
            reflectPending(.disconnected)
        case .unknown:
            break
        }
        return []
    }

    private func handleStableConnected(at now: Date) -> [PolicyDecision] {
        if !armed {
            // First stable Mac connection: arm without issuing a command.
            armed = true
            state = .connected
            return []
        }
        let wasReturn = (state == .disconnected || state == .arrivalPending)
        state = .connected
        if wasReturn, mode == .returnToMac || mode == .followBoth {
            return emit(target: .mac, at: now, reason: "stable return to Mac")
        }
        return []
    }

    private func handleStableDisconnected(at now: Date) -> [PolicyDecision] {
        guard armed else {
            // Never switch on a disconnect before the session is armed.
            state = .waitingForMac
            return []
        }
        let wasDeparture = (state == .connected || state == .departurePending)
        state = .disconnected
        if wasDeparture, mode == .followBoth {
            return emit(target: .windows, at: now, reason: "stable departure to Windows")
        }
        return []
    }

    private func reflectPending(_ s: ConnectionState) {
        switch s {
        case .connected:
            if state == .disconnected { state = .arrivalPending }
        case .disconnected:
            if state == .connected { state = .departurePending }
            else if !armed { state = .waitingForMac }
        case .unknown:
            break
        }
    }

    // MARK: Lifecycle

    public func handle(lifecycle event: LifecycleEvent, at now: Date) -> [PolicyDecision] {
        switch event {
        case .willSleep, .bluetoothUnavailable, .displayDisconnected:
            hardSuspend()
        case .screensDidLock:
            if config.pauseWhenLocked { hardSuspend() }
        case .didWake, .bluetoothAvailable, .displayReconnected, .screensDidUnlock:
            beginSettling(at: now)
        }
        return []
    }

    // MARK: Manual override

    /// A manual switch cancels pending automation and starts a holdoff to
    /// prevent an immediate automatic reversal. Does not change armed state.
    public func manualSwitch(to target: TargetComputer, at now: Date) {
        cancelPending()
        holdoffUntil = now.addingTimeInterval(config.manualHoldoffSeconds)
        deferredTarget = nil
    }

    // MARK: Time-based progression

    /// Call each poll tick. Handles settle expiry (re-baseline) and applying a
    /// deferred action once cooldown/holdoff clear.
    public func tick(now: Date) -> [PolicyDecision] {
        if let until = settleUntil, now >= until {
            settleUntil = nil
            if !paused && !hardSuspended {
                // Re-baseline without replaying a departure from the outage.
                armed = false
                state = .waitingForMac
                clearAccumulation()
            }
        }

        if let target = deferredTarget {
            if isSuspended(at: now) || !armed || !enabled {
                deferredTarget = nil
                return []
            }
            let cooldownOK = lastAutomaticCommandAt.map { now.timeIntervalSince($0) >= config.cooldownSeconds } ?? true
            let holdoffOK = holdoffUntil.map { now >= $0 } ?? true
            if cooldownOK && holdoffOK {
                return emit(target: target, at: now, reason: "deferred")
            }
        }
        return []
    }

    // MARK: Emission with cooldown / holdoff

    private func emit(target: TargetComputer, at now: Date, reason: String) -> [PolicyDecision] {
        if let last = lastAutomaticCommandAt, now.timeIntervalSince(last) < config.cooldownSeconds {
            deferredTarget = target   // keep only the newest eligible desired action
            return []
        }
        if let until = holdoffUntil, now < until {
            deferredTarget = target
            return []
        }
        generation += 1
        lastAutomaticCommandAt = now
        deferredTarget = nil
        return [PolicyDecision(target: target, generation: generation, reason: reason)]
    }

    // MARK: Helpers

    private func enterUnknown() -> [PolicyDecision] {
        cancelPending()
        armed = false
        state = .waitingForMac
        clearAccumulation()
        return []
    }

    private func hardSuspend() {
        cancelPending()
        armed = false
        hardSuspended = true
        settleUntil = nil
        state = .suspended
        clearAccumulation()
    }

    private func beginSettling(at now: Date) {
        hardSuspended = false
        cancelPending()
        armed = false
        settleUntil = now.addingTimeInterval(config.resumeSettleSeconds)
        state = .suspended
        clearAccumulation()
    }

    private func isSuspended(at now: Date) -> Bool {
        if paused || hardSuspended { return true }
        if let s = settleUntil, now < s { return true }
        return false
    }

    private func cancelPending() {
        deferredTarget = nil
        generation += 1
    }

    private func disarmAndReset() {
        armed = false
        cancelPending()
        state = enabled ? .waitingForMac : .initializing
        clearAccumulation()
    }

    private func clearAccumulation() {
        accumulatingState = nil
        accumulatingSince = nil
    }
}
