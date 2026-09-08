import Foundation
import CoreBluetooth
import Observation
import HazaCore

/// Valentine One Gen2 over Bluetooth LE. The Gen2 has Bluetooth built in and speaks ESP through the
/// V1connection LE service (UUIDs from the ESP Bluetooth Addendum). Frames ≤ 20 bytes use the "short"
/// characteristics; longer frames are chunked on the "long" ones.
@Observable @MainActor
final class V1Client: NSObject {
    static let shared = V1Client()

    enum State: Equatable { case off, scanning, connecting(String), connected(String), failed(String) }

    private(set) var state: State = .off
    private(set) var display: ESP.Display?
    private(set) var alerts: [ESP.Alert] = []
    private(set) var firmware: String?
    private(set) var lastAlertAt: Date?
    var shareWithCrew = true

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var shortOut: CBCharacteristic?
    private var longOut: CBCharacteristic?
    private var parser = ESP.Parser()
    private var reassembler = ESP.BLE.Reassembler()
    private var table: [Int: ESP.Alert] = [:]
    private let requests = ESP.Requests(origin: .thirdParty1)
    private var lastSharedAlertAt = Date.distantPast

    override private init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "haza.v1"])
    }

    func startScanning() {
        guard central.state == .poweredOn else { state = .failed("Bluetooth is off"); return }
        state = .scanning
        central.scanForPeripherals(withServices: [CBUUID(string: ESP.BLE.serviceUUID)], options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; state = .off; display = nil; alerts = []
    }

    func mute(_ on: Bool) { send(on ? requests.muteOn : requests.muteOff) }

    private func send(_ packet: ESP.Packet) {
        guard let p = peripheral else { return }
        let frame = packet.encode()
        if frame.count <= ESP.BLE.shortMax, let c = shortOut {
            p.writeValue(Data(frame), for: c, type: .withResponse)
        } else if let c = longOut {
            for chunk in ESP.BLE.chunk(frame) { p.writeValue(Data(chunk), for: c, type: .withResponse) }
        }
    }

    private func handle(_ packet: ESP.Packet) {
        switch packet.id {
        case .infDisplayData:
            display = ESP.Display(payload: packet.payload)
        case .respAlertData:
            guard let a = ESP.Alert(payload: packet.payload) else { return }
            if a.count == 0 { table.removeAll(); alerts = []; return }
            table[a.index] = a
            if table.count >= a.count {          // full table received → publish (spec recommendation)
                alerts = table.values.sorted { $0.index < $1.index }.filter { !$0.isJunk }
                table.removeAll()
                lastAlertAt = .now
                shareIfNeeded()
            }
        case .respVersion:
            firmware = ESP.Version(payload: packet.payload)?.text
        default: break
        }
    }

    /// Priority alert → crew map pin (rate-limited to one every 20 s).
    private func shareIfNeeded() {
        guard shareWithCrew, let a = alerts.first(where: { $0.isPriority }) ?? alerts.first,
              a.bars >= 3, Date.now.timeIntervalSince(lastSharedAlertAt) > 20,
              let loc = LocationService.shared.location else { return }
        lastSharedAlertAt = .now
        let p = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        Task { try? await SupabaseService.shared.shareRadarAlert(band: a.band.name, freq: a.frequencyMHz, strength: Int(a.strongest), direction: a.band.direction, at: p, heading: loc.course >= 0 ? loc.course : nil) }
    }
}

extension V1Client: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in if central.state != .poweredOn { self.state = .failed("Bluetooth is off") } }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        Task { @MainActor in
            if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
                self.peripheral = p; p.delegate = self; self.state = .connecting(p.name ?? "V1")
                central.connect(p)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            central.stopScan()
            self.peripheral = peripheral; peripheral.delegate = self
            self.state = .connecting(peripheral.name ?? "Valentine One")
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: ESP.BLE.serviceUUID)])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.state = .off; self.display = nil; self.alerts = []
            central.connect(peripheral)      // auto-reconnect when the car comes back
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for c in service.characteristics ?? [] {
                switch c.uuid.uuidString.uppercased() {
                case ESP.BLE.v1OutClientInShort, ESP.BLE.v1OutClientInLong: peripheral.setNotifyValue(true, for: c)
                case ESP.BLE.clientOutV1InShort: self.shortOut = c
                case ESP.BLE.clientOutV1InLong: self.longOut = c
                default: break
                }
            }
            self.state = .connected(peripheral.name ?? "Valentine One")
            self.send(self.requests.version)
            self.send(self.requests.startAlertData)
            try? await SupabaseService.shared.registerRadarDevice(brand: "valentine", model: "V1 Gen2", identifier: peripheral.identifier.uuidString, firmware: self.firmware)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let isLong = characteristic.uuid.uuidString.uppercased() == ESP.BLE.v1OutClientInLong
        Task { @MainActor in
            let frameBytes: [UInt8]
            if isLong { guard let f = self.reassembler.add(bytes) else { return }; frameBytes = f } else { frameBytes = bytes }
            for packet in self.parser.feed(frameBytes) { self.handle(packet) }
        }
    }
}
