import XCTest
@testable import G9Core

final class KeyboardJSONParsingTests: XCTestCase {
    private let kbdName = "MX KEYS S"

    private func status(_ json: String, localIdentifier: String? = nil) -> ConnectionState {
        KeyboardStatusParser.status(fromJSON: Data(json.utf8), deviceName: kbdName, localIdentifier: localIdentifier)
    }

    func testConnectedByName() {
        let json = """
        { "SPBluetoothDataType": [ {
            "device_connected": [ { "MX KEYS S": { "device_address": "AA-BB-CC" } } ],
            "device_not_connected": [ { "Old Mouse": {} } ]
        } ] }
        """
        XCTAssertEqual(status(json), .connected)
    }

    func testDisconnectedByName() {
        let json = """
        { "SPBluetoothDataType": [ {
            "device_connected": [ { "Some Headset": {} } ],
            "device_not_connected": [ { "MX KEYS S": { "device_address": "AA-BB-CC" } } ]
        } ] }
        """
        XCTAssertEqual(status(json), .disconnected)
    }

    func testMissingFromBothIsUnknown() {
        let json = """
        { "SPBluetoothDataType": [ {
            "device_connected": [ { "Some Headset": {} } ],
            "device_not_connected": [ { "Old Mouse": {} } ]
        } ] }
        """
        XCTAssertEqual(status(json), .unknown)
    }

    func testContradictoryIsUnknown() {
        let json = """
        { "SPBluetoothDataType": [ {
            "device_connected": [ { "MX KEYS S": {} } ],
            "device_not_connected": [ { "MX KEYS S": {} } ]
        } ] }
        """
        XCTAssertEqual(status(json), .unknown)
    }

    func testMalformedIsUnknown() {
        XCTAssertEqual(status("{ not json"), .unknown)
        XCTAssertEqual(status("{}"), .unknown)
    }

    func testAddressMatchDisambiguatesDuplicateNames() {
        // Two identically-named keyboards; select by saved address.
        let json = """
        { "SPBluetoothDataType": [ {
            "device_connected": [ { "MX KEYS S": { "device_address": "11-22-33" } } ],
            "device_not_connected": [ { "MX KEYS S": { "device_address": "AA-BB-CC" } } ]
        } ] }
        """
        XCTAssertEqual(status(json, localIdentifier: "AA-BB-CC"), .disconnected)
        XCTAssertEqual(status(json, localIdentifier: "11-22-33"), .connected)
    }
}
