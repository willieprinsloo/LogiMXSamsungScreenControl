# G9 Keyboard Switch — Release 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu-bar app that lets a Samsung Odyssey Neo G9 (G95NC) follow a Logitech MX Keys S keyboard between a Mac and a Windows PC, driven by the keyboard's Bluetooth connection state, with a manual switching fallback that always works.

**Architecture:** Two Swift targets in one SwiftPM package. `G9Core` is a pure, hardware-free library (models, config, the switching state machine, the command coordinator, diagnostics) driven entirely by injected clocks and protocol boundaries — fully unit-tested with `swift test`. `G9KeyboardSwitch` is the SwiftUI `MenuBarExtra` app that supplies the real hardware implementations (bundled `m1ddc` for DDC, `system_profiler` JSON for Bluetooth), the lifecycle wiring, and the UI. All monitor writes go through one serialized command queue. Nothing infers keyboard intent from a disconnect.

**Tech Stack:** Swift 6, SwiftUI `MenuBarExtra` (macOS 14+), Foundation `Process`, `NSWorkspace` notifications, `SMAppService` (login item), bundled `m1ddc` helper. Tests: XCTest via `swift test`.

## Global Constraints

Copied verbatim from the spec; every task implicitly includes these.

- **Verified device profile only.** Monitor VCP feature `0x60` (decimal 96). Windows = HDMI 1 = DDC value **5**. Mac = HDMI 2 = DDC value **6** (verified 2026-09-16 from Windows and by register read-back). HDMI 3 has NO DDC value on this firmware (full 0x00-0xFF sweep; only 5/6/15 honoured), which is why the Mac was moved from HDMI 3 to HDMI 2.
- **Mandatory Mac-first activation gate.** Automation starts **unarmed**. It arms only after a stable, valid Mac keyboard connection is observed while automation is enabled, and arming sends **no** monitor command. Only a departure from an armed `Connected` state may auto-request Windows; only a return after an accepted armed departure may auto-request Mac.
- **Armed flag is in-memory only.** Never persist it. Restart, disable/pause, provider fault, or any lifecycle suspension disarms; re-arming needs a fresh stable Mac connection.
- **Unknown ≠ disconnected.** Query failure, timeout, malformed/unexpected JSON, or device-absent-from-both-lists ⇒ `unknown` ⇒ cancel pending, disarm, no monitor write. Only an explicit match in `device_not_connected` is a confirmed disconnect.
- **Process success ≠ visual switch.** A zero exit from `m1ddc` means `transportCompleted`, not confirmed input change. UI label is **"Last requested input"**, never "Current input". Do not use the `0` input readback to drive policy or trigger retries.
- **No key logging.** Detect Easy-Switch only via connection state; never read typed content. Global shortcuts register only the configured combinations.
- **Least privilege.** Run as the normal logged-in user. No daemon, no `sudo`, no Full Disk Access, no Accessibility unless a specific reproduced requirement proves otherwise. Resolve the helper by bundle URL and invoke argv directly — never a shell string built from names/settings. Bounded command timeout; capped captured output.
- **Manual path is sacrosanct.** Manual menu/shortcut switching works independently of automation, cancels pending automatic actions, and starts a manual holdoff.
- **Helper provenance.** `m1ddc` pinned to commit `04d949794102eb8df01ad3681afff6464a3eede2`, MIT license retained, tested arm64 SHA-256 `022685d9ee238a4d0a7a1de0b46d8263af1be6603ef1255a38c9d1470a50892b`. (Verified present and matching on the dev machine.)

## Verified environment facts (dev machine, 2026-09-16)

- Swift 6.3.3, Xcode 26.6, Apple M2 Max, macOS 26.
- `m1ddc display list` ⇒ `[1] Odyssey G95NC (95493343-DBDA-457E-A630-9191EF7330E7)`. Do **not** hardcode this UUID in shipped code — resolve saved identity at launch.
- m1ddc binary hash matches the spec exactly.
- **Safety during dev:** switching to Windows (value 5) blacks out the Mac's own display mid-session; the only recovery is the monitor's physical source control. Never trigger a Windows switch autonomously during development — only on an explicit user action, always after showing the recovery instruction.

## File Structure

