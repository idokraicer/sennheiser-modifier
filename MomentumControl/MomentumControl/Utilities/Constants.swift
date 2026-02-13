import Foundation

enum Constants {
    /// BLE service UUID used by Sennheiser devices for discovery
    static let sennheiserBLEServiceUUID = "0000FCFE-0000-1000-8000-00805F9B34FB"

    /// GAIA v3 packet header bytes
    static let gaiaHeader: [UInt8] = [0xFF, 0x03]

    /// Sennheiser vendor ID for most commands
    static let sennheiserVendorID: UInt16 = 0x0495

    /// Qualcomm core vendor ID
    static let qualcommVendorID: UInt16 = 0x001D

    /// GAIA header size (header 2 + length 2 + vendor 2 + command 2)
    static let gaiaHeaderSize = 8

    /// Minimum packet size for valid GAIA packet
    static let gaiaMinPacketSize = 8

    /// Demo device address for testing
    static let demoDeviceAddress = "11:11:11:11:11:11"
}
