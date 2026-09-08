import XCTest
@testable import HazaCore

final class ESPTests: XCTestCase {

    // Payloads from Tables 9.5 / 9.6 of the ESP spec (Rev 3.016), framed per Table 2.2 (PL counts the
    // checksum → $08) with checksums computed by the spec's formula. The spec prints these examples
    // with PL $07 and checksums that don't match its own formula; see testSpecExamplesAsPrinted.
    let zeroAlerts: [UInt8] = [0xAA, 0xD6, 0xEA, 0x43, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xB5, 0xAB]
    let xRear: [UInt8]      = [0xAA, 0xD6, 0xEA, 0x43, 0x08, 0x13, 0x29, 0x1D, 0x21, 0x85, 0x88, 0x00, 0x3C, 0xAB]
    let kFront: [UInt8]     = [0xAA, 0xD6, 0xEA, 0x43, 0x08, 0x23, 0x5E, 0x56, 0x92, 0x83, 0x24, 0x00, 0xC5, 0xAB]
    let kaPriority: [UInt8] = [0xAA, 0xD6, 0xEA, 0x43, 0x08, 0x33, 0x87, 0x8C, 0xB6, 0x81, 0x22, 0x80, 0xD4, 0xAB]

    func testSpecExamplesAsPrinted() {
        // Table 9.5 exactly as printed: PL $07 but eight bytes follow (7 data + $B4 checksum). The parser
        // tolerates the one-byte-longer frame; the checksum $B4 is correct for the bytes before it.
        var parser = ESP.Parser()
        let printed: [UInt8] = [0xAA, 0xD6, 0xEA, 0x43, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xB4, 0xAB]
        let p = parser.feed(printed)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(ESP.Alert(payload: p[0].payload)?.count, 0)
    }

    func testParsesSpecAlertExamples() {
        var parser = ESP.Parser()
        let packets = parser.feed(zeroAlerts + xRear + kFront + kaPriority)
        XCTAssertEqual(packets.count, 4)
        XCTAssertEqual(parser.droppedBytes, 0)

        let a1 = ESP.Alert(payload: packets[1].payload)!
        XCTAssertEqual(a1.index, 1); XCTAssertEqual(a1.count, 3)
        XCTAssertEqual(a1.frequencyMHz, 10525)
        XCTAssertEqual(a1.frontStrength, 0x21); XCTAssertEqual(a1.rearStrength, 0x85)
        XCTAssertEqual(a1.band.name, "X"); XCTAssertEqual(a1.band.direction, "rear")
        XCTAssertFalse(a1.isPriority)

        let a2 = ESP.Alert(payload: packets[2].payload)!
        XCTAssertEqual(a2.frequencyMHz, 24150); XCTAssertEqual(a2.band.name, "K"); XCTAssertEqual(a2.band.direction, "front")

        let a3 = ESP.Alert(payload: packets[3].payload)!
        XCTAssertEqual(a3.index, 3); XCTAssertEqual(a3.frequencyMHz, 34700)
        XCTAssertEqual(a3.band.name, "Ka"); XCTAssertTrue(a3.isPriority)
        XCTAssertEqual(a3.bars, 7)   // 0xB6 on Ka → 7 LEDs per Table 9.1

        let a0 = ESP.Alert(payload: packets[0].payload)!
        XCTAssertEqual(a0.count, 0); XCTAssertEqual(a0.bars, 0)
    }

    func testChecksumRoundTrip() {
        let req = ESP.Requests(origin: .thirdParty1).startAlertData
        let bytes = req.encode()
        XCTAssertEqual(bytes.first, 0xAA); XCTAssertEqual(bytes.last, 0xAB)
        XCTAssertEqual(bytes[1], 0xDA)        // dest V1 (checksum)
        XCTAssertEqual(bytes[2], 0xE3)        // origin third-party 1
        XCTAssertEqual(bytes[3], 0x41)
        XCTAssertEqual(bytes[4], 1)           // payload length includes the checksum
        // Checksum infDisplayData frame (payload from the spec example, 8 data bytes + checksum = PL 9).
        let display = ESP.Packet(destination: 8, origin: 0x0A, packetID: 0x31, payload: [0x5B, 0x1F, 0x38, 0x28, 0x0C, 0x00, 0x00, 0x00], checksummed: true)
        XCTAssertEqual(display.encode(), [0xAA, 0xD8, 0xEA, 0x31, 0x09, 0x5B, 0x1F, 0x38, 0x28, 0x0C, 0x00, 0x00, 0x00, 0x8C, 0xAB])
        // …and the zero-alert example from Table 9.5 re-encodes byte for byte.
        var parser = ESP.Parser()
        XCTAssertEqual(parser.feed(zeroAlerts).first?.encode(), zeroAlerts)
    }