```
Package.swift
Sources/
  G9Core/
    Models.swift            # ConnectionObservation, ConnectionState, TargetComputer, AutomationMode,
                            # LifecycleEvent, SwitchOutcome, PolicyState, PolicyDecision
    Clock.swift             # Clock protocol, SystemClock, FakeClock
    Configuration.swift     # Configuration + nested config structs (Codable, matches spec §11 JSON)
    ConfigurationStore.swift# load / validate / atomic save; ConfigError
    SwitchPolicy.swift      # pure Mac-first state machine (the brain)
    Services.swift          # protocols: KeyboardConnectionProvider, DisplayCommandExecutor, LifecycleEventSource
    CommandCoordinator.swift# serialize display writes, generation cancellation, cooldown, retry-once
    Diagnostics.swift       # bounded event log + redacted export
  G9KeyboardSwitch/
    G9App.swift             # @main SwiftUI App, MenuBarExtra scene, accessory activation
    AppModel.swift          # ObservableObject: owns policy/coordinator/providers, publishes status
    MenuBarView.swift       # the menu content (§6.2)
    SettingsView.swift      # profile/keyboard/mode/shortcuts/login (§6.1, later milestone)
    DisplayController.swift  # DisplayCommandExecutor via bundled m1ddc Process
    KeyboardProvider.swift   # KeyboardConnectionProvider via system_profiler JSON
    LifecycleMonitor.swift   # NSWorkspace sleep/wake/lock/unlock -> LifecycleEventSource
    ResourceLocator.swift    # resolve bundled m1ddc URL across swift-run and .app-bundle layouts
    Resources/m1ddc          # bundled helper (pinned build)
    Resources/m1ddc-LICENSE  # MIT notice
Tests/
  G9CoreTests/
    ConfigurationStoreTests.swift
    SwitchPolicyTests.swift
    CommandCoordinatorTests.swift
    DiagnosticsTests.swift
    KeyboardJSONParsingTests.swift   # parser fixtures (parser lives in G9Core, called by the app provider)
Scripts/
  build-app.sh             # swift build -c release, assemble .app bundle, ad-hoc codesign
```

---

## Milestone 1 — Manual controller (menu-bar app that switches the monitor)

Exit condition: signed `.app` appears in the top menu bar; **Switch to Mac** and **Switch to Windows** both visually confirmed by the user; a manual switch works with automation off.

### Task 1: Scaffold the SwiftPM package

**Files:**
- Create: `Package.swift`
- Create: `Sources/G9Core/Clock.swift`
- Create: `Sources/G9KeyboardSwitch/G9App.swift` (temporary stub)
- Create: `Tests/G9CoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: `Clock` protocol, `SystemClock`, `FakeClock`; a buildable package with `G9Core` (library) + `G9KeyboardSwitch` (executable) targets.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "G9KeyboardSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "G9Core"),
        .executableTarget(
            name: "G9KeyboardSwitch",
            dependencies: ["G9Core"],
            resources: [.copy("Resources/m1ddc"), .copy("Resources/m1ddc-LICENSE")]
        ),
        .testTarget(name: "G9CoreTests", dependencies: ["G9Core"]),
    ]
)
```

- [ ] **Step 2: Write `Clock.swift`**

```swift
import Foundation

public protocol Clock: AnyObject { var now: Date { get } }

public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public final class FakeClock: Clock {
    private var current: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }
    public var now: Date { current }
    public func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    public func set(_ date: Date) { current = date }
}
```

- [ ] **Step 3: Stub the app entry point so the package builds**

`Sources/G9KeyboardSwitch/G9App.swift`:

```swift
import SwiftUI

@main
struct G9App: App {
    var body: some Scene {
        MenuBarExtra("G9", systemImage: "display") {
            Text("G9 Keyboard Switch")
        }
    }
}
```

Also create empty resource files so `.copy` succeeds initially, then replace with the real helper in Task 8:
`Sources/G9KeyboardSwitch/Resources/m1ddc` (copy the verified binary here) and `Resources/m1ddc-LICENSE`.

- [ ] **Step 4: Write a smoke test**

`Tests/G9CoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import G9Core

final class SmokeTests: XCTestCase {
    func testFakeClockAdvances() {
        let c = FakeClock(Date(timeIntervalSince1970: 0))
        c.advance(by: 5)
        XCTAssertEqual(c.now, Date(timeIntervalSince1970: 5))
    }
}
```

- [ ] **Step 5: Build & test**

Run: `swift build && swift test`
Expected: build succeeds; `testFakeClockAdvances` PASSES.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "chore: scaffold G9Core + menu-bar app package"`

---

### Task 2: Core models

**Files:** Create `Sources/G9Core/Models.swift`; Test `Tests/G9CoreTests/ModelsTests.swift`

**Interfaces — Produces (exact names later tasks depend on):**

```swift
public enum ConnectionState: Equatable, Sendable { case connected, disconnected, unknown }

public struct ConnectionObservation: Equatable, Sendable {
    public let state: ConnectionState
    public let timestamp: Date
    public let providerHealthy: Bool
    public init(state: ConnectionState, timestamp: Date, providerHealthy: Bool = true)
}

public enum TargetComputer: String, Codable, Sendable { case mac, windows }

public enum AutomationMode: String, Codable, CaseIterable, Sendable {
    case manual, returnToMac, followBoth
}

public enum LifecycleEvent: Equatable, Sendable {
    case willSleep, didWake
    case screensDidLock, screensDidUnlock
    case bluetoothUnavailable, bluetoothAvailable
    case displayDisconnected, displayReconnected
}

