import Foundation
import IOBluetooth
import os

/// RFCOMM Bluetooth transport using IOBluetooth framework.
/// Connects to Sennheiser headphones via classic Bluetooth RFCOMM.
final class RFCOMMChannel: NSObject, BluetoothTransport {
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private let logger = Logger(subsystem: "com.momentumcontrol", category: "RFCOMM")

    private(set) var isConnected = false
    var onDataReceived: ((Data) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    /// The RFCOMM channel ID to use (default 1 for GAIA)
    private let channelID: BluetoothRFCOMMChannelID

    init(channelID: BluetoothRFCOMMChannelID = 1) {
        self.channelID = channelID
        super.init()
    }

    func connect(to address: String) async throws {
        logger.info("Connecting to \(address) on channel \(self.channelID)")

        guard let btDevice = IOBluetoothDevice(addressString: address) else {
            throw TransportError.connectionFailed("Invalid Bluetooth address: \(address)")
        }

        self.device = btDevice

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var rfcommChannel: IOBluetoothRFCOMMChannel?
            let result = btDevice.openRFCOMMChannelAsync(
                &rfcommChannel,
                withChannelID: channelID,
                delegate: self
            )

            if result != kIOReturnSuccess {
                continuation.resume(throwing: TransportError.connectionFailed(
                    "openRFCOMMChannelAsync failed with code: \(result)"
                ))
                return
            }

            self.channel = rfcommChannel

            // Store continuation to resolve when delegate callback fires
            self.connectionContinuation = continuation
        }
    }

    func disconnect() {
        logger.info("Disconnecting RFCOMM")
        channel?.close()
        channel = nil
        device?.closeConnection()
        device = nil
        if isConnected {
            isConnected = false
            onDisconnected?()
        }
    }

    func send(_ data: Data) throws {
        guard isConnected, let channel = channel else {
            throw TransportError.notConnected
        }

        let bytes = [UInt8](data)
        let result = bytes.withUnsafeBufferPointer { buffer in
            channel.writeAsync(
                UnsafeMutableRawPointer(mutating: buffer.baseAddress!),
                length: UInt16(data.count),
                refcon: nil
            )
        }

        if result != kIOReturnSuccess {
            throw TransportError.sendFailed("Write failed with code: \(result)")
        }
    }

    // Used to bridge async/await with delegate callbacks
    private var connectionContinuation: CheckedContinuation<Void, Error>?
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension RFCOMMChannel: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            logger.info("RFCOMM channel opened successfully")
            isConnected = true
            onConnected?()
            connectionContinuation?.resume()
        } else {
            logger.error("RFCOMM channel open failed: \(error)")
            connectionContinuation?.resume(throwing: TransportError.connectionFailed(
                "Channel open failed with code: \(error)"
            ))
        }
        connectionContinuation = nil
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                            data dataPointer: UnsafeMutableRawPointer!,
                            length dataLength: Int) {
        guard let dataPointer = dataPointer else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        logger.debug("RFCOMM received \(dataLength) bytes")
        onDataReceived?(data)
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        logger.info("RFCOMM channel closed")
        isConnected = false
        channel = nil
        onDisconnected?()
    }
}
