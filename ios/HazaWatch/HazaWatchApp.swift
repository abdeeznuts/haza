import SwiftUI
import WatchConnectivity
import AVFoundation
import WatchKit
import Observation

@main
struct HazaWatchApp: App {
    @State private var session = WatchSessionManager.shared
    var body: some Scene {
        WindowGroup { WatchTalkView().environment(session) }
    }
}

/// Watch side of the link. The watch never talks to LiveKit (no watchOS SDK); it records while the
/// button is held and streams PCM chunks to the iPhone, which publishes them. Incoming talk arrives
/// as a "incoming" message → haptic + name.
@Observable @MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    var joined = false
    var channel = "Crew"
    var speaker: String?
    var speedMPH = 0
    struct NearbyItem: Identifiable, Equatable { var id: String; var name: String; var distanceM: Double; var driving: Bool }
    var nearby: [NearbyItem] = []
    var transmitting = false
    var reachable = false

    private let recorder = WatchRecorder()

    override private init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
        // Ask for the microphone up front so the first hold-to-talk isn't silent.
        Task { _ = await AVAudioApplication.requestRecordPermission() }
    }

    func beginTalk() {
        guard reachable else { WKInterfaceDevice.current().play(.failure); return }
        transmitting = true
        WKInterfaceDevice.current().play(.start)
        WCSession.default.sendMessage(["type": "ptt.begin"], replyHandler: nil)
        recorder.start { chunk in WCSession.default.sendMessageData(chunk, replyHandler: nil) }
    }

    func endTalk() {
        guard transmitting else { return }
        transmitting = false
        recorder.stop()
        WCSession.default.sendMessage(["type": "ptt.end"], replyHandler: nil)
        WKInterfaceDevice.current().play(.stop)
    }

    func ping(_ userId: String) {
        WCSession.default.sendMessage(["type": "ping", "userId": userId], replyHandler: nil)
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.reachable = session.isReachable; self.apply(session.receivedApplicationContext) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.isReachable }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    private func apply(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "state":
            joined = m["joined"] as? Bool ?? false
            channel = m["channel"] as? String ?? channel
            let s = m["speaker"] as? String ?? ""
            speaker = s.isEmpty ? nil : s
        case "speed": speedMPH = m["mph"] as? Int ?? speedMPH
        case "incoming":
            speaker = m["speaker"] as? String
            WKInterfaceDevice.current().play(.notification)
        case "nearby":
            nearby = (m["items"] as? [[String: Any]] ?? []).map { NearbyItem(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", distanceM: $0["d"] as? Double ?? 0, driving: $0["drv"] as? Bool ?? false) }
        default: break
        }
    }
}

/// 16 kHz mono Int16 PCM in ~100 ms chunks (3.2 KB each) — small enough for WatchConnectivity messages.
final class WatchRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    func start(_ onChunk: @escaping (Data) -> Void) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord)
        try? session.setActive(true)
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: target)
        input.installTap(onBus: 0, bufferSize: 1600, format: inFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = self.target.sampleRate / inFormat.sampleRate
            guard let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return }
            onChunk(Data(bytes: ch[0], count: Int(out.frameLength) * 2))
        }
        engine.prepare()
        try? engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct WatchTalkView: View {
    @Environment(WatchSessionManager.self) private var session
    private let live = Color(red: 48/255, green: 209/255, blue: 88/255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    Text(session.channel).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Circle().fill(session.joined ? live : .gray).frame(width: 8, height: 8)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(session.transmitting ? live : (session.speaker != nil ? Color(white: 0.2) : live.opacity(session.joined ? 1 : 0.35)))
                    .frame(width: 104, height: 104)
                    .overlay(VStack(spacing: 2) {
                        Text(session.transmitting ? "TALKING" : (session.speaker ?? "HOLD")).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(session.transmitting ? "release to send" : (session.speaker != nil ? "is talking" : "to talk")).font(.system(size: 10)).opacity(0.7)
                    }.foregroundStyle(session.transmitting || session.speaker == nil ? .black : .white))
                    .scaleEffect(session.transmitting ? 0.94 : 1)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !session.transmitting { session.beginTalk() } }.onEnded { _ in session.endTalk() })
                    .disabled(!session.joined)
                Spacer(minLength: 0)
                HStack {
                    if let n = session.nearby.first { Text("\(n.name) \(String(format: "%.1f", n.distanceM / 1609.344)) mi").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Text("\(session.speedMPH) mph").font(.system(size: 12, design: .serif)).monospacedDigit()
                }
                if !session.reachable { Text("Open Haza on your iPhone").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 6)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { WatchNearbyView() } label: { Image(systemName: "person.2") }
                }
            }
        }
    }
}

struct WatchNearbyView: View {
    @Environment(WatchSessionManager.self) private var session
    var body: some View {
        List(session.nearby) { n in
            Button { session.ping(n.id) } label: {
                VStack(alignment: .leading) { Text(n.name).font(.system(size: 14, weight: .semibold)); Text("\(String(format: "%.1f", n.distanceM / 1609.344)) mi · \(n.driving ? "driving" : "parked") · tap to ping").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Nearby")
    }
}
