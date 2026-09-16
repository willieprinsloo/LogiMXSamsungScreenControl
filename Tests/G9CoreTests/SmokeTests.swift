import XCTest
@testable import G9Core

final class SmokeTests: XCTestCase {
    func testFakeClockAdvances() {
        let c = FakeClock(Date(timeIntervalSince1970: 0))
        c.advance(by: 5)
        XCTAssertEqual(c.now, Date(timeIntervalSince1970: 5))
    }

    func testAutomationModeRawValues() {
        XCTAssertEqual(AutomationMode(rawValue: "followBoth"), .followBoth)
        XCTAssertEqual(AutomationMode.allCases.count, 3)
    }
}
