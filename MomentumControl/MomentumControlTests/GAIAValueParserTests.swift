import Foundation
import Testing
@testable import MomentumControl

@Suite("GAIAValueParser Tests")
struct GAIAValueParserTests {

    // MARK: - Parsing

    @Test("Parse single UINT8")
    func parseUInt8() {
        let data = Data([0x2A])
        let values = GAIAValueParser.parse(data: data, types: [.uint8])

        #expect(values.count == 1)
        #expect(values[0] == .uint8(0x2A))
        #expect(values[0].asUInt8 == 42)
    }

    @Test("Parse single UINT16")
    func parseUInt16() {
        let data = Data([0x00, 0x2A])
        let values = GAIAValueParser.parse(data: data, types: [.uint16])

        #expect(values.count == 1)
        #expect(values[0] == .uint16(42))
    }

    @Test("Parse single UINT32")
    func parseUInt32() {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        let values = GAIAValueParser.parse(data: data, types: [.uint32])

        #expect(values.count == 1)
        #expect(values[0] == .uint32(0x12345678))
    }

    @Test("Parse BOOL true")
    func parseBoolTrue() {
        let values = GAIAValueParser.parse(data: Data([0x01]), types: [.bool])
        #expect(values[0] == .bool(true))
    }

    @Test("Parse BOOL false")
    func parseBoolFalse() {
        let values = GAIAValueParser.parse(data: Data([0x00]), types: [.bool])
        #expect(values[0] == .bool(false))
    }

    @Test("Parse STRING")
    func parseString() {
        let data = "Hello".data(using: .utf8)!
        let values = GAIAValueParser.parse(data: data, types: [.string])

        #expect(values.count == 1)
        #expect(values[0] == .string("Hello"))
    }

    @Test("Parse battery percent: 2x UINT8")
    func parseBatteryPercent() {
        let data = Data([0x00, 0x2A])
        let values = GAIAValueParser.parse(data: data, types: [.uint8, .uint8])

        #expect(values.count == 2)
        #expect(values[0] == .uint8(0x00))
        #expect(values[1] == .uint8(0x2A))
    }

    @Test("Parse ANC: 6x UINT8")
    func parseANC() {
        let data = Data([0x01, 0x02, 0x02, 0x00, 0x03, 0x01])
        let values = GAIAValueParser.parse(data: data, types: [.uint8, .uint8, .uint8, .uint8, .uint8, .uint8])

        #expect(values.count == 6)
        #expect(values[1] == .uint8(0x02))  // anti-wind value
        #expect(values[3] == .uint8(0x00))  // comfort off
        #expect(values[5] == .uint8(0x01))  // adaptive on
    }

    @Test("Parse firmware version: 3x UINT16")
    func parseFirmwareVersion() {
        let data = Data([0x00, 0x2A, 0x00, 0x18, 0x00, 0x2A])
        let values = GAIAValueParser.parse(data: data, types: [.uint16, .uint16, .uint16])

        #expect(values.count == 3)
        #expect(values[0] == .uint16(42))
        #expect(values[1] == .uint16(24))
        #expect(values[2] == .uint16(42))
    }

    @Test("Parse paired device info: UINT8, UINT8, UINT8, STRING")
    func parsePairedDeviceInfo() {
        var data = Data([0x00, 0x01, 0x01])
        data.append("Motorola T2288".data(using: .utf8)!)

        let values = GAIAValueParser.parse(data: data, types: [.uint8, .uint8, .uint8, .string])

        #expect(values.count == 4)
        #expect(values[0] == .uint8(0x00))  // index
        #expect(values[1] == .uint8(0x01))  // connection state
        #expect(values[2] == .uint8(0x01))  // device type
        #expect(values[3] == .string("Motorola T2288"))
    }

    @Test("Parse handles truncated data gracefully")
    func parseTruncated() {
        let data = Data([0x42])
        let values = GAIAValueParser.parse(data: data, types: [.uint8, .uint16])

        // Should parse what it can
        #expect(values.count == 1)
        #expect(values[0] == .uint8(0x42))
    }

    // MARK: - Encoding

    @Test("Encode UINT8")
    func encodeUInt8() {
        let data = GAIAValueParser.encode(values: [.uint8(0x42)])
        #expect(data == Data([0x42]))
    }

    @Test("Encode UINT16")
    func encodeUInt16() {
        let data = GAIAValueParser.encode(values: [.uint16(0x1234)])
        #expect(data == Data([0x12, 0x34]))
    }

    @Test("Encode UINT32")
    func encodeUInt32() {
        let data = GAIAValueParser.encode(values: [.uint32(0x12345678)])
        #expect(data == Data([0x12, 0x34, 0x56, 0x78]))
    }

    @Test("Encode BOOL")
    func encodeBool() {
        #expect(GAIAValueParser.encode(values: [.bool(true)]) == Data([0x01]))
        #expect(GAIAValueParser.encode(values: [.bool(false)]) == Data([0x00]))
    }

    @Test("Encode STRING")
    func encodeString() {
        let data = GAIAValueParser.encode(values: [.string("Hi")])
        #expect(data == "Hi".data(using: .utf8))
    }

    @Test("Encode multiple values")
    func encodeMultiple() {
        let data = GAIAValueParser.encode(values: [.uint8(0x01), .uint8(0x00)])
        #expect(data == Data([0x01, 0x00]))
    }

    // MARK: - Roundtrip

    @Test("Encode/decode roundtrip for UINT8")
    func roundtripUInt8() {
        let original: [GAIAValue] = [.uint8(42)]
        let encoded = GAIAValueParser.encode(values: original)
        let decoded = GAIAValueParser.parse(data: encoded, types: [.uint8])
        #expect(decoded == original)
    }

    @Test("Encode/decode roundtrip for mixed types")
    func roundtripMixed() {
        let original: [GAIAValue] = [.uint8(1), .uint16(1000), .uint32(100000)]
        let encoded = GAIAValueParser.encode(values: original)
        let decoded = GAIAValueParser.parse(data: encoded, types: [.uint8, .uint16, .uint32])
        #expect(decoded == original)
    }
}