public enum SwitchOutcome: Equatable, Sendable {
    case transportCompleted, transportFailed(String), timedOut, displayUnavailable, cancelled
}

public enum PolicyState: Equatable, Sendable {
    case initializing, waitingForMac, connected, departurePending, disconnected, arrivalPending, suspended
}

public struct PolicyDecision: Equatable, Sendable {
    public let target: TargetComputer
    public let generation: Int
    public let reason: String
    public init(target: TargetComputer, generation: Int, reason: String)
}
```

- [ ] **Step 1:** Write the types above into `Models.swift` with public memberwise inits.
- [ ] **Step 2:** Write `ModelsTests.swift` asserting `AutomationMode(rawValue: "followBoth") == .followBoth` and `SwitchOutcome.transportFailed("x") != .transportCompleted`.
- [ ] **Step 3:** `swift test` — PASS.
- [ ] **Step 4:** Commit `feat: G9Core domain models`.

---

### Task 3: Configuration model + ConfigurationStore

**Files:** Create `Sources/G9Core/Configuration.swift`, `Sources/G9Core/ConfigurationStore.swift`; Test `Tests/G9CoreTests/ConfigurationStoreTests.swift`

**Interfaces — Produces:**

```swift
public struct InputProfile: Codable, Equatable, Sendable {
    public var label: String; public var value: UInt8; public var calibrated: Bool
}
public struct MonitorInputs: Codable, Equatable, Sendable { public var mac: InputProfile; public var windows: InputProfile }
public struct MonitorConfig: Codable, Equatable, Sendable {
    public var displayUUID: String?; public var model: String; public var vcpFeature: UInt8; public var inputs: MonitorInputs
}
public struct KeyboardConfig: Codable, Equatable, Sendable {
    public var name: String; public var vendorID: Int; public var productID: Int; public var localIdentifier: String?
}
public struct AutomationConfig: Codable, Equatable, Sendable {
    public var mode: AutomationMode
    public var pollIntervalSeconds: Double
    public var departureDebounceSeconds: Double
    public var arrivalDebounceSeconds: Double
    public var cooldownSeconds: Double
    public var resumeSettleSeconds: Double
    public var manualHoldoffSeconds: Double
    public var pauseWhenLocked: Bool
}
public struct Configuration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var monitor: MonitorConfig
    public var keyboard: KeyboardConfig
    public var automation: AutomationConfig
    public var launchAtLogin: Bool
    public static var g95ncDefault: Configuration { get }   // matches spec §11 JSON, calibrated:false
}

public enum ConfigError: Error, Equatable {
    case unsupportedSchema(Int), duplicateInputValue(UInt8), invalidInputValue(UInt8)
    case invalidVCPFeature(UInt8), invalidDeviceID, invalidTiming(String)
}

public final class ConfigurationStore {
    public init(directory: URL, fileManager: FileManager = .default)
    public func load() throws -> Configuration?          // nil if no file yet
    public func save(_ config: Configuration) throws     // atomic write
    public static func validate(_ config: Configuration) throws
}
```

- [ ] **Step 1 (test first):** Round-trip + validation tests in `ConfigurationStoreTests.swift`:

```swift
import XCTest
@testable import G9Core

final class ConfigurationStoreTests: XCTestCase {
    private func tmpDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("g9-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testDefaultMatchesSpec() {
        let c = Configuration.g95ncDefault
        XCTAssertEqual(c.monitor.vcpFeature, 96)
        XCTAssertEqual(c.monitor.inputs.mac.value, 7)
        XCTAssertEqual(c.monitor.inputs.windows.value, 5)
        XCTAssertFalse(c.monitor.inputs.mac.calibrated)
        XCTAssertEqual(c.keyboard.vendorID, 1133)
        XCTAssertEqual(c.keyboard.productID, 45944)
        XCTAssertEqual(c.automation.mode, .manual)
    }

    func testSaveLoadRoundTrip() throws {
        let store = ConfigurationStore(directory: tmpDir())
        XCTAssertNil(try store.load())
        try store.save(.g95ncDefault)
        XCTAssertEqual(try store.load(), .g95ncDefault)
    }

    func testDuplicateInputValueRejected() {
        var c = Configuration.g95ncDefault
        c.monitor.inputs.windows.value = 7   // same as mac
        XCTAssertThrowsError(try ConfigurationStore.validate(c)) {
            XCTAssertEqual($0 as? ConfigError, .duplicateInputValue(7))
        }
    }

    func testZeroInputValueRejected() {
        var c = Configuration.g95ncDefault
        c.monitor.inputs.mac.value = 0
        XCTAssertThrowsError(try ConfigurationStore.validate(c)) {
            XCTAssertEqual($0 as? ConfigError, .invalidInputValue(0))
        }
    }

