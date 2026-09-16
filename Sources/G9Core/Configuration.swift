import Foundation

/// One monitor input mapping (label + DDC value + whether the user has
/// visually confirmed it).
public struct InputProfile: Codable, Equatable, Sendable {
    public var label: String
    public var value: UInt8
    public var calibrated: Bool

    public init(label: String, value: UInt8, calibrated: Bool) {
        self.label = label
        self.value = value
        self.calibrated = calibrated
    }
}

public struct MonitorInputs: Codable, Equatable, Sendable {
    public var mac: InputProfile
    public var windows: InputProfile

    public init(mac: InputProfile, windows: InputProfile) {
        self.mac = mac
        self.windows = windows
    }
}

public struct MonitorConfig: Codable, Equatable, Sendable {
    /// Resolved at runtime; `nil` for a fresh install (must be discovered).
    public var displayUUID: String?
    public var model: String
    /// DDC VCP feature for input selection; 96 == 0x60 on this device.
    public var vcpFeature: UInt8
    public var inputs: MonitorInputs

    public init(displayUUID: String?, model: String, vcpFeature: UInt8, inputs: MonitorInputs) {
        self.displayUUID = displayUUID
        self.model = model
        self.vcpFeature = vcpFeature
        self.inputs = inputs
    }
}

public struct KeyboardConfig: Codable, Equatable, Sendable {
    public var name: String
    public var vendorID: Int
    public var productID: Int
    /// Local address/identifier captured at discovery; disambiguates identical models.
    public var localIdentifier: String?

    public init(name: String, vendorID: Int, productID: Int, localIdentifier: String?) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.localIdentifier = localIdentifier
    }
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

    public init(
        mode: AutomationMode,
        pollIntervalSeconds: Double,
        departureDebounceSeconds: Double,
        arrivalDebounceSeconds: Double,
        cooldownSeconds: Double,
        resumeSettleSeconds: Double,
        manualHoldoffSeconds: Double,
        pauseWhenLocked: Bool
    ) {
        self.mode = mode
        self.pollIntervalSeconds = pollIntervalSeconds
        self.departureDebounceSeconds = departureDebounceSeconds
        self.arrivalDebounceSeconds = arrivalDebounceSeconds
        self.cooldownSeconds = cooldownSeconds
        self.resumeSettleSeconds = resumeSettleSeconds
        self.manualHoldoffSeconds = manualHoldoffSeconds
        self.pauseWhenLocked = pauseWhenLocked
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var monitor: MonitorConfig
    public var keyboard: KeyboardConfig
    public var automation: AutomationConfig
    public var launchAtLogin: Bool

    public init(
        schemaVersion: Int,
        monitor: MonitorConfig,
        keyboard: KeyboardConfig,
        automation: AutomationConfig,
        launchAtLogin: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.monitor = monitor
        self.keyboard = keyboard
        self.automation = automation
        self.launchAtLogin = launchAtLogin
    }

    /// The verified G95NC candidate profile (spec §11). Identities null and
    /// calibration false for a fresh install even though this session confirmed
    /// the mappings.
    public static var g95ncDefault: Configuration {
        Configuration(
            schemaVersion: 1,
            monitor: MonitorConfig(
                displayUUID: nil,
                model: "Odyssey G95NC",
                vcpFeature: 96,
                inputs: MonitorInputs(
                    mac: InputProfile(label: "HDMI 3", value: 7, calibrated: false),
                    windows: InputProfile(label: "HDMI 1", value: 5, calibrated: false)
                )
            ),
            keyboard: KeyboardConfig(
                name: "MX KEYS S",
                vendorID: 1133,
                productID: 45944,
                localIdentifier: nil
            ),
            automation: AutomationConfig(
                mode: .manual,
                pollIntervalSeconds: 1,
                departureDebounceSeconds: 3,
                arrivalDebounceSeconds: 1,
                cooldownSeconds: 5,
                resumeSettleSeconds: 10,
                manualHoldoffSeconds: 10,
                pauseWhenLocked: true
            ),
            launchAtLogin: false
        )
    }
}
