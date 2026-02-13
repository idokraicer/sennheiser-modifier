import Foundation

/// Abstraction over the Bluetooth transport layer.
/// Allows swapping RFCOMM for a mock in tests.
protocol BluetoothTransport: AnyObject {
    var isConnected: Bool { get }
    var onDataReceived: ((Data) -> Void)? { get set }
    var onConnected: (() -> Void)? { get set }
    var onDisconnected: (() -> Void)? { get set }

    func connect(to address: String) async throws
    func disconnect()
    func send(_ data: Data) throws
}

/// A mock transport for testing the GAIA protocol layer without real Bluetooth.
/// Responds to known GET commands with hardcoded test data matching the C++ demo mode.
final class MockTransport: BluetoothTransport {
    var isConnected = false
    var onDataReceived: ((Data) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    /// Queued responses to deliver for testing
    var queuedResponses: [Data] = []

    /// All data that was sent through this transport
    var sentData: [Data] = []

    /// Whether to auto-respond with demo data
    var autoRespond = true

    func connect(to address: String) async throws {
        isConnected = true
        onConnected?()
    }

    func disconnect() {
        isConnected = false
        onDisconnected?()
    }

    func send(_ data: Data) throws {
        guard isConnected else { throw TransportError.notConnected }
        sentData.append(data)

        if !queuedResponses.isEmpty {
            let response = queuedResponses.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.onDataReceived?(response)
            }
            return
        }

        guard autoRespond else { return }

        // Auto-respond to known GET commands with demo data
        if let response = demoResponse(for: data) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.onDataReceived?(response)
            }
        }
    }

    private func demoResponse(for request: Data) -> Data? {
        // Match known GET commands from the C++ demo mode
        let hex = request.map { String(format: "%02x", $0) }.joined()

        switch hex {
        // Battery Percent GET → 42%
        case "ff03000004950603":
            return Data([0xFF, 0x03, 0x00, 0x02, 0x04, 0x95, 0x07, 0x03, 0x00, 0x2A])

        // Battery Charging GET → not charging
        case "ff03000004950602":
            return Data([0xFF, 0x03, 0x00, 0x02, 0x04, 0x95, 0x07, 0x02, 0x00, 0x00])

        // ANC GET → [01, 02, 02, 00, 03, 01]
        case "ff030000049s1a01", "ff0300000495la01":
            return Data([0xFF, 0x03, 0x00, 0x06, 0x04, 0x95, 0x1B, 0x01,
                         0x01, 0x02, 0x02, 0x00, 0x03, 0x01])

        // ANC Status GET → enabled
        case "ff0300000495la05":
            return Data([0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1B, 0x05, 0x01])

        // ANC Transparency GET → 0
        case "ff0300000495la03":
            return Data([0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1B, 0x03, 0x00])

        // Serial Number GET → "123456789012"
        case "ff030000001d0003":
            var resp = Data([0xFF, 0x03, 0x00, 0x0C, 0x00, 0x1D, 0x01, 0x03])
            resp.append("123456789012".data(using: .utf8)!)
            return resp

        // Firmware Version GET → 0.42, 0.24, 0.42
        case "ff0300000495l201":
            return Data([0xFF, 0x03, 0x00, 0x06, 0x04, 0x95, 0x13, 0x01,
                         0x00, 0x2A, 0x00, 0x18, 0x00, 0x2A])

        // Model ID GET → "MMMMBT Black"
        case "ff0300000495l206":
            var resp = Data([0xFF, 0x03, 0x00, 0x0C, 0x04, 0x95, 0x13, 0x06])
            resp.append("MMMMBT Black".data(using: .utf8)!)
            return resp

        // Paired Devices List Size GET → 4
        case "ff0300000495l400":
            return Data([0xFF, 0x03, 0x00, 0x02, 0x04, 0x95, 0x15, 0x00, 0x00, 0x04])

        default:
            return nil
        }
    }
}

enum TransportError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to device"
        case .connectionFailed(let msg): "Connection failed: \(msg)"
        case .sendFailed(let msg): "Send failed: \(msg)"
        }
    }
}
