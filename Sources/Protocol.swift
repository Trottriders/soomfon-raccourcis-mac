import Foundation

// Protocol facts verified against mirajazz and opendeck-akp153; see REFERENCES.md.
enum DeckProtocol {
    static let vendor = 0x1500
    static let product = 0x3003
    static let usagePage = 0xFFA0
    static let packetSize = 1024

    // Three rows of five buttons followed by the three dashboard slots.
    static func address(for index: Int) -> UInt8 {
        precondition((0..<18).contains(index))
        if index >= 15 { return UInt8(index + 1) }
        return UInt8(13 - (index % 5) * 3 + index / 5)
    }

    static func index(for address: UInt8) -> Int? {
        guard (1...15).contains(Int(address)) else { return nil }
        let zero = Int(address) - 1
        return (zero % 3) * 5 + (4 - zero / 3)
    }

    static func event(_ bytes: [UInt8]) -> (index: Int?, down: Bool)? {
        guard bytes.count >= 11, Array(bytes.prefix(3)) == [0x41, 0x43, 0x4B],
              bytes[10] <= 1 else { return nil }
        if bytes[9] == 0 { return (nil, false) }
        guard let index = index(for: bytes[9]) else { return nil }
        return (index, bytes[10] == 1)
    }

    // IOHIDDeviceSetReport takes the report ID separately. Unlike HIDAPI's
    // 1025-byte buffer, the native macOS payload must NOT include that byte.
    static func command(_ name: String, tail: [UInt8] = []) -> [UInt8] {
        var bytes: [UInt8] = [0x43, 0x52, 0x54, 0, 0]
        bytes += Array(name.utf8)
        bytes += tail
        precondition(bytes.count <= packetSize)
        bytes += Array(repeating: 0, count: packetSize - bytes.count)
        return bytes
    }

    static func imagePackets(_ jpeg: Data, index: Int) -> [[UInt8]] {
        precondition(!jpeg.isEmpty && jpeg.count <= 65535)
        var packets = [command("BAT", tail: [0, 0, UInt8(jpeg.count >> 8), UInt8(jpeg.count & 255), address(for: index)])]
        let bytes = Array(jpeg)
        for offset in stride(from: 0, to: bytes.count, by: packetSize) {
            var chunk = Array(bytes[offset..<min(offset + packetSize, bytes.count)])
            chunk += Array(repeating: 0, count: packetSize - chunk.count)
            packets.append(chunk)
        }
        return packets
    }

    static var clearScreenPackets: [[UInt8]] {
        [command("CLE", tail: [0,0,0,0xFF]), command("STP")]
    }

    static var sleepPackets: [[UInt8]] {
        // HAN is the device's sleep command; brightness zero alone leaves a glow.
        // Commit clearing before HAN, then send nothing until the screens wake.
        [command("DIS"), command("LIG", tail: [0,0,0])] + clearScreenPackets + [command("HAN")]
    }
}