    func testWrongSchemaRejected() {
        var c = Configuration.g95ncDefault
        c.schemaVersion = 99
        XCTAssertThrowsError(try ConfigurationStore.validate(c)) {
            XCTAssertEqual($0 as? ConfigError, .unsupportedSchema(99))
        }
    }
}
```

- [ ] **Step 2:** Run tests — FAIL (types absent).
- [ ] **Step 3:** Implement `Configuration.swift` (structs + `g95ncDefault` exactly mirroring spec §11) and `ConfigurationStore.swift`:
  - `load()`: return `nil` if file missing; else decode `config.json`.
  - `save()`: `validate` first, encode pretty JSON, write to a temp file in the same dir, then `FileManager.replaceItemAt` for atomicity.
  - `validate()`: schemaVersion == 1 else `unsupportedSchema`; each input value in `1...255` else `invalidInputValue`; `mac.value != windows.value` else `duplicateInputValue`; `vcpFeature != 0` else `invalidVCPFeature`; vendorID/productID > 0 else `invalidDeviceID`; every timing > 0 (debounces ≥ 0) else `invalidTiming`.
- [ ] **Step 4:** `swift test` — PASS.
- [ ] **Step 5:** Commit `feat: configuration model + validating store`.

---

### Task 4: DisplayCommandExecutor protocol + m1ddc DisplayController

**Files:** Create `Sources/G9Core/Services.swift` (protocols), `Sources/G9KeyboardSwitch/ResourceLocator.swift`, `Sources/G9KeyboardSwitch/DisplayController.swift`.

**Interfaces — Produces:**

```swift
// G9Core/Services.swift
public protocol DisplayCommandExecutor: AnyObject {
    // Set `vcpFeature` to `value` on the display identified by `displayUUID`. Bounded, synchronous-ish.
    func setInput(displayUUID: String, vcpFeature: UInt8, value: UInt8) async -> SwitchOutcome
    // Resolve current identities; empty if none / helper failure.
    func listDisplays() async -> [ResolvedDisplay]
}
public struct ResolvedDisplay: Equatable, Sendable {
    public let uuid: String; public let name: String
    public init(uuid: String, name: String)
}
public protocol KeyboardConnectionProvider: AnyObject {
    func poll() async -> ConnectionObservation
}
public protocol LifecycleEventSource: AnyObject {
    var onEvent: ((LifecycleEvent) -> Void)? { get set }
    func start()
}
```

- [ ] **Step 1:** Write `Services.swift` with the three protocols + `ResolvedDisplay`.
- [ ] **Step 2:** Write `ResourceLocator.swift` — resolve the bundled `m1ddc` across layouts:

```swift
import Foundation

enum ResourceLocator {
    /// Resolve the bundled m1ddc executable URL.
    static func m1ddcURL() -> URL? {
        // .app bundle: Contents/Resources/m1ddc
        if let u = Bundle.main.url(forResource: "m1ddc", withExtension: nil) { return u }
        // SwiftPM resource bundle (swift run / tests)
        if let u = Bundle.module.url(forResource: "m1ddc", withExtension: nil) { return u }
        return nil
    }
}
```

- [ ] **Step 3:** Write `DisplayController.swift`:

```swift
import Foundation
import G9Core

final class DisplayController: DisplayCommandExecutor {
    private let executableURL: URL
    private let timeout: TimeInterval

    init(executableURL: URL, timeout: TimeInterval = 8) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func setInput(displayUUID: String, vcpFeature: UInt8, value: UInt8) async -> SwitchOutcome {
        // m1ddc addresses the display by UUID; input is set via `set input <value>`.
        let (code, _, err, timedOut) = await run(["display", displayUUID, "set", "input", String(value)])
        if timedOut { return .timedOut }
        if code == 0 { return .transportCompleted }
        if err.localizedCaseInsensitiveContains("no display") { return .displayUnavailable }
        return .transportFailed("exit \(code): \(err.prefix(200))")
    }

    func listDisplays() async -> [ResolvedDisplay] {
        let (code, out, _, timedOut) = await run(["display", "list"])
        guard !timedOut, code == 0 else { return [] }
        // Lines look like: "[1] Odyssey G95NC (95493343-....)"
        return out.split(separator: "\n").compactMap { line in
            guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close
            else { return nil }
            let uuid = String(line[line.index(after: open)..<close])
            let name = line[..<open].drop(while: { $0 != "]" }).dropFirst().trimmingCharacters(in: .whitespaces)
            return ResolvedDisplay(uuid: uuid, name: name)
        }
    }

