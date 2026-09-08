// Valentine Research "ESP" (Extended Serial Protocol) — implementation of the parts a phone app needs.
// Built from the ESP User's Guide Rev 3.016 (Aug 2026) and the ESP Bluetooth Addendum Rev 4.
//
// Frame:  SOF($AA) | DI($D0+dest) | OI($E0+origin) | PI | PL | payload… | [CS] | EOF($AB)
// Checksum (when talking to the checksum V1, id $0A): 8-bit sum of every byte before it, carries ignored.
// Device ids verified from the spec's own packet examples:
//   $06 V1connection, $08 General Broadcast, $09 V1 (no checksum), $0A V1 (checksum); $03–$05 are reserved for third parties.
import Foundation

public enum ESP {

    public enum DeviceID: UInt8, Sendable {
        case concealedDisplay = 0x00
        case remoteAudio = 0x01
        case savvy = 0x02
        case thirdParty1 = 0x03
        case thirdParty2 = 0x04
        case thirdParty3 = 0x05
        case v1connection = 0x06
        case generalBroadcast = 0x08
        case valentineOneNoChecksum = 0x09
        case valentineOne = 0x0A          // V1 with checksums (Gen2 default)
    }

    public enum PacketID: UInt8, Sendable {
        case reqVersion = 0x01, respVersion = 0x02
        case reqSerialNumber = 0x03, respSerialNumber = 0x04
        case reqUserBytes = 0x11, respUserBytes = 0x12, reqWriteUserBytes = 0x13, reqFactoryDefault = 0x14
        case infDisplayData = 0x31
        case reqTurnOffMainDisplay = 0x32, reqTurnOnMainDisplay = 0x33
        case reqMuteOn = 0x34, reqMuteOff = 0x35, reqChangeMode = 0x36
        case reqCurrentVolume = 0x37, respCurrentVolume = 0x38, reqWriteVolume = 0x39
        case reqStartAlertData = 0x41, reqStopAlertData = 0x42, respAlertData = 0x43
        case respDataReceived = 0x61, reqBatteryVoltage = 0x62, respBatteryVoltage = 0x63
        case respUnsupportedPacket = 0x64, respRequestNotProcessed = 0x65, infV1Busy = 0x66, respDataError = 0x67
    }

    public static let sof: UInt8 = 0xAA
    public static let eof: UInt8 = 0xAB
    public static let destBase: UInt8 = 0xD0
    public static let originBase: UInt8 = 0xE0

    /// A decoded ESP frame. `payload` excludes the checksum byte.
    public struct Packet: Equatable, Sendable {
        public var destination: UInt8
        public var origin: UInt8
        public var packetID: UInt8
        public var payload: [UInt8]
        public var checksummed: Bool

        public init(destination: UInt8, origin: UInt8, packetID: UInt8, payload: [UInt8] = [], checksummed: Bool = true) {
            self.destination = destination; self.origin = origin; self.packetID = packetID
            self.payload = payload; self.checksummed = checksummed
        }

        public var id: PacketID? { PacketID(rawValue: packetID) }

        /// Serialises the frame, appending a checksum when `checksummed` is set.
        public func encode() -> [UInt8] {
            let pl = UInt8(payload.count + (checksummed ? 1 : 0))
            var bytes: [UInt8] = [ESP.sof, ESP.destBase | destination, ESP.originBase | origin, packetID, pl]
            bytes += payload
            if checksummed {
                bytes.append(bytes.reduce(0) { $0 &+ $1 })
            }
            bytes.append(ESP.eof)
            return bytes
        }
    }

    // MARK: Requests a phone app sends (origin defaults to a third-party id)

    public struct Requests {
        public var origin: UInt8
        public var destination: UInt8
        public init(origin: DeviceID = .thirdParty1, destination: DeviceID = .valentineOne) {
            self.origin = origin.rawValue; self.destination = destination.rawValue
        }
        private func make(_ id: PacketID, _ payload: [UInt8] = []) -> Packet {
            Packet(destination: destination, origin: origin, packetID: id.rawValue, payload: payload, checksummed: destination == DeviceID.valentineOne.rawValue)
        }
        public var version: Packet { make(.reqVersion) }
        public var serialNumber: Packet { make(.reqSerialNumber) }
        public var startAlertData: Packet { make(.reqStartAlertData) }
        public var stopAlertData: Packet { make(.reqStopAlertData) }
        public var muteOn: Packet { make(.reqMuteOn) }
        public var muteOff: Packet { make(.reqMuteOff) }
        public var batteryVoltage: Packet { make(.reqBatteryVoltage) }
        public var turnOnMainDisplay: Packet { make(.reqTurnOnMainDisplay) }
        public var turnOffMainDisplay: Packet { make(.reqTurnOffMainDisplay) }
        /// Version request addressed to the V1connection itself (same originator and destination).
        public var v1connectionVersion: Packet {
            Packet(destination: origin, origin: origin, packetID: PacketID.reqVersion.rawValue, checksummed: false)
        }
    }

