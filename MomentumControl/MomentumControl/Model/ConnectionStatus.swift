import Foundation

enum ConnectionStatus: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning..."
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }
}