    private func run(_ args: [String]) async -> (Int32, String, String, Bool) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = executableURL
            p.arguments = args
            let outPipe = Pipe(); let errPipe = Pipe()
            p.standardOutput = outPipe; p.standardError = errPipe
            var finished = false
            let lock = NSLock()
            let timeoutWork = DispatchWorkItem {
                lock.lock(); let done = finished; lock.unlock()
                if !done { p.terminate() ; cont.resume(returning: (-1, "", "timeout", true)) ; lock.lock(); finished = true; lock.unlock() }
            }
            p.terminationHandler = { proc in
                timeoutWork.cancel()
                lock.lock(); if finished { lock.unlock(); return }; finished = true; lock.unlock()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile().prefix(64_000), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile().prefix(64_000), encoding: .utf8) ?? ""
                cont.resume(returning: (proc.terminationStatus, out, err, false))
            }
            do { try p.run() } catch {
                cont.resume(returning: (-1, "", "launch failed: \(error)", false)); return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        }
    }
}
```

- [ ] **Step 4 (manual verification — safe path only):** From a scratch `main`, call `listDisplays()` and assert it returns the G95NC. Do **not** call `setInput` to Windows here. Run `swift run` or a temporary test executable and confirm the UUID prints.
- [ ] **Step 5:** Commit `feat: m1ddc display controller + service protocols`.

> Note: `setInput` is exercised end-to-end only via the menu action in Task 9 with the user watching the monitor, per the Windows-blackout safety rule.

---

### Task 5: CommandCoordinator (serialized queue, generation cancel, cooldown, retry-once)

**Files:** Create `Sources/G9Core/CommandCoordinator.swift`; Test `Tests/G9CoreTests/CommandCoordinatorTests.swift`

**Interfaces — Consumes:** `DisplayCommandExecutor`, `Clock`, `SwitchOutcome`. **Produces:**

```swift
public actor CommandCoordinator {
    public init(executor: DisplayCommandExecutor, clock: Clock, displayUUID: String, vcpFeature: UInt8)
    /// Request an input write for `target` with the given `value`, tagged with policy `generation`.
    /// Coalesces to the newest request; drops requests whose generation is stale before executing.
    public func request(target: TargetComputer, value: UInt8, generation: Int) async
    /// Latest generation observed; used by policy/tests to reason about cancellation.
    public func currentGeneration() -> Int
    /// For tests/telemetry: outcomes emitted, newest last.
    public var lastOutcome: SwitchOutcome? { get }
}
```

Behaviour to implement and test with a `FakeExecutor` (records calls, returns scripted outcomes):
- [ ] Only one `setInput` runs at a time (serialized by the actor).
- [ ] A request whose `generation` is lower than the newest received generation is discarded without calling the executor (`test_staleRequestDropped`).
- [ ] On `.transportFailed`, retry exactly once, after re-checking the request is still current; do not retry on `.transportCompleted`, `.timedOut`→(no retry), `.displayUnavailable`, or `.cancelled` (`test_retryOnceOnTransportFailure`).
- [ ] No repeated identical write at steady state — same (target,value,generation) already applied ⇒ skip (`test_noDuplicateWrite`).
- [ ] Write each test first, watch it fail, implement, pass, commit `feat: serialized command coordinator`.

Example test skeleton:

```swift
final class CommandCoordinatorTests: XCTestCase {
    func test_staleRequestDropped() async {
        let exec = FakeExecutor(outcomes: [.transportCompleted])
        let clock = FakeClock()
        let c = CommandCoordinator(executor: exec, clock: clock, displayUUID: "U", vcpFeature: 96)
        await c.request(target: .windows, value: 5, generation: 1)
        await c.request(target: .mac, value: 7, generation: 5)
        // A late arrival with old generation must not execute.
        await c.request(target: .windows, value: 5, generation: 2)
        let calls = await exec.calls
        XCTAssertFalse(calls.contains(where: { $0.value == 5 && $0.afterGeneration >= 5 }))
    }
}
```

---

## Milestone 2 — Connection diagnostics (keyboard provider)

Exit condition: repeated real Windows↔Mac keyboard switches are observed as connected/disconnected transitions; any failure surfaces as `unknown`.

### Task 6: Keyboard JSON parser (in G9Core, pure)

**Files:** Create `Sources/G9Core/KeyboardStatusParser.swift`; Test `Tests/G9CoreTests/KeyboardJSONParsingTests.swift`

**Interfaces — Produces:**

```swift
public enum KeyboardStatusParser {
    /// Parse `system_profiler SPBluetoothDataType -json` output for the selected device.
    /// - Returns `.connected`/`.disconnected` only on an explicit match in the corresponding list.
    /// - Returns `.unknown` for malformed JSON, device absent from both lists, or contradiction.
    public static func status(
        fromJSON data: Data,
        deviceName: String,
        localIdentifier: String?
    ) -> ConnectionState
}
```

Rules (from §8.2): parse JSON structurally — never text-search for "connected". Walk `SPBluetoothDataType[].device_connected[]` and `device_not_connected[]` (arrays of single-key dicts keyed by device name). Match by `localIdentifier` (address) when present, else by `deviceName`. Present in `device_connected` ⇒ `.connected`; present in `device_not_connected` ⇒ `.disconnected`; in neither, in both, or unparseable ⇒ `.unknown`.

- [ ] **Step 1:** Add sanitized fixtures (connected, explicitly-disconnected, missing, duplicate-named, contradictory, malformed) as string literals in the test.
- [ ] **Step 2:** Assert each fixture maps to the expected `ConnectionState` (missing⇒unknown, contradictory⇒unknown, malformed⇒unknown).
- [ ] **Step 3:** Implement the parser with `JSONSerialization`; run — PASS.
- [ ] **Step 4:** Commit `feat: structural Bluetooth status parser`.

### Task 7: system_profiler KeyboardProvider (app target)

**Files:** Create `Sources/G9KeyboardSwitch/KeyboardProvider.swift`

**Interfaces — Consumes:** `KeyboardStatusParser`, `KeyboardConnectionProvider`, `Clock`.

- [ ] Implement `poll()` that runs `/usr/sbin/system_profiler SPBluetoothDataType -json` via `Process` with an **absolute path**, a 5 s timeout, never overlapping a prior invocation (guard with an actor / in-flight flag), captures stdout with a size cap, and returns `ConnectionObservation(state: KeyboardStatusParser.status(...), timestamp: clock.now, providerHealthy: <query succeeded>)`. On timeout/nonzero/malformed ⇒ `state: .unknown, providerHealthy: false`. Record query duration for diagnostics; back off after repeated failures.
- [ ] **Manual verification:** run `swift run` with a temporary loop logging observations while the user switches the keyboard Windows→Mac→Windows; confirm the log shows disconnected↔connected transitions and that a query failure shows `unknown`, never `disconnected`.
- [ ] Commit `feat: system_profiler keyboard provider`.

---

## Milestone 3 — Policy engine (the brain)

Exit condition: the full activation-gate + edge-case suite (§15) passes on a fake clock.

### Task 8: SwitchPolicy state machine

**Files:** Create `Sources/G9Core/SwitchPolicy.swift`; Test `Tests/G9CoreTests/SwitchPolicyTests.swift`

**Interfaces — Consumes:** `AutomationConfig`, `Clock`, `ConnectionObservation`, `LifecycleEvent`. **Produces:**

```swift
public final class SwitchPolicy {
    public init(config: AutomationConfig, clock: Clock)
    public private(set) var state: PolicyState
    public private(set) var armed: Bool
    public var mode: AutomationMode { get set }        // setting a different mode disarms + cancels

