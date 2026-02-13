import Foundation

extension Data {
    /// Read a UInt8 at the given offset
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset < count else { return nil }
        return self[startIndex + offset]
    }

    /// Read a big-endian UInt16 at the given offset
    func readUInt16BE(at offset: Int) -> UInt16? {
        guard offset + 1 < count else { return nil }
        let hi = UInt16(self[startIndex + offset]) << 8
        let lo = UInt16(self[startIndex + offset + 1])
        return hi | lo
    }

    /// Read a big-endian UInt32 at the given offset
    func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset + 3 < count else { return nil }
        let b0 = UInt32(self[startIndex + offset]) << 24
        let b1 = UInt32(self[startIndex + offset + 1]) << 16
        let b2 = UInt32(self[startIndex + offset + 2]) << 8
        let b3 = UInt32(self[startIndex + offset + 3])
        return b0 | b1 | b2 | b3
    }

    /// Read a UTF-8 string from the given offset to the end, stripping null terminators
    func readString(at offset: Int) -> String? {
        guard offset < count else { return nil }
        let start = startIndex + offset
        // Find null terminator or use end
        var end = endIndex
        for i in start..<endIndex {
            if self[i] == 0x00 {
                end = i
                break
            }
        }
        let slice = self[start..<end]
        return String(data: Data(slice), encoding: .utf8)
    }

    /// Append a UInt8
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    /// Append a big-endian UInt16
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    /// Append a big-endian UInt32
    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    /// Append a UTF-8 string (no null terminator)
    mutating func appendString(_ value: String) {
        if let data = value.data(using: .utf8) {
            append(data)
        }
    }

    /// Hex string representation for debugging
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