    // MARK: Stream parser

    /// Incremental frame parser. Feed raw bytes from the BLE characteristic; complete frames come out.
    public struct Parser {
        private var buffer: [UInt8] = []
        public private(set) var droppedBytes = 0
        public init() {}

        public mutating func feed(_ bytes: [UInt8]) -> [Packet] {
            buffer += bytes
            var out: [Packet] = []
            while true {
                guard let start = buffer.firstIndex(of: ESP.sof) else { droppedBytes += buffer.count; buffer.removeAll(); break }
                if start > 0 { droppedBytes += start; buffer.removeFirst(start) }
                guard buffer.count >= 6 else { break }
                guard buffer[1] & 0xF0 == ESP.destBase, buffer[2] & 0xF0 == ESP.originBase else {
                    droppedBytes += 1; buffer.removeFirst(); continue
                }
                let pl = Int(buffer[4])
                // Table 2.2: PL counts the checksum, so the frame is 6 + PL bytes. The spec's own worked
                // examples print PL without the checksum, so a frame one byte longer is accepted too.
                let normative = 6 + pl
                guard buffer.count >= normative else { break }
                var frameLength = normative
                if buffer[normative - 1] != ESP.eof {
                    if buffer.count > normative, buffer[normative] == ESP.eof { frameLength = normative + 1 }
                    else if buffer.count == normative { break }          // maybe the longer variant, wait for one more byte
                    else { droppedBytes += 1; buffer.removeFirst(); continue }
                }
                let origin = buffer[2] & 0x0F
                let checksummed = origin == DeviceID.valentineOne.rawValue
                var payload = Array(buffer[5..<(frameLength - 1)])
                var valid = true
                if checksummed, !payload.isEmpty {
                    let expected = buffer[0..<(frameLength - 2)].reduce(0 as UInt8) { $0 &+ $1 }
                    valid = expected == payload.removeLast()
                }
                if valid {
                    out.append(Packet(destination: buffer[1] & 0x0F, origin: origin, packetID: buffer[3], payload: payload, checksummed: checksummed))
                } else {
                    droppedBytes += frameLength
                }
                buffer.removeFirst(frameLength)
            }
            return out
        }
    }

    // MARK: V1connection LE chunking (packets > 20 bytes)

    public enum BLE {
        public static let serviceUUID = "92A0AFF4-9E05-11E2-AA59-F23C91AEC05E"
        public static let v1OutClientInShort = "92A0B2CE-9E05-11E2-AA59-F23C91AEC05E"
        public static let v1OutClientInLong = "92A0B4E0-9E05-11E2-AA59-F23C91AEC05E"
        public static let clientOutV1InShort = "92A0B6D4-9E05-11E2-AA59-F23C91AEC05E"
        public static let clientOutV1InLong = "92A0B8D2-9E05-11E2-AA59-F23C91AEC05E"
        public static let shortMax = 20

        /// Splits a frame longer than 20 bytes into indexed chunks: first byte = (index << 4) | count.
        public static func chunk(_ frame: [UInt8]) -> [[UInt8]] {
            guard frame.count > shortMax else { return [frame] }
            let per = shortMax - 1
            let count = (frame.count + per - 1) / per
            return (0..<count).map { i in
                let slice = frame[(i * per)..<min(frame.count, (i + 1) * per)]
                return [UInt8((i + 1) << 4) | UInt8(count)] + slice
            }
        }

        /// Reassembles chunks that may arrive out of order. Returns the frame once every chunk is present.
        public struct Reassembler {
            private var parts: [Int: [UInt8]] = [:]
            private var expected = 0
            public init() {}
            public mutating func add(_ chunk: [UInt8]) -> [UInt8]? {
                guard let head = chunk.first else { return nil }
                let index = Int(head >> 4), count = Int(head & 0x0F)
                if count != expected { parts.removeAll(); expected = count }
                parts[index] = Array(chunk.dropFirst())
                guard parts.count == count, count > 0 else { return nil }
                let frame = (1...count).flatMap { parts[$0] ?? [] }
                parts.removeAll(); expected = 0
                return frame
            }
        }
    }

    // MARK: Decoded data

    public struct Band: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let laser = Band(rawValue: 1 << 0)
        public static let ka = Band(rawValue: 1 << 1)
        public static let k = Band(rawValue: 1 << 2)
        public static let x = Band(rawValue: 1 << 3)
        public static let ku = Band(rawValue: 1 << 4)
        public static let front = Band(rawValue: 1 << 5)
        public static let side = Band(rawValue: 1 << 6)
        public static let rear = Band(rawValue: 1 << 7)