    public func begin()                                  // enter waitingForMac (automation enabled)
    public func handle(observation: ConnectionObservation) -> [PolicyDecision]
    public func handle(lifecycle: LifecycleEvent, at now: Date) -> [PolicyDecision]
    public func tick(now: Date) -> [PolicyDecision]      // cooldown/settle/deferred progression
    public func pause()
    public func resume()
    public func manualSwitch(to target: TargetComputer, at now: Date)  // cancels pending, sets holdoff
}
```

Implement the behaviour from §9 and the reference logic in the design notes below. Then write the **required activation tests (§15 a–g)** plus the mode table and edge cases — one `XCTest` method each, all on a `FakeClock`:

- [ ] `test_a_startupDisconnectedNeverSwitches`
- [ ] `test_b_firstMacConnectionArmsNoCommand`
- [ ] `test_c_departureRequestsWindows_inFollowBoth`
- [ ] `test_d_returnRequestsMac`
- [ ] `test_e_startupAlreadyConnectedArmsAfterFreshStability_noCommand`
- [ ] `test_f_restartPauseResumeProviderFailSleepWakeResetArming`
- [ ] `test_g_repeatedDisconnectedAfterResetCannotTriggerUntilNewMacConnection`
- [ ] `test_returnToMac_noWindowsOnDeparture_macOnReturn`
- [ ] `test_manual_modeNeverActsAutomatically`
- [ ] `test_interruptedDepartureDebounce_noCommand`
- [ ] `test_unknownDisarmsAndCancelsPending`
- [ ] `test_cooldownDefersOppositeTransition_thenApplies`
- [ ] `test_manualHoldoffBlocksAutomaticReversal`
- [ ] `test_followBoth_twentyRoundTrips_noOscillation` (loop; final decision correct, one command per accepted transition)

Each: write test → run (FAIL) → implement/extend policy → run (PASS) → commit.

**Design notes (reference implementation guidance):**
- Accumulate consecutive same-state healthy observations; a transition is *accepted* when `now - firstOfRun >= debounce` (departure 3 s, arrival 1 s). Any `unknown`/unhealthy observation resets the run, cancels pending, disarms, and enters suspended detection.
- `handleStableConnected`: if `!armed` ⇒ set `armed = true`, `state = .connected`, **emit nothing** (this is the arming event). If armed and the prior state was `.disconnected`/`.arrivalPending` ⇒ this is a *return*; emit `.mac` in `returnToMac`/`followBoth`.
- `handleStableDisconnected`: if `!armed` ⇒ stay `.waitingForMac`, emit nothing. If armed and prior state was `.connected`/`.departurePending` ⇒ emit `.windows` **only** in `followBoth`.
- `emit`: if within `cooldownSeconds` of the last automatic command, or before `holdoffUntil`, store as the single `deferredTarget` and emit nothing; else bump `generation`, stamp `lastAutomaticCommandAt = now`, clear `deferredTarget`, return one `PolicyDecision`.
- `tick`: when `settleUntil` elapses, re-baseline (`armed = false`, `state = .waitingForMac`, clear runs) — never replay a departure that may have happened during the outage. If a `deferredTarget` exists and cooldown+holdoff have expired and the session is armed and not suspended, emit it (revalidated); if suspended or disarmed, discard it.
- Lifecycle: `willSleep`/`bluetoothUnavailable`/`displayDisconnected`/(`screensDidLock` when `pauseWhenLocked`) ⇒ hard-suspend (cancel pending, disarm, `state = .suspended`). `didWake`/`screensDidUnlock`/`bluetoothAvailable`/`displayReconnected` ⇒ start settling (`settleUntil = now + resumeSettleSeconds`), cancel pending, disarm.
- `manualSwitch`: cancel pending (bump generation), set `holdoffUntil = now + manualHoldoffSeconds`, clear `deferredTarget`. Never changes `armed`/observation state.
- `cancelPending` bumps `generation` so any queued command in the coordinator becomes stale.

---

## Milestone 4 — Automatic modes wired to hardware

Exit condition: hardware round-trip + lifecycle tests pass; modes selectable from the menu; calibration flags set on confirmation.

### Task 9: AppModel — wire providers, policy, coordinator, menu bar

**Files:** Create `Sources/G9KeyboardSwitch/AppModel.swift`, rewrite `Sources/G9KeyboardSwitch/MenuBarView.swift`, `Sources/G9KeyboardSwitch/LifecycleMonitor.swift`, update `G9App.swift`.

`AppModel` (`@MainActor final class AppModel: ObservableObject`) owns: `ConfigurationStore`, `SwitchPolicy`, `CommandCoordinator`, `DisplayController`, `KeyboardProvider`, `LifecycleMonitor`, `DiagnosticsStore`. It:
- [ ] Loads config at launch (falls back to `.g95ncDefault`), resolves the display UUID via `listDisplays()` matching saved identity (or the single connected display), and stores it for the coordinator.
- [ ] Runs a polling loop (`Task`): every `pollIntervalSeconds` (after the previous query completes), `await provider.poll()`, feed to `policy.handle(observation:)`, then `policy.tick(now:)`; for each returned `PolicyDecision`, `await coordinator.request(target:value:generation:)` using the config's input value for that target. Publishes a `@Published var status: StatusLine`.
- [ ] Subscribes to `LifecycleMonitor` events → `policy.handle(lifecycle:at:)`.
- [ ] Exposes `switchToMac()` / `switchToWindows()` (manual): call `policy.manualSwitch(to:at:)` then `coordinator.request(...)` with a fresh generation. **`switchToWindows()` must show/log the physical-recovery note** (monitor source control → HDMI 3) because it blacks out the Mac.
- [ ] Exposes `setMode(_:)`, `pauseAutomation()`, `resumeAutomation()`.

`MenuBarView` renders §6.2 exactly, binding to `AppModel`:
```
G9 Keyboard Switch
Keyboard: <status>          Monitor: Odyssey G95NC
Last requested input: <Mac · HDMI 3 | Windows · HDMI 1 | —>
—
Switch to Mac
Switch to Windows
—
Automation: (Manual / Return to Mac / Follow both ways picker)
Pause automation
—
Settings…   Diagnostics…   Quit
```
Status strings must distinguish: Paused, Waiting for keyboard to connect to Mac, Armed and monitoring, Waiting for stable connection, Display unavailable, Detection unavailable. Never show "Keyboard on Windows" from a disconnect alone.

`LifecycleMonitor` maps `NSWorkspace.willSleepNotification`/`didWakeNotification` and the session lock/unlock distributed notifications (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`) to `LifecycleEvent`s.

