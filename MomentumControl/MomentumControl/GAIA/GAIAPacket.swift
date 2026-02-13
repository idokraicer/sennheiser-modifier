import Foundation

/// Represents a decoded GAIA v3 packet
/// Format: [0xFF 0x03] [length: 2B BE] [vendorID: 2B BE] [commandID: 2B BE] [payload]
struct GAIAPacket {
    let vendorID: UInt16
    let commandID: UInt16
    let payload: Data

    /// Encode this packet into raw bytes for transmission
    func encode() -> Data {
        var data = Data()
        // Header
        data.append(contentsOf: Constants.gaiaHeader)
        // Payload length (big-endian UInt16)
        data.appendUInt16BE(UInt16(payload.count))
        // Vendor ID
        data.appendUInt16BE(vendorID)
        // Command ID
        data.appendUInt16BE(commandID)
        // Payload
        data.append(payload)
        return data
    }

    /// Create a GET command packet (no payload)
    static func get(vendorID: UInt16, commandID: UInt16) -> GAIAPacket {
        GAIAPacket(vendorID: vendorID, commandID: commandID, payload: Data())
    }

    /// Create a SET/INVOCATION command packet with typed payload values
    static func command(vendorID: UInt16, commandID: UInt16, payload: Data) -> GAIAPacket {
        GAIAPacket(vendorID: vendorID, commandID: commandID, payload: payload)
    }

    /// Decode a single packet from raw data. Returns nil if invalid.
    static func decode(from data: Data) -> GAIAPacket? {
        guard data.count >= Constants.gaiaMinPacketSize else { return nil }
        guard data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0x03 else { return nil }

        guard let payloadLength = data.readUInt16BE(at: 2),
              let vendorID = data.readUInt16BE(at: 4),
              let commandID = data.readUInt16BE(at: 6) else {
            return nil
        }

        let expectedTotal = Int(payloadLength) + Constants.gaiaHeaderSize
        guard data.count >= expectedTotal else { return nil }

        let payload: Data
        if payloadLength > 0 {
            let start = data.startIndex + Constants.gaiaHeaderSize
            let end = start + Int(payloadLength)
            payload = data[start..<end]
        } else {
            payload = Data()
        }

        return GAIAPacket(vendorID: vendorID, commandID: commandID, payload: payload)
    }

    /// Split a raw data stream into individual GAIA packets.
    /// Matches the C++ `packetSplitter()` logic.
    static func splitPackets(from data: Data) -> [GAIAPacket] {
        var packets: [GAIAPacket] = []
        var offset = 0

        while offset < data.count {
            let remaining = data.count - offset
            guard remaining >= 6 else { break }

            guard let payloadLength = data.readUInt16BE(at: offset + 2) else { break }
            let packetSize = Int(payloadLength) + Constants.gaiaHeaderSize
            guard remaining >= packetSize else { break }

            let packetData = data[data.startIndex + offset ..< data.startIndex + offset + packetSize]
            if let packet = GAIAPacket.decode(from: packetData) {
                packets.append(packet)
            }
            offset += packetSize
        }

        return packets
    }
}

extension GAIAPacket: CustomDebugStringConvertible {
    var debugDescription: String {
        "GAIAPacket(vendor: \(String(format: "0x%04X", vendorID)), cmd: \(String(format: "0x%04X", commandID)), payload: \(payload.hexString))"
    }
}
