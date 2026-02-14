import Foundation

/// Observable state model for the connected headphone.
/// All properties are updated from GAIA responses via the ViewModel.
@Observable
final class DeviceState {
    // MARK: - Connection
    var connectionStatus: ConnectionStatus = .disconnected
    var deviceAddress: String?

    // MARK: - Device Info
    var deviceName: String = "Sennheiser Momentum 4"
    var serialNumber: String?
    var firmwareVersion: String?
    var modelID: String?

    // MARK: - Battery
    var batteryPercent: Int = 0
    var batterySource: UInt8 = 0  // First byte from Battery_Percent response
    var isCharging: Bool = false

    // MARK: - ANC
    var ancEnabled: Bool = false
    var ancMode: ANCMode = .off
    var ancTransparencyLevel: Int = 0  // 0-255
    var antiWindEnabled: Bool = false
    var antiWindValue: Int = 0
    var adaptiveModeEnabled: Bool = false

    // MARK: - Transparent Hearing
    var transparentHearingEnabled: Bool = false

    // MARK: - Audio
    var bassBoostEnabled: Bool = false

    // MARK: - Settings
    var autoCallEnabled: Bool = false
    var comfortCallEnabled: Bool = false

    // MARK: - Paired Devices
    var pairedDeviceCount: Int = 0
    var pairedDevices: [PairedDevice] = []

    // MARK: - Computed

    var batteryIcon: String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch batteryPercent {
        case 0..<10: return "battery.0"
        case 10..<35: return "battery.25"
        case 35..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Derive ANC mode from enabled status and transparency.
    /// TransparentHearing takes priority: if it's on, we're in transparency mode
    /// regardless of ANC status.
    var effectiveANCMode: ANCMode {
        get {
            if transparentHearingEnabled { return .transparency }
            if ancEnabled { return .anc }
            return .off
        }
        set {
            ancMode = newValue
        }
    }

    /// Reset all state to defaults
    func reset() {
        connectionStatus = .disconnected
        deviceAddress = nil
        deviceName = "Sennheiser Momentum 4"
        serialNumber = nil
        firmwareVersion = nil
        modelID = nil
        batteryPercent = 0
        isCharging = false
        ancEnabled = false
        ancMode = .off
        ancTransparencyLevel = 0
        antiWindEnabled = false
        antiWindValue = 0
        adaptiveModeEnabled = false
        transparentHearingEnabled = false
        bassBoostEnabled = false
        autoCallEnabled = false
        comfortCallEnabled = false
        pairedDeviceCount = 0
        pairedDevices = []
    }
}