        public var name: String {
            if contains(.laser) { return "Laser" }
            if contains(.ka) { return "Ka" }
            if contains(.k) { return "K" }
            if contains(.ku) { return "Ku" }
            if contains(.x) { return "X" }
            return "—"
        }
        public var direction: String {
            if contains(.front) { return "front" }
            if contains(.side) { return "side" }
            if contains(.rear) { return "rear" }
            return "—"
        }
    }

    /// One row of the Alert Table (respAlertData, $43).
    public struct Alert: Equatable, Sendable {
        public var index: Int
        public var count: Int
        public var frequencyMHz: Int
        public var frontStrength: UInt8
        public var rearStrength: UInt8
        public var band: Band
        public var isPriority: Bool
        public var isJunk: Bool
        public var photoRadarType: UInt8

        public init?(payload p: [UInt8]) {
            guard p.count >= 7 else { return nil }
            index = Int(p[0] >> 4); count = Int(p[0] & 0x0F)
            frequencyMHz = Int(p[1]) << 8 | Int(p[2])
            frontStrength = p[3]; rearStrength = p[4]
            band = Band(rawValue: p[5])
            photoRadarType = p[6] & 0x0F
            isJunk = p[6] & 0x40 != 0
            isPriority = p[6] & 0x80 != 0
        }

        public var strongest: UInt8 { max(frontStrength, rearStrength) }
        /// 0…8 bar-graph equivalent from Table 9.1 of the spec.
        public var bars: Int { ESP.bars(strength: strongest, band: band) }
    }

    /// Front-panel image from infDisplayData ($31).
    public struct Display: Equatable, Sendable {
        public var bogeyCounter: Int?          // decoded 7-segment digit, nil for letters/modes
        public var bogeySegments: UInt8
        public var barGraphLevel: Int          // 0…8 lit LEDs
        public var band: Band                  // band + arrow image 1
        public var isMuted: Bool
        public var isSystemActive: Bool
        public var isDisplayOn: Bool
        public var isEuroMode: Bool
        public var isLegacyMode: Bool
        public var isLogicMuted: Bool
        public var mode: UInt8                 // 0…3 from Aux1
        public var mainVolume: Int
        public var muteVolume: Int

        public init?(payload p: [UInt8]) {
            guard p.count >= 6 else { return nil }
            bogeySegments = p[0]
            bogeyCounter = ESP.sevenSegmentDigit(p[0] & 0x7F)
            barGraphLevel = (0..<8).filter { p[2] & (1 << $0) != 0 }.count
            band = Band(rawValue: p[3] & ~0x10)      // bit 4 is the mute indicator on this byte
            isMuted = p[3] & 0x10 != 0 || p[5] & 0x01 != 0
            isSystemActive = p[5] & 0x04 != 0
            isDisplayOn = p[5] & 0x08 != 0
            isEuroMode = p[5] & 0x10 != 0
            isLegacyMode = p[5] & 0x40 != 0
            let aux1 = p.count > 6 ? p[6] : 0
            isLogicMuted = aux1 & 0x02 != 0
            mode = (aux1 >> 2) & 0x03
            let aux2 = p.count > 7 ? p[7] : 0
            muteVolume = Int(aux2 & 0x0F); mainVolume = Int(aux2 >> 4)
        }
    }

    public struct Version: Equatable, Sendable {
        public var device: Character
        public var text: String
        public init?(payload p: [UInt8]) {
            guard p.count >= 7 else { return nil }
            device = Character(UnicodeScalar(p[0]))
            text = String(p[1..<7].map { Character(UnicodeScalar($0)) })
        }
    }

    // MARK: Tables

    /// Table 9.1 — Alert Table strength → equivalent number of LEDs.
    public static func bars(strength s: UInt8, band: Band) -> Int {
        let thresholds: [UInt8]
        if band.contains(.ka) { thresholds = [0x01, 0x90, 0x97, 0x9E, 0xA5, 0xAC, 0xB3, 0xBA] }
        else if band.contains(.k) || band.contains(.ku) { thresholds = [0x01, 0x88, 0x90, 0x9A, 0xA4, 0xAE, 0xB8, 0xC2] }
        else { thresholds = [0x01, 0x96, 0xA0, 0xAA, 0xB4, 0xBD, 0xC5, 0xD0] }   // X band
        if s == 0 { return 0 }
        return thresholds.filter { s >= $0 }.count
    }

    /// Standard 7-segment encoding (bit0=a … bit6=g).
    public static func sevenSegmentDigit(_ image: UInt8) -> Int? {
        switch image {
        case 0x3F: return 0
        case 0x06: return 1
        case 0x5B: return 2
        case 0x4F: return 3
        case 0x66: return 4
        case 0x6D: return 5
        case 0x7D: return 6
        case 0x07: return 7
        case 0x7F: return 8
        case 0x6F: return 9
        default: return nil
        }
    }
}
