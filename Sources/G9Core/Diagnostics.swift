import Foundation

public struct DiagnosticEvent: Equatable, Sendable {
    public let type: String
    public let localTime: Date
    public let providerDurationMs: Int?
    public let stateTransition: String?
    public let targetInput: String?
    public let requestID: Int?
    public let transportResult: String?

    public init(
        type: String,
        localTime: Date,
        providerDurationMs: Int? = nil,
        stateTransition: String? = nil,
        targetInput: String? = nil,
        requestID: Int? = nil,
        transportResult: String? = nil
    ) {
        self.type = type
        self.localTime = localTime
        self.providerDurationMs = providerDurationMs
        self.stateTransition = stateTransition
        self.targetInput = targetInput
        self.requestID = requestID
        self.transportResult = transportResult
    }
}

/// Bounded, in-memory event log. No keystrokes are ever recorded.
public final class DiagnosticsStore {
    private var events: [DiagnosticEvent] = []
    private let maxEvents: Int
    private let maxAge: TimeInterval
    private let clock: Clock

    public init(maxEvents: Int = 5000, maxAge: TimeInterval = 7 * 24 * 3600, clock: Clock = SystemClock()) {
        self.maxEvents = maxEvents
        self.maxAge = maxAge
        self.clock = clock
    }

    public func record(_ event: DiagnosticEvent) {
        events.append(event)
        prune()
    }

    public func all() -> [DiagnosticEvent] { events }

    private func prune() {
        let cutoff = clock.now.addingTimeInterval(-maxAge)
        events.removeAll { $0.localTime < cutoff }
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    /// Export as plain text with Bluetooth addresses, display UUIDs, and serials
    /// redacted. Redaction operates on the caller-supplied secrets list.
    public func exportRedacted(secrets: [String]) -> String {
        let df = ISO8601DateFormatter()
        var lines: [String] = []
        for e in events {
            var parts = ["[\(df.string(from: e.localTime))]", e.type]
            if let d = e.providerDurationMs { parts.append("dur=\(d)ms") }
            if let t = e.stateTransition { parts.append("state=\(t)") }
            if let ti = e.targetInput { parts.append("target=\(ti)") }
            if let r = e.requestID { parts.append("req=\(r)") }
            if let res = e.transportResult { parts.append("result=\(res)") }
            lines.append(parts.joined(separator: " "))
        }
        var text = lines.joined(separator: "\n")
        for secret in secrets where !secret.isEmpty {
            text = text.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return text
    }
}
