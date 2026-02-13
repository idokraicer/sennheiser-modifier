import Foundation

/// A device paired with the headphones
struct PairedDevice: Identifiable, Equatable {
    let index: UInt8
    let connectionState: UInt8
    let deviceType: UInt8
    let name: String

    var id: UInt8 { index }

    var isConnected: Bool {
        connectionState == 1
    }

    var displayConnectionState: String {
        isConnected ? "Connected" : "Not Connected"
    }
}