    func testDisplayDataDecodes() {
        // Non-checksum infDisplayData from a V1 without checksums (origin $09): 8 payload bytes, PL 8.
        var parser = ESP.Parser()
        let p = parser.feed([0xAA, 0xD8, 0xE9, 0x31, 0x08, 0x5B, 0x1F, 0x38, 0x28, 0x0C, 0x00, 0x00, 0x00, 0xAB])
        XCTAssertEqual(p.count, 1)
        let d = ESP.Display(payload: p[0].payload)!
        XCTAssertEqual(d.bogeyCounter, 2)                 // 0x5B is the digit 2
        XCTAssertEqual(d.barGraphLevel, 3)                // byte 2 = 0x38 → three LEDs lit
        XCTAssertTrue(d.band.contains(.x))                // byte 3 = 0x28: X band + front arrow
        XCTAssertEqual(d.band.direction, "front")
        XCTAssertFalse(d.isSystemActive)                  // aux0 (byte 5) is 0x00 in this example
        XCTAssertFalse(d.isMuted)
        let live = ESP.Display(payload: [0x06, 0x00, 0xFF, 0x22, 0x22, 0x0D, 0x04, 0x85])!
        XCTAssertEqual(live.bogeyCounter, 1); XCTAssertEqual(live.barGraphLevel, 8)
        XCTAssertEqual(live.band.name, "Ka"); XCTAssertTrue(live.isMuted); XCTAssertTrue(live.isSystemActive)
        XCTAssertEqual(live.mode, 1); XCTAssertEqual(live.mainVolume, 8); XCTAssertEqual(live.muteVolume, 5)
    }

    func testCorruptChecksumIsDropped() {
        var bad = kaPriority; bad[12] = 0x31
        var parser = ESP.Parser()
        XCTAssertEqual(parser.feed(bad).count, 0)
        XCTAssertGreaterThan(parser.droppedBytes, 0)
        XCTAssertEqual(parser.feed(kFront).count, 1)     // recovers on the next frame
    }

    func testStreamSplitAcrossBLEWrites() {
        var parser = ESP.Parser()
        let all = xRear + kFront
        var out: [ESP.Packet] = []
        for chunk in stride(from: 0, to: all.count, by: 5) { out += parser.feed(Array(all[chunk..<min(all.count, chunk + 5)])) }
        XCTAssertEqual(out.count, 2)
    }

    func testBLEChunkingMatchesAddendumExample() {
        let frame: [UInt8] = [0xAA, 0xD6, 0xEA, 0x23, 0x0B, 0x13, 0x8C, 0xE8, 0x89, 0x23, 0x23, 0x89, 0x1F, 0x87, 0xD6, 0x33, 0x87, 0xD2, 0x82, 0x67, 0x68, 0xAB]
        let chunks = ESP.BLE.chunk(frame)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], [0x12, 0xAA, 0xD6, 0xEA, 0x23, 0x0B, 0x13, 0x8C, 0xE8, 0x89, 0x23, 0x23, 0x89, 0x1F, 0x87, 0xD6, 0x33, 0x87, 0xD2, 0x82])
        XCTAssertEqual(chunks[1], [0x22, 0x67, 0x68, 0xAB])
        var r = ESP.BLE.Reassembler()
        XCTAssertNil(r.add(chunks[1]))                    // out of order is fine
        XCTAssertEqual(r.add(chunks[0]), frame)
        XCTAssertEqual(ESP.BLE.chunk([0xAA, 0xAB]), [[0xAA, 0xAB]])
    }

    func testVersionDecode() {
        let v = ESP.Version(payload: Array("V4.1037".utf8) + [0x00])!
        XCTAssertEqual(v.device, "V"); XCTAssertEqual(v.text, "4.1037")
    }
}

final class SpeedFilterTests: XCTestCase {
    func testConvergesAndPredicts() {
        var f = SpeedFilter()
        var t = 0.0
        for _ in 0..<20 { f.update(measuredSpeed: 20, accuracy: 1, at: t); t += 1 }
        XCTAssertEqual(f.speed, 20, accuracy: 0.5)
        for v in stride(from: 20.0, through: 30.0, by: 1.0) { f.update(measuredSpeed: v, accuracy: 1, at: t); t += 1 }
        XCTAssertGreaterThan(f.acceleration, 0.5)
        XCTAssertGreaterThan(f.predicted(after: 3), f.speed)
        XCTAssertLessThan(f.predicted(after: 3), f.speed * 1.5 + 5)
    }
    func testStationarySnapsToZero() {
        var f = SpeedFilter()
        for i in 0..<10 { f.update(measuredSpeed: 0.2, accuracy: 2, at: Double(i)) }
        XCTAssertEqual(f.speed, 0); XCTAssertEqual(f.predicted(after: 3), 0)
    }
}

