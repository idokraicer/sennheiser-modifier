import Foundation
import os

/// Orchestrates GAIA v3 protocol communication over a BluetoothTransport.
/// Handles packet encoding, sending, receiving, splitting, and response routing.
@Observable
final class GAIAConnection {
    private let transport: BluetoothTransport
    private let registry: GAIAPropertyRegistry
    private let logger = Logger(subsystem: "com.momentumcontrol", category: "GAIA")

    /// Buffer for incomplete incoming data
    private var receiveBuffer = Data()

    /// Callback when a property value is received
    var onPropertyReceived: ((GAIAPropertyDefinition, [GAIAValue]) -> Void)?

    /// Callback when an unrecognized packet is received (vendor, command, payload)
    var onUnknownPacket: ((UInt16, UInt16, Data) -> Void)?

    /// Callback when the transport disconnects (remote device lost)
    var onDisconnected: (() -> Void)?

    /// Whether the transport is currently connected
    var isConnected: Bool { transport.isConnected }

    init(transport: BluetoothTransport, registry: GAIAPropertyRegistry = GAIAPropertyRegistry()) {
        self.transport = transport
        self.registry = registry

        transport.onDataReceived = { [weak self] data in
            self?.handleReceivedData(data)
        }

        transport.onConnected = { [weak self] in
            self?.logger.info("Transport connected")
        }

        transport.onDisconnected = { [weak self] in
            self?.logger.info("Transport disconnected")
            self?.receiveBuffer.removeAll()
            self?.onDisconnected?()
        }
    }

    // MARK: - Sending

    /// Send a GET request for a property
    func sendGet(for property: GAIAPropertyDefinition) {
        guard let packet = property.buildGetPacket() else {
            logger.warning("Cannot build GET for \(property.name)")
            return
        }
        send(packet)
    }

    /// Send a SET command for a property
    func sendSet(for property: GAIAPropertyDefinition, values: [GAIAValue]) {
        guard let packet = property.buildSetPacket(values: values) else {
            logger.warning("Cannot build SET for \(property.name)")
            return
        }
        send(packet)
    }

    /// Send an INVOCATION command for a property
    func sendInvocation(for property: GAIAPropertyDefinition, parameters: [GAIAValue]) {
        guard let packet = property.buildInvocationPacket(parameters: parameters) else {
            logger.warning("Cannot build INVOCATION for \(property.name)")
            return
        }
        send(packet)
    }

    /// Send a raw GAIA packet
    func send(_ packet: GAIAPacket) {
        let data = packet.encode()
        logger.debug("TX: \(data.hexString)")
        do {
            try transport.send(data)
        } catch {
            logger.error("Send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Receiving

    private func handleReceivedData(_ data: Data) {
        logger.debug("RX: \(data.hexString)")

        // Append to buffer and try to extract complete packets
        receiveBuffer.append(data)
        processBuffer()
    }

    private func processBuffer() {
        let packets = GAIAPacket.splitPackets(from: receiveBuffer)

        // Calculate how many bytes were consumed
        var consumed = 0
        for packet in packets {
            consumed += Int(packet.payload.count) + Constants.gaiaHeaderSize
        }

        // Remove consumed bytes from buffer
        if consumed > 0 {
            receiveBuffer = Data(receiveBuffer.dropFirst(consumed))
        }

        // Route each packet through the registry
        for packet in packets {
            if let (property, values) = registry.parseResponse(packet: packet) {
                logger.info("Parsed \(property.name): \(values)")
                onPropertyReceived?(property, values)
            } else {
                logger.debug("Unknown response: vendor=\(String(format: "0x%04X", packet.vendorID)) cmd=\(String(format: "0x%04X", packet.commandID))")
                onUnknownPacket?(packet.vendorID, packet.commandID, packet.payload)
            }
        }
    }

    // MARK: - Connection

    func connect(to address: String) async throws {
        try await transport.connect(to: address)
    }

    func disconnect() {
        transport.disconnect()
    }
}
