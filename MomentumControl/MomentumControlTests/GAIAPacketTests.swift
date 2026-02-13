import Foundation
import Testing
@testable import MomentumControl

@Suite("GAIAPacket Tests")
struct GAIAPacketTests {

    // MARK: - Encoding

    @Test("Encode GET command with no payload")
    func encodeGetCommand() {
        let packet = GAIAPacket.get(vendorID: 0x0495, commandID: 0x0603)
        let encoded = packet.encode()

        #expect(encoded == Data([0xFF, 0x03, 0x00, 0x00, 0x04, 0x95, 0x06, 0x03]))
    }

    @Test("Encode serial number GET")
    func encodeSerialNumberGet() {
        let packet = GAIAPacket.get(vendorID: 0x001D, commandID: 0x0003)
        let encoded = packet.encode()

        #expect(encoded == Data([0xFF, 0x03, 0x00, 0x00, 0x00, 0x1D, 0x00, 0x03]))
    }

    @Test("Encode SET command with payload")
    func encodeSetCommand() {
        let payload = Data([0x01])
        let packet = GAIAPacket.command(vendorID: 0x0495, commandID: 0x1A04, payload: payload)
        let encoded = packet.encode()

        #expect(encoded == Data([0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1A, 0x04, 0x01]))
    }

    @Test("Encode invocation with parameter")
    func encodeInvocation() {
        // PairedDevicesGetDeviceInfo with index 0
        let payload = Data([0x00])
        let packet = GAIAPacket.command(vendorID: 0x0495, commandID: 0x1401, payload: payload)
        let encoded = packet.encode()

        #expect(encoded == Data([0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x14, 0x01, 0x00]))
    }

    // MARK: - Decoding

    @Test("Decode battery percent response")
    func decodeBatteryResponse() {
        let data = Data([0xFF, 0x03, 0x00, 0x02, 0x04, 0x95, 0x07, 0x03, 0x00, 0x2A])
        let packet = GAIAPacket.decode(from: data)

        #expect(packet != nil)
        #expect(packet?.vendorID == 0x0495)
        #expect(packet?.commandID == 0x0703)
        #expect(packet?.payload == Data([0x00, 0x2A]))
    }

    @Test("Decode ANC response with 6 bytes")
    func decodeANCResponse() {
        let data = Data([0xFF, 0x03, 0x00, 0x06, 0x04, 0x95, 0x1B, 0x01,
                         0x01, 0x02, 0x02, 0x00, 0x03, 0x01])
        let packet = GAIAPacket.decode(from: data)

        #expect(packet != nil)
        #expect(packet?.vendorID == 0x0495)
        #expect(packet?.commandID == 0x1B01)
        #expect(packet?.payload.count == 6)
        #expect(packet?.payload == Data([0x01, 0x02, 0x02, 0x00, 0x03, 0x01]))
    }

    @Test("Decode serial number response with string")
    func decodeSerialNumberResponse() {
        var data = Data([0xFF, 0x03, 0x00, 0x0C, 0x00, 0x1D, 0x01, 0x03])
        data.append("123456789012".data(using: .utf8)!)

        let packet = GAIAPacket.decode(from: data)

        #expect(packet != nil)
        #expect(packet?.vendorID == 0x001D)
        #expect(packet?.commandID == 0x0103)
        #expect(packet?.payload.count == 12)
    }

    @Test("Decode returns nil for too-short data")
    func decodeTooShort() {
        let data = Data([0xFF, 0x03, 0x00])
        #expect(GAIAPacket.decode(from: data) == nil)
    }

    @Test("Decode returns nil for wrong header")
    func decodeWrongHeader() {
        let data = Data([0xFE, 0x03, 0x00, 0x00, 0x04, 0x95, 0x06, 0x03])
        #expect(GAIAPacket.decode(from: data) == nil)
    }

    // MARK: - Packet Splitting

    @Test("Split single packet")
    func splitSinglePacket() {
        let data = Data([0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x07, 0x03, 0x2A])
        let packets = GAIAPacket.splitPackets(from: data)

        #expect(packets.count == 1)
        #expect(packets[0].vendorID == 0x0495)
        #expect(packets[0].commandID == 0x0703)
    }

    @Test("Split two concatenated packets")
    func splitTwoPackets() {
        var data = Data()
        // Battery response (9 bytes)
        data.append(contentsOf: [0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x07, 0x03, 0x2A])
        // ANC status response (9 bytes)
        data.append(contentsOf: [0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1B, 0x05, 0x01])

        let packets = GAIAPacket.splitPackets(from: data)

        #expect(packets.count == 2)
        #expect(packets[0].commandID == 0x0703)
        #expect(packets[1].commandID == 0x1B05)
    }

    @Test("Split handles empty and short data")
    func splitEmptyData() {
        #expect(GAIAPacket.splitPackets(from: Data()).isEmpty)
        #expect(GAIAPacket.splitPackets(from: Data([0xFF, 0x03])).isEmpty)
    }

    // MARK: - Roundtrip

    @Test("Encode then decode roundtrip")
    func roundtrip() {
        let original = GAIAPacket(vendorID: 0x0495, commandID: 0x1A00,
                                   payload: Data([0x01, 0x02, 0x03]))
        let encoded = original.encode()
        let decoded = GAIAPacket.decode(from: encoded)

        #expect(decoded != nil)
        #expect(decoded?.vendorID == original.vendorID)
        #expect(decoded?.commandID == original.commandID)
        #expect(decoded?.payload == original.payload)
    }
}
