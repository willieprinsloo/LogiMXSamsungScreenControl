import Foundation

/// Keyboard connection state as observed by a provider.
/// `unknown` is a first-class value: query failure, malformed data, or device
/// absent from both lists MUST map to `.unknown`, never `.disconnected`.
public enum ConnectionState: Equatable, Sendable {
    case connected
    case disconnected
    case unknown
}

/// A single timestamped observation from a `KeyboardConnectionProvider`.
public struct ConnectionObservation: Equatable, Sendable {
    public let state: ConnectionState
    public let timestamp: Date
    public let providerHealthy: Bool

    public init(state: ConnectionState, timestamp: Date, providerHealthy: Bool = true) {
        self.state = state
        self.timestamp = timestamp
        self.providerHealthy = providerHealthy
    }
}

/// Which computer a monitor-input request targets.
public enum TargetComputer: String, Codable, Sendable {
    case mac
    case windows
}

/// Automation behaviour selected by the user.
///
/// On the verified G95NC both directions are plain DDC writes (Windows = 5, Mac = 6
/// on HDMI 2) and are honoured even from the input that is not on screen, so the
/// Mac app alone can do both halves; the Windows companion does the same and the
/// two simply agree.
public enum AutomationMode: String, Codable, CaseIterable, Sendable {
    case manual
    case followToWindows   // switch to Windows when the keyboard leaves the Mac; no return
    case returnToMac
    case followBoth
}

/// System lifecycle transitions that must suspend/re-baseline automation.
public enum LifecycleEvent: Equatable, Sendable {
    case willSleep
    case didWake
    case screensDidLock
    case screensDidUnlock
    case bluetoothUnavailable
    case bluetoothAvailable
    case displayDisconnected
    case displayReconnected
}

/// Explicit outcome of a display-control command. `transportCompleted` means the
/// helper exited 0 — it is NOT proof the monitor changed inputs.
public enum SwitchOutcome: Equatable, Sendable {
    case transportCompleted
    case transportFailed(String)
    case timedOut
    case displayUnavailable
    case cancelled
}

/// Coarse policy state for UI/diagnostics (see spec §9.1).
public enum PolicyState: Equatable, Sendable {
    case initializing
    case waitingForMac
    case connected
    case departurePending
    case disconnected
    case arrivalPending
    case suspended
}

/// A decision emitted by `SwitchPolicy` — a request to write a monitor input.
public struct PolicyDecision: Equatable, Sendable {
    public let target: TargetComputer
    public let generation: Int
    public let reason: String

    public init(target: TargetComputer, generation: Int, reason: String) {
        self.target = target
        self.generation = generation
        self.reason = reason
    }
}
