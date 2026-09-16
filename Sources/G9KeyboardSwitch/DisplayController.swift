import Foundation
import G9Core

/// `DisplayCommandExecutor` backed by the bundled `m1ddc` helper. Resolves the
/// binary by bundle URL and invokes argv directly (never a shell string).
final class DisplayController: DisplayCommandExecutor, @unchecked Sendable {
    private let executableURL: URL
    private let timeout: TimeInterval

    init(executableURL: URL, timeout: TimeInterval = 8) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func setInput(displayUUID: String, vcpFeature: UInt8, value: UInt8) async -> SwitchOutcome {
        let (code, _, err, timedOut) = await run(["display", displayUUID, "set", "input", String(value)])
        if timedOut { return .timedOut }
        if code == 0 { return .transportCompleted }
        if err.localizedCaseInsensitiveContains("no display") || err.localizedCaseInsensitiveContains("not found") {
            return .displayUnavailable
        }
        return .transportFailed("exit \(code): \(err.prefix(200))")
    }

    func listDisplays() async -> [ResolvedDisplay] {
        let (code, out, _, timedOut) = await run(["display", "list"])
        guard !timedOut, code == 0 else { return [] }
        return out.split(separator: "\n").compactMap { line -> ResolvedDisplay? in
            // Format: "[1] Odyssey G95NC (95493343-....)"
            guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { return nil }
            let uuid = String(line[line.index(after: open)..<close])
            let afterBracket = line.drop(while: { $0 != "]" }).dropFirst()
            let name = String(afterBracket[..<(afterBracket.firstIndex(of: "(") ?? afterBracket.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            return ResolvedDisplay(uuid: uuid, name: name)
        }
    }

    /// Returns (exitCode, stdout, stderr, timedOut). Bounded by `timeout`; output capped.
    private func run(_ args: [String]) async -> (Int32, String, String, Bool) {
        let exe = executableURL
        let limit = timeout
        return await withCheckedContinuation { (cont: CheckedContinuation<(Int32, String, String, Bool), Never>) in
            DispatchQueue.global().async {
                cont.resume(returning: DisplayController.runSync(exe: exe, args: args, timeout: limit))
            }
        }
    }

    /// Synchronous, self-contained process run — no captures cross closures, so
    /// it satisfies strict-concurrency checks. Runs off the cooperative pool.
    private static func runSync(exe: URL, args: [String], timeout: TimeInterval) -> (Int32, String, String, Bool) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        let outBox = ByteBox(); let errBox = ByteBox()
        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global().async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); reads.leave() }
        reads.enter()
        DispatchQueue.global().async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); reads.leave() }

        do { try p.run() } catch { return (-1, "", "launch failed: \(error)", false) }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline { p.terminate(); return (-1, "", "timeout", true) }
            usleep(20_000)
        }
        reads.wait()   // pipes close on exit; reads complete
        let out = String(data: outBox.data.prefix(64_000), encoding: .utf8) ?? ""
        let err = String(data: errBox.data.prefix(64_000), encoding: .utf8) ?? ""
        return (p.terminationStatus, out, err, false)
    }
}

/// Hand-off box for a background pipe reader; access serialized by the group barrier.
private final class ByteBox: @unchecked Sendable {
    var data = Data()
}
