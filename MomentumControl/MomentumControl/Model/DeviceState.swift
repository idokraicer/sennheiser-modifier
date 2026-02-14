import Foundation
import SwiftUI

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

    /// Unified slider value (0–100).
    /// 0–39 = ANC zone, 40–60 = Off zone, 61–100 = Transparency zone.
    var unifiedSliderValue: Double {
        if transparentHearingEnabled {
            return 61.0 + 39.0 // Full transparency = 100
        } else if ancEnabled {
            let mapped = Double(ancTransparencyLevel) / 100.0 * 39.0
            return mapped
        } else {
            return 50.0 // Off
        }
    }

    /// Dynamic accent color based on current ANC mode.
    var ancAccentColor: Color {
        if adaptiveModeEnabled {
            return Color(red: 0.55, green: 0.45, blue: 0.85) // Soft purple
        }
        if transparentHearingEnabled {
            return Color(red: 0.9, green: 0.65, blue: 0.3)   // Warm amber
        }
        if ancEnabled {
            return Color(red: 0.3, green: 0.6, blue: 0.95)   // Cool blue
        }
        return Color.gray
    }

    /// Accent color for a specific unified slider position (for continuous color shift).
    static func accentColor(forSliderValue value: Double) -> Color {
        if value <= 39 {
            let intensity = 1.0 - (value / 39.0) * 0.3
            return Color(red: 0.3 * intensity, green: 0.6 * intensity, blue: 0.95)
        } else if value >= 61 {
            let intensity = 0.7 + ((value - 61.0) / 39.0) * 0.3
            return Color(red: 0.9 * intensity, green: 0.65 * intensity, blue: 0.3)
        } else {
            return Color.gray
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
