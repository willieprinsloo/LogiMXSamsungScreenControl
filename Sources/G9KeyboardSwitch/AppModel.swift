import AppKit
import Foundation
import OSLog
import G9Core

private let log = Logger(subsystem: "solutions.metalogix.g9switch", category: "policy")

/// Owns the policy, hardware services, and command coordinator; runs the poll
/// loop; and publishes menu-bar status. Main-actor isolated.
@MainActor
final class AppModel: ObservableObject {
    // Published status for the menu bar.
    @Published private(set) var keyboardStatus: String = "Detection unavailable"
    @Published private(set) var monitorName: String = "—"
    @Published private(set) var lastRequestedInput: String = "—"
    @Published private(set) var automationStatus: String = "Manual"
    @Published var mode: AutomationMode = .manual { didSet { applyModeChange() } }
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var helperAvailable: Bool = true
    @Published private(set) var lastRecoveryNote: String? = nil
    /// SF Symbol name for the menu-bar icon; reflects live status.
    @Published private(set) var menuBarSymbol: String = "display.2"

    private var needsConfigSave = false

    private let store: ConfigurationStore
    private var config: Configuration
    private let policy: SwitchPolicy
    private let clock = SystemClock()
    private let diagnostics: DiagnosticsStore

    private let displayController: DisplayController?
    private var provider: SystemProfilerKeyboardProvider
    private var coordinator: CommandCoordinator?
    private let lifecycle = LifecycleMonitor()

    private var displayUUID: String?
    private var lastObservation: ConnectionObservation?
    private var lastRequestedTarget: TargetComputer?
    private var pollTask: Task<Void, Never>?

    init() {
        // Configuration.
        let dir = AppModel.supportDirectory()
        let store = ConfigurationStore(directory: dir)
        self.store = store
        self.config = (try? store.load()) ?? .g95ncDefault

        // This monitor can't be switched back to the Mac from the Mac (see README):
        // coerce any saved return-capable mode to the honest Mac-side mode.
        if self.config.automation.mode == .returnToMac || self.config.automation.mode == .followBoth {
            self.config.automation.mode = .followToWindows
            self.needsConfigSave = true
        }

        self.diagnostics = DiagnosticsStore(clock: SystemClock())
        self.policy = SwitchPolicy(config: self.config.automation, clock: SystemClock())
        self.provider = SystemProfilerKeyboardProvider(
            deviceName: config.keyboard.name,
            localIdentifier: config.keyboard.localIdentifier
        )

        if let url = ResourceLocator.m1ddcURL() {
            self.displayController = DisplayController(executableURL: url)
        } else {
            self.displayController = nil
        }

        self.mode = config.automation.mode
        self.monitorName = config.monitor.model
        self.helperAvailable = (displayController != nil)
    }

    // MARK: Lifecycle

    func start() {
        lifecycle.onEvent = { [weak self] event in
            guard let self else { return }
            log.notice("lifecycle: \(String(describing: event), privacy: .public)")
            _ = self.policy.handle(lifecycle: event, at: Date())
            self.updateStatus()
        }
        lifecycle.start()
        policy.begin()
        if needsConfigSave {
            try? store.save(config)   // persist the coerced mode so the file stays honest
            needsConfigSave = false
        }
        Task { await self.resolveDisplay() }
        startPolling()
        updateStatus()
    }

    private func resolveDisplay() async {
        guard let displayController else { return }
        let displays = await displayController.listDisplays()
        // Prefer saved UUID; else the single connected display; else first match by name.
        let resolved: ResolvedDisplay?
        if let saved = config.monitor.displayUUID {
            resolved = displays.first { $0.uuid == saved } ?? (displays.count == 1 ? displays.first : nil)
        } else if displays.count == 1 {
            resolved = displays.first
        } else {
            resolved = displays.first { $0.name == config.monitor.model }
        }
        if let r = resolved {
            displayUUID = r.uuid
            monitorName = r.name
            coordinator = CommandCoordinator(
                executor: displayController,
                clock: clock,
                displayUUID: r.uuid,
                vcpFeature: config.monitor.vcpFeature
            )
            log.notice("resolved display '\(r.name, privacy: .public)' uuid=\(r.uuid, privacy: .public) (list size=\(displays.count))")
        } else {
            log.error("no display resolved from list of \(displays.count)")
        }
        updateStatus()
    }

