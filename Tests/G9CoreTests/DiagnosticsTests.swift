import XCTest
@testable import G9Core

final class DiagnosticsTests: XCTestCase {

    func testMaxEventsBound() {
        let clock = FakeClock()
        let store = DiagnosticsStore(maxEvents: 3, maxAge: 3600, clock: clock)
        for i in 0..<5 {
            store.record(DiagnosticEvent(type: "poll-\(i)", localTime: clock.now))
        }
        let all = store.all()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map { $0.type }, ["poll-2", "poll-3", "poll-4"])
    }

    func testAgePruning() {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let store = DiagnosticsStore(maxEvents: 100, maxAge: 10, clock: clock)
        store.record(DiagnosticEvent(type: "old", localTime: clock.now))
        clock.advance(by: 20)
        store.record(DiagnosticEvent(type: "new", localTime: clock.now))
        XCTAssertEqual(store.all().map { $0.type }, ["new"])
    }

    func testExportRedactsSecrets() {
        let clock = FakeClock()
        let store = DiagnosticsStore(clock: clock)
        let uuid = "95493343-DBDA-457E-A630-9191EF7330E7"
        store.record(DiagnosticEvent(type: "switch", localTime: clock.now, targetInput: "mac", transportResult: "ok on \(uuid)"))
        let text = store.exportRedacted(secrets: [uuid])
        XCTAssertFalse(text.contains(uuid))
        XCTAssertTrue(text.contains("<redacted>"))
    }
}
