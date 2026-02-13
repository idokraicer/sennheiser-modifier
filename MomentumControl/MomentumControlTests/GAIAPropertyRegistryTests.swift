import Foundation
import Testing
@testable import MomentumControl

@Suite("GAIAPropertyRegistry Tests")
struct GAIAPropertyRegistryTests {

    @Test("Lookup battery percent response")
    func lookupBatteryPercent() {
        let registry = GAIAPropertyRegistry()
        let result = registry.lookup(vendorID: 0x0495, commandID: 0x0703)

        #expect(result != nil)
        #expect(result?.0.name == "Battery_Percent")
    }

    @Test("Lookup ANC response")
    func lookupANC() {
        let registry = GAIAPropertyRegistry()
        let result = registry.lookup(vendorID: 0x0495, commandID: 0x1B01)

        #expect(result != nil)
        #expect(result?.0.name == "ANC")
    }

    @Test("Lookup ANC Status response")
    func lookupANCStatus() {
        let registry = GAIAPropertyRegistry()
        let result = registry.lookup(vendorID: 0x0495, commandID: 0x1B05)

        #expect(result != nil)
        #expect(result?.0.name == "ANC_Status")
    }

    @Test("Lookup serial number response")
    func lookupSerialNumber() {
        let registry = GAIAPropertyRegistry()
        let result = registry.lookup(vendorID: 0x001D, commandID: 0x0103)

        #expect(result != nil)
        #expect(result?.0.name == "Core_SerialNumber")
    }

    @Test("Lookup paired device info response")
    func lookupPairedDeviceInfo() {
        let registry = GAIAPropertyRegistry()
        let result = registry.lookup(vendorID: 0x0495, commandID: 0x1501)

        #expect(result != nil)
        #expect(result?.0.name == "PairedDevicesGetDeviceInfo")
    }

    @Test("Lookup unknown command returns nil")
    func lookupUnknown() {
        let registry = GAIAPropertyRegistry()
        #expect(registry.lookup(vendorID: 0xFFFF, commandID: 0xFFFF) == nil)
    }

    @Test("Parse battery response packet")
    func parseBatteryResponse() {
        let registry = GAIAPropertyRegistry()
        let packet = GAIAPacket(vendorID: 0x0495, commandID: 0x0703,
                                 payload: Data([0x00, 0x2A]))
        let result = registry.parseResponse(packet: packet)

        #expect(result != nil)
        #expect(result?.0.name == "Battery_Percent")
        #expect(result?.1.count == 2)
        #expect(result?.1[1] == .uint8(42))
    }

    @Test("Parse ANC response packet")
    func parseANCResponse() {
        let registry = GAIAPropertyRegistry()
        let packet = GAIAPacket(vendorID: 0x0495, commandID: 0x1B01,
                                 payload: Data([0x01, 0x02, 0x02, 0x00, 0x03, 0x01]))
        let result = registry.parseResponse(packet: packet)

        #expect(result != nil)
        #expect(result?.0.name == "ANC")
        #expect(result?.1.count == 6)
        #expect(result?.1[1] == .uint8(0x02))
        #expect(result?.1[5] == .uint8(0x01))
    }

    @Test("Parse firmware version response")
    func parseFirmwareVersion() {
        let registry = GAIAPropertyRegistry()
        let packet = GAIAPacket(vendorID: 0x0495, commandID: 0x1301,
                                 payload: Data([0x00, 0x2A, 0x00, 0x18, 0x00, 0x2A]))
        let result = registry.parseResponse(packet: packet)

        #expect(result != nil)
        #expect(result?.0.name == "Service_SystemReleaseVersion")
        #expect(result?.1.count == 3)
        #expect(result?.1[0] == .uint16(42))
        #expect(result?.1[1] == .uint16(24))
    }

    @Test("Lookup SET response commands")
    func lookupSetResponses() {
        let registry = GAIAPropertyRegistry()

        // ANC_Status SET response
        #expect(registry.lookup(vendorID: 0x0495, commandID: 0x1B04)?.0.name == "ANC_Status")

    }

    @Test("Build GET packets from definitions")
    func buildGetPackets() {
        let battery = GAIAPropertyDefinition.batteryPercent.buildGetPacket()
        #expect(battery != nil)
        #expect(battery?.encode() == Data([0xFF, 0x03, 0x00, 0x00, 0x04, 0x95, 0x06, 0x03]))

        let serial = GAIAPropertyDefinition.serialNumber.buildGetPacket()
        #expect(serial != nil)
        #expect(serial?.encode() == Data([0xFF, 0x03, 0x00, 0x00, 0x00, 0x1D, 0x00, 0x03]))
    }

    @Test("Build SET packet with values")
    func buildSetPacket() {
        let packet = GAIAPropertyDefinition.ancStatus.buildSetPacket(values: [.uint8(0x01)])

        #expect(packet != nil)
        #expect(packet?.encode() == Data([0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1A, 0x04, 0x01]))
    }
}