    private func startPolling() {
        let interval = config.automation.pollIntervalSeconds
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let prev = self.lastObservation
                let prevArmed = self.policy.armed
                let obs = await self.provider.poll()
                self.lastObservation = obs
                // Log observation only when it changes, to keep the trace readable.
                if prev?.state != obs.state || prev?.providerHealthy != obs.providerHealthy {
                    log.notice("obs: \(String(describing: obs.state), privacy: .public) healthy=\(obs.providerHealthy) | armed=\(self.policy.armed) state=\(String(describing: self.policy.state), privacy: .public)")
                }
                var decisions = self.policy.handle(observation: obs)
                decisions += self.policy.tick(now: Date())
                if self.policy.armed != prevArmed {
                    log.notice("armed -> \(self.policy.armed) (state=\(String(describing: self.policy.state), privacy: .public))")
                }
                for d in decisions {
                    log.notice("decision: \(d.target.rawValue, privacy: .public) gen=\(d.generation) reason=\(d.reason, privacy: .public)")
                    await self.apply(d)
                }
                self.updateStatus()
                try? await Task.sleep(nanoseconds: UInt64(max(0.2, interval) * 1_000_000_000))
            }
        }
    }

    // MARK: Actions

    func switchToMac() { Task { await performManual(.mac) } }
    func switchToWindows() { Task { await performManual(.windows) } }

    func pauseAutomation() {
        policy.pause()
        isPaused = true
        updateStatus()
    }

    func resumeAutomation() {
        policy.resume()
        isPaused = false
        updateStatus()
    }

    func quit() { NSApplication.shared.terminate(nil) }

    private func performManual(_ target: TargetComputer) async {
        if coordinator == nil { await resolveDisplay() }
        guard let coordinator else {
            lastRecoveryNote = "Display not resolved — open Settings to select the monitor."
            return
        }
        if target == .windows {
            lastRecoveryNote = "Switching to Windows blacks out this Mac. To return, press the monitor's source button and select HDMI 3, or use Switch to Mac from another device."
        } else {
            lastRecoveryNote = nil
        }
        policy.manualSwitch(to: target, at: Date())
        let value = inputValue(for: target)
        lastRequestedTarget = target
        updateStatus()
        let outcome = await coordinator.request(target: target, value: value, generation: policy.currentGeneration)
        log.notice("manual outcome: \(target.rawValue, privacy: .public) value=\(value) -> \(String(describing: outcome), privacy: .public)")
        diagnostics.record(DiagnosticEvent(
            type: "manual-switch", localTime: Date(),
            targetInput: target.rawValue, transportResult: String(describing: outcome)
        ))
        updateStatus()
    }

    private func apply(_ decision: PolicyDecision) async {
        guard let coordinator else {
            log.error("apply: no coordinator (display unresolved) for \(decision.target.rawValue, privacy: .public)")
            return
        }
        let value = inputValue(for: decision.target)
        lastRequestedTarget = decision.target
        updateStatus()
        let outcome = await coordinator.request(target: decision.target, value: value, generation: decision.generation)
        log.notice("auto outcome: \(decision.target.rawValue, privacy: .public) value=\(value) gen=\(decision.generation) -> \(String(describing: outcome), privacy: .public)")
        diagnostics.record(DiagnosticEvent(
            type: "auto-switch", localTime: Date(),
            targetInput: decision.target.rawValue, requestID: decision.generation,
            transportResult: String(describing: outcome)
        ))
    }

    private func applyModeChange() {
        guard mode != policy.mode else { return }
        log.notice("mode -> \(self.mode.rawValue, privacy: .public) (disarms; re-arm needs a stable Mac connection)")
        policy.mode = mode
        config.automation.mode = mode
        try? store.save(config)
        updateStatus()
    }

    // MARK: Helpers

    private func inputValue(for target: TargetComputer) -> UInt8 {
        target == .mac ? config.monitor.inputs.mac.value : config.monitor.inputs.windows.value
    }

    private func updateStatus() {
        // Keyboard line from the last observation.
        if let obs = lastObservation {
            switch (obs.state, obs.providerHealthy) {
            case (_, false): keyboardStatus = "Detection unavailable"
            case (.connected, true): keyboardStatus = "Connected to Mac"
            case (.disconnected, true): keyboardStatus = "Disconnected"
            case (.unknown, true): keyboardStatus = "Unknown"
            }
        } else {
            keyboardStatus = "Detecting…"
        }

        // Automation status line.
        if isPaused {
            automationStatus = "Paused"
        } else if lastObservation?.providerHealthy == false {
            automationStatus = "Detection unavailable"
        } else if displayUUID == nil {
            automationStatus = "Display unavailable"
        } else {
            switch policy.state {
            case .suspended: automationStatus = "Waiting for stable connection"
            case .waitingForMac, .initializing:
                automationStatus = policy.armed ? "Armed and monitoring" : "Waiting for keyboard to connect to Mac"
            default:
                automationStatus = policy.armed ? "Armed and monitoring" : "Waiting for keyboard to connect to Mac"
            }
        }

        // Menu-bar icon reflects live status.
        if isPaused {
            menuBarSymbol = "pause.circle"
        } else if lastObservation?.providerHealthy == false || displayUUID == nil {
            menuBarSymbol = "display.trianglebadge.exclamationmark"
        } else {
            menuBarSymbol = "display.2"
        }

        // Last requested input.
        if let t = lastRequestedTarget {
            let profile = t == .mac ? config.monitor.inputs.mac : config.monitor.inputs.windows
            lastRequestedInput = "\(t == .mac ? "Mac" : "Windows") · \(profile.label)"
        } else {
            lastRequestedInput = "—"
        }
    }

    private static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("G9KeyboardSwitch", isDirectory: true)
    }
}
