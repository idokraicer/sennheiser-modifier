import Foundation

/// Types of values that can appear in GAIA property payloads
enum GAIAValueType: Sendable {
    case uint8
    case uint16
    case uint32
    case string
    case bool
    case none

    /// Fixed byte size for this type, or nil for variable-length types (string)
    var byteSize: Int? {
        switch self {
        case .uint8: 1
        case .uint16: 2
        case .uint32: 4
        case .bool: 1
        case .none: 0
        case .string: nil
        }
    }
}

/// A parsed GAIA value
enum GAIAValue: Equatable, Sendable {
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case string(String)
    case bool(Bool)

    var asUInt8: UInt8? {
        if case .uint8(let v) = self { return v }
        return nil
    }

    var asUInt16: UInt16? {
        if case .uint16(let v) = self { return v }
        return nil
    }

    var asUInt32: UInt32? {
        if case .uint32(let v) = self { return v }
        return nil
    }

    var asString: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var asBool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var asInt: Int {
        switch self {
        case .uint8(let v): Int(v)
        case .uint16(let v): Int(v)
        case .uint32(let v): Int(v)
        case .bool(let v): v ? 1 : 0
        case .string: 0
        }
    }
}

/// Parses and encodes typed values from/to raw GAIA payload bytes
enum GAIAValueParser {

    /// Parse a list of typed values from raw payload data
    static func parse(data: Data, types: [GAIAValueType]) -> [GAIAValue] {
        var values: [GAIAValue] = []
        var offset = 0

        for type in types {
            guard offset < data.count else { break }

            switch type {
            case .uint8:
                guard let raw = data.readUInt8(at: offset) else { break }
                values.append(.uint8(raw))
                offset += 1

            case .uint16:
                guard let raw = data.readUInt16BE(at: offset) else { break }
                values.append(.uint16(raw))
                offset += 2

            case .uint32:
                guard let raw = data.readUInt32BE(at: offset) else { break }
                values.append(.uint32(raw))
                offset += 4

            case .bool:
                guard let raw = data.readUInt8(at: offset) else { break }
                values.append(.bool(raw != 0x00))
                offset += 1

            case .string:
                // String consumes all remaining data
                guard let str = data.readString(at: offset) else { break }
                values.append(.string(str))
                offset = data.count

            case .none:
                continue
            }
        }

        return values
    }

    /// Encode a list of typed values into raw payload bytes
    static func encode(values: [GAIAValue]) -> Data {
        var data = Data()

        for value in values {
            switch value {
            case .uint8(let v):
                data.appendUInt8(v)
            case .uint16(let v):
                data.appendUInt16BE(v)
            case .uint32(let v):
                data.appendUInt32BE(v)
            case .bool(let v):
                data.appendUInt8(v ? 0x01 : 0x00)
            case .string(let v):
                data.appendString(v)
            }
        }

        return data
    }
}
