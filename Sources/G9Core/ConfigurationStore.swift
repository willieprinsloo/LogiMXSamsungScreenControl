import Foundation

public enum ConfigError: Error, Equatable {
    case unsupportedSchema(Int)
    case duplicateInputValue(UInt8)
    case invalidInputValue(UInt8)
    case invalidVCPFeature(UInt8)
    case invalidDeviceID
    case invalidTiming(String)
}

/// Loads, validates, and atomically persists `Configuration`.
public final class ConfigurationStore {
    private let directory: URL
    private let fileManager: FileManager
    private let fileName = "config.json"

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    /// Returns `nil` when no config file exists yet.
    public func load() throws -> Configuration? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    /// Validates then writes atomically (temp file + replace).
    public func save(_ config: Configuration) throws {
        try Self.validate(config)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let tmp = directory.appendingPathComponent(".config.json.\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        // Replace existing file atomically; if none exists, move into place.
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tmp)
        } else {
            try fileManager.moveItem(at: tmp, to: fileURL)
        }
    }

    public static func validate(_ config: Configuration) throws {
        guard config.schemaVersion == 1 else {
            throw ConfigError.unsupportedSchema(config.schemaVersion)
        }
        guard config.monitor.vcpFeature != 0 else {
            throw ConfigError.invalidVCPFeature(config.monitor.vcpFeature)
        }
        let mac = config.monitor.inputs.mac.value
        let win = config.monitor.inputs.windows.value
        for v in [mac, win] where v == 0 {
            throw ConfigError.invalidInputValue(v)
        }
        guard mac != win else { throw ConfigError.duplicateInputValue(mac) }
        guard config.keyboard.vendorID > 0, config.keyboard.productID > 0 else {
            throw ConfigError.invalidDeviceID
        }
        let a = config.automation
        let positives: [(String, Double)] = [
            ("pollIntervalSeconds", a.pollIntervalSeconds),
            ("cooldownSeconds", a.cooldownSeconds),
            ("resumeSettleSeconds", a.resumeSettleSeconds),
            ("manualHoldoffSeconds", a.manualHoldoffSeconds),
        ]
        for (name, value) in positives where value <= 0 {
            throw ConfigError.invalidTiming(name)
        }
        let nonNegatives: [(String, Double)] = [
            ("departureDebounceSeconds", a.departureDebounceSeconds),
            ("arrivalDebounceSeconds", a.arrivalDebounceSeconds),
        ]
        for (name, value) in nonNegatives where value < 0 {
            throw ConfigError.invalidTiming(name)
        }
    }
}