- [ ] **Manual verification with user present:** launch, click **Switch to Mac** (safe, value 7) → confirm no visual change / stays on Mac. Then, with the user ready to recover via the monitor's source button, click **Switch to Windows** (value 5) → user confirms the monitor changes to the PC; user switches back physically or via a second machine. Record both as visually confirmed. Set `calibrated = true` on confirmation and save config.
- [ ] Commit `feat: wire menu-bar app to policy + hardware`.

### Task 10: DiagnosticsStore + export

**Files:** Create `Sources/G9Core/Diagnostics.swift`; Test `Tests/G9CoreTests/DiagnosticsTests.swift`

- [ ] Bounded ring buffer (≤ 7 days or 5 MB) of events: `{type, localTime, providerDurationMs, stateTransition, targetInput, requestID, transportResult}`. No keystrokes.
- [ ] `exportRedacted()` omits/redacts Bluetooth addresses, display UUIDs, serials.
- [ ] Tests: buffer bound enforced; export contains no UUID/address substrings.
- [ ] Commit `feat: bounded diagnostics with redacted export`.

---

## Milestone 5 — Packaging

Exit condition: a clean, signed `.app` runs for a normal user; login-at-start optional; diagnostic export works.

### Task 11: `.app` bundle + ad-hoc sign + launch

