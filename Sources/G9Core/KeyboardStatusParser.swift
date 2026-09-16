import Foundation

/// Parses `system_profiler SPBluetoothDataType -json` output structurally.
/// Never text-searches for "connected" ("not connected" contains it).
public enum KeyboardStatusParser {

    /// - Returns `.connected`/`.disconnected` only on an explicit match in the
    ///   corresponding list. Device absent from both, present in both, or any
    ///   parse failure => `.unknown`.
    public static func status(fromJSON data: Data, deviceName: String, localIdentifier: String?) -> ConnectionState {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let bt = root["SPBluetoothDataType"] as? [[String: Any]]
        else {
            return .unknown
        }

        var inConnected = false
        var inDisconnected = false

        for controller in bt {
            if matches(inList: controller["device_connected"], deviceName: deviceName, localIdentifier: localIdentifier) {
                inConnected = true
            }
            if matches(inList: controller["device_not_connected"], deviceName: deviceName, localIdentifier: localIdentifier) {
                inDisconnected = true
            }
        }

        switch (inConnected, inDisconnected) {
        case (true, false): return .connected
        case (false, true): return .disconnected
        default: return .unknown   // absent from both, or contradictory
        }
    }

    /// Each list is an array of single-key dictionaries: `[{ "<Device Name>": { ...props } }]`.
    private static func matches(inList list: Any?, deviceName: String, localIdentifier: String?) -> Bool {
        guard let entries = list as? [[String: Any]] else { return false }
        for entry in entries {
            for (name, props) in entry {
                if let id = localIdentifier, !id.isEmpty {
                    // Prefer address match when we have a saved identifier.
                    if let props = props as? [String: Any],
                       let address = (props["device_address"] as? String),
                       address.caseInsensitiveCompare(id) == .orderedSame {
                        return true
                    }
                } else if name.caseInsensitiveCompare(deviceName) == .orderedSame {
                    return true
                }
            }
        }
        return false
    }
}
