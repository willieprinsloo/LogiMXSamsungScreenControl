import Foundation

/// A resolved display identity from the helper.
public struct ResolvedDisplay: Equatable, Sendable {
    public let uuid: String
    public let name: String
    public init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }
}

/// Sends monitor-input requests to one resolved display. Implementations wrap
/// the bundled `m1ddc` helper; all methods return explicit outcomes and never
/// assume a visual switch from a zero exit.
public protocol DisplayCommandExecutor: AnyObject, Sendable {
    func setInput(displayUUID: String, vcpFeature: UInt8, value: UInt8) async -> SwitchOutcome
    func listDisplays() async -> [ResolvedDisplay]
}

/// Emits one connection observation per poll. Failures MUST surface as
/// `.unknown` with `providerHealthy == false`.
public protocol KeyboardConnectionProvider: AnyObject, Sendable {
    func poll() async -> ConnectionObservation
}

/// Reports system lifecycle transitions (sleep/wake, lock/unlock, etc.).
public protocol LifecycleEventSource: AnyObject {
    var onEvent: ((LifecycleEvent) -> Void)? { get set }
    func start()
}