**Files:** Create `Scripts/build-app.sh`.

- [ ] `swift build -c release`; assemble `G9 Keyboard Switch.app` with `Contents/MacOS/G9KeyboardSwitch`, `Contents/Resources/m1ddc` (+ LICENSE + the SPM resource bundle), and `Contents/Info.plist` with `LSUIElement = true`, `CFBundleIdentifier = solutions.metalogix.g9switch`, `LSMinimumSystemVersion = 14.0`.
- [ ] `codesign --force --deep --sign - "G9 Keyboard Switch.app"` (ad-hoc for local run; note real distribution needs a Developer ID + notarization).
- [ ] `open "G9 Keyboard Switch.app"` → confirm the `display` icon appears in the top menu bar and the menu renders. Confirm no Dock icon (accessory).
- [ ] Commit `chore: .app packaging script`.

### Task 12: Settings, shortcuts, launch-at-login

**Files:** Create `Sources/G9KeyboardSwitch/SettingsView.swift`; extend `AppModel`.

- [ ] Settings window: choose display (from `listDisplays()`), choose keyboard, edit/test input mappings (with the recovery warning before a Windows test), pick automation mode (default Manual until calibrated), toggle launch-at-login.
- [ ] Launch-at-login via `SMAppService.mainApp.register()/unregister()`.
- [ ] Global shortcuts for Switch-to-Mac / Switch-to-Windows using a minimal, no-Accessibility mechanism (`KeyboardShortcuts` SPM package *or* Carbon `RegisterEventHotKey` — engineer's choice; must register only the configured combos). **Decision to confirm with maintainer before adding a dependency.**
- [ ] "Waiting for keyboard to connect to Mac" shown after enabling a mode until a stable Mac connection arms the session.
- [ ] Commit `feat: settings, login item, global shortcuts`.

---

## Milestone 6 — Broader support (roadmap; separate plan later)

Out of scope for this plan; each item gets its own compatibility-tested plan:
- Native Bluetooth event provider behind `KeyboardConnectionProvider` (validate `IOBluetoothDevice.isConnected()` / CoreBluetooth against the same physical/sleep/re-pair tests before replacing the profiler baseline).
- Windows companion (arrival-based `requestOwnInput`, authenticated transport).
- Logitech HID++ host events; optional mouse-following.
- More monitor profiles + manual calibration UI.

---

## Failure-handling coverage (spec §14) — where each is handled

| Condition | Handled in |
|---|---|
| Start with keyboard absent / already connected / first connect | Task 8 activation tests b/e + AppModel |
| Keyboard missing / malformed / timeout ⇒ unknown | Task 6/7 provider + Task 8 unknown handling |
| Bluetooth off, sleep/lock, wake/unlock | Task 8 lifecycle + Task 9 LifecycleMonitor |
| Keyboard powered off / third device (residual ambiguity) | Disclosed in Settings copy (Task 12); not "solved" |
| Monitor unplugged / DDC success-but-unchanged / `0` readback | Task 4 outcomes + "Last requested input" label (Task 9) |
| Return during queued Windows request | Task 5 generation cancel + Task 8 cooldown |
| Manual switch cancels automation + holdoff | Task 8 `manualSwitch` + Task 9 |
| Two instances launched | Single-instance guard in `G9App` (bundle-id lock at launch; Task 11) |

## Self-review notes

- **Spec coverage:** §1–§10, §11 (config), §12 (perms/packaging — Tasks 11/12), §14 (table above), §15 activation + parsing + policy tests (Tasks 3/6/8), §16 milestones map 1:1 to the milestone headers, §17 assets (m1ddc verified/bundled Task 1/11). §13 (Windows companion) intentionally deferred to Milestone 6.
- **Type consistency:** `PolicyDecision(target,generation,reason)`, `ConnectionObservation(state,timestamp,providerHealthy)`, `SwitchOutcome` cases, and `AutomationMode` raw values are used identically across Tasks 2/4/5/8/9.
- **Open decision (needs maintainer sign-off):** global-shortcut mechanism / whether to add the `KeyboardShortcuts` dependency (Task 12). Everything else uses only Foundation/SwiftUI/AppKit + the bundled helper.
