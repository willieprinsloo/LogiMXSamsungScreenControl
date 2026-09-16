import Foundation

/// Abstract time source so policy/coordinator logic is deterministic under test.
public protocol Clock: AnyObject, Sendable {
    var now: Date { get }
}

public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Deterministic clock for tests. Advance/set time explicitly.
/// `@unchecked Sendable`: intended for single-threaded test use only.
public final class FakeClock: Clock, @unchecked Sendable {
    private var current: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }
    public var now: Date { current }
    public func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    public func set(_ date: Date) { current = date }
}