final class GeoTests: XCTestCase {
    let richmond = GeoPoint(latitude: 29.5822, longitude: -95.7605)
    let houston = GeoPoint(latitude: 29.7604, longitude: -95.3698)
    func testDistanceAndBearing() {
        XCTAssertEqual(Geo.distance(richmond, houston), 42_500, accuracy: 1_500)
        XCTAssertEqual(Geo.bearing(from: richmond, to: houston), 62, accuracy: 5)
    }
    func testPrivacyBubble() {
        let near = GeoPoint(latitude: 29.5825, longitude: -95.7609)
        let r = Geo.privacySnapped(near, home: richmond)
        XCTAssertTrue(r.atHome); XCTAssertEqual(r.point, richmond)
        XCTAssertFalse(Geo.privacySnapped(houston, home: richmond).atHome)
    }
    func testSimplifyKeepsEnds() {
        let pts = (0..<50).map { GeoPoint(latitude: 29.5 + Double($0) * 0.001, longitude: -95.7 + ($0 % 2 == 0 ? 0 : 0.00001)) }
        let s = Geo.simplify(pts, tolerance: 5)
        XCTAssertEqual(s.first, pts.first); XCTAssertEqual(s.last, pts.last); XCTAssertLessThan(s.count, 10)
    }
}

final class HomeInferenceTests: XCTestCase {
    func testFindsHomeFromOvernightSamples() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let home = GeoPoint(latitude: 29.6009, longitude: -95.7411)
        var samples: [HomeSample] = []
        for night in 0..<4 {
            for k in 0..<6 {
                let t = cal.date(from: DateComponents(year: 2026, month: 9, day: 1 + night, hour: 2, minute: k * 7))!
                samples.append(HomeSample(time: t, point: GeoPoint(latitude: home.latitude + Double(k) * 0.00005, longitude: home.longitude - Double(k) * 0.00004)))
            }
        }
        // daytime noise elsewhere must not count
        for d in 0..<10 {
            let t = cal.date(from: DateComponents(year: 2026, month: 9, day: 1 + d, hour: 14))!
            samples.append(HomeSample(time: t, point: GeoPoint(latitude: 29.76, longitude: -95.36)))
        }
        let s = HomeInference.suggest(from: samples, calendar: cal)!
        XCTAssertEqual(s.nights, 4)
        XCTAssertLessThan(Geo.distance(s.point, home), 40)
        XCTAssertEqual(s.confidence, 0.8, accuracy: 0.01)
        XCTAssertNil(HomeInference.suggest(from: Array(samples.prefix(12)), calendar: cal))   // only 2 nights
    }
}

final class ReferralAndBriefingTests: XCTestCase {
    func testCodes() {
        XCTAssertEqual(Referral.normalize(" 4k2p-z9aa "), nil)                 // z is not hex
        XCTAssertEqual(Referral.normalize("4a2b-c9de"), "4A2BC9DE")
        XCTAssertEqual(Referral.display("4A2BC9DE"), "4A2B-C9DE")
        XCTAssertEqual(Referral.code(from: URL(string: "https://haza.app/i/4A2BC9DE")!), "4A2BC9DE")
        XCTAssertEqual(Referral.code(from: URL(string: "haza://i/4a2bc9de")!), "4A2BC9DE")
        XCTAssertEqual(Referral.code(fromPasteboard: "join me https://haza.app/i/4A2BC9DE"), nil)
        XCTAssertEqual(Referral.code(fromPasteboard: "4A2B C9DE"), "4A2BC9DE")
    }
    func testBriefingMergeOrder() {
        let server = [ServerBriefingRow(key: "no_vehicle", severity: "setup", title: "Add your car", detail: "…"),
                      ServerBriefingRow(key: "no_radar", severity: "feature", title: "Pair a radar detector", detail: "…")]
        let items = Briefing.merge(server: server, device: DeviceFacts(locationAlways: false, notificationsAllowed: true, watchAppInstalled: true, carPlayWidgetSeen: false, controlAdded: true))
        XCTAssertEqual(items.map(\.key), ["location_always", "no_vehicle", "carplay_widget", "no_radar"])
        XCTAssertEqual(Briefing.headline(remaining: items.count), "Four things before your first drive.")
    }
}
