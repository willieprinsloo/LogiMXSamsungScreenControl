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
        XCTAssertEqual(c.schemaVersion, 1)
        XCTAssertEqual(c.monitor.vcpFeature, 96)
        XCTAssertEqual(c.monitor.inputs.mac.value, 7)
        XCTAssertEqual(c.monitor.inputs.windows.value, 5)
        XCTAssertEqual(c.monitor.inputs.mac.label, "HDMI 3")
        XCTAssertEqual(c.monitor.inputs.windows.label, "HDMI 1")
        XCTAssertFalse(c.monitor.inputs.mac.calibrated)
        XCTAssertFalse(c.monitor.inputs.windows.calibrated)
        XCTAssertEqual(c.keyboard.vendorID, 1133)
        XCTAssertEqual(c.keyboard.productID, 45944)
        XCTAssertEqual(c.automation.mode, .manual)
        XCTAssertTrue(c.automation.pauseWhenLocked)
        XCTAssertFalse(c.launchAtLogin)
    }

    func testSaveLoadRoundTrip() throws {
        let store = ConfigurationStore(directory: tmpDir())
        XCTAssertNil(try store.load())
        try store.save(.g95ncDefault)
        XCTAssertEqual(try store.load(), .g95ncDefault)
    }

    func testOverwriteIsAtomicRoundTrip() throws {
        let store = ConfigurationStore(directory: tmpDir())
        try store.save(.g95ncDefault)
        var updated = Configuration.g95ncDefault
        updated.monitor.displayUUID = "UUID-123"
        updated.monitor.inputs.mac.calibrated = true
        try store.save(updated)
        XCTAssertEqual(try store.load(), updated)
    }

    func testDuplicateInputValueRejected() {
        var c = Configuration.g95ncDefault
        c.monitor.inputs.windows.value = 7
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

    func testZeroPollIntervalRejected() {
        var c = Configuration.g95ncDefault
        c.automation.pollIntervalSeconds = 0
        XCTAssertThrowsError(try ConfigurationStore.validate(c)) {
            XCTAssertEqual($0 as? ConfigError, .invalidTiming("pollIntervalSeconds"))
        }
    }
}
