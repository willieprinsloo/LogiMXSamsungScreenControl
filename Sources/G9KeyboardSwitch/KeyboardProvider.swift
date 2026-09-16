import Foundation
import G9Core

/// Polls `system_profiler SPBluetoothDataType -json` for the selected device.
/// Serialized (never overlaps a prior query). Any failure => `.unknown` with
/// `providerHealthy == false`. Records the last query duration for diagnostics.
actor SystemProfilerKeyboardProvider: KeyboardConnectionProvider {
    private let deviceName: String
    private let localIdentifier: String?
    private let timeout: TimeInterval
    private let profilerPath = "/usr/sbin/system_profiler"

    private(set) var lastDurationMs: Int = 0
    private var consecutiveFailures = 0

    init(deviceName: String, localIdentifier: String?, timeout: TimeInterval = 5) {
        self.deviceName = deviceName
        self.localIdentifier = localIdentifier
        self.timeout = timeout
    }

    func poll() async -> ConnectionObservation {
        let start = Date()
        let (code, data, timedOut) = runProfiler()
        lastDurationMs = Int(Date().timeIntervalSince(start) * 1000)

        guard !timedOut, code == 0, let data, !data.isEmpty else {
            consecutiveFailures += 1
            return ConnectionObservation(state: .unknown, timestamp: Date(), providerHealthy: false)
        }
        let state = KeyboardStatusParser.status(fromJSON: data, deviceName: deviceName, localIdentifier: localIdentifier)
        // A parseable query that simply doesn't find the device is still a
        // healthy query returning `.unknown` (device absent from both lists).
        consecutiveFailures = 0
        return ConnectionObservation(state: state, timestamp: Date(), providerHealthy: true)
    }

    private func runProfiler() -> (Int32, Data?, Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: profilerPath)
        p.arguments = ["SPBluetoothDataType", "-json"]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        let handle = outPipe.fileHandleForReading

        // Drain stdout on a background queue so a full pipe never deadlocks.
        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            box.data = handle.readDataToEndOfFile()
            group.leave()
        }

        do { try p.run() } catch { return (-1, nil, false) }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return (-1, nil, true)
        }
        p.waitUntilExit()
        return (p.terminationStatus, Data(box.data.prefix(4_000_000)), false)
    }
}

/// Lock-free hand-off box for the background pipe reader; access is serialized
/// by the DispatchGroup barrier (write completes before the read).
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
