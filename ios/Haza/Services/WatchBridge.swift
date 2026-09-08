import Foundation
import WatchConnectivity
import AVFAudio
import Observation
import HazaCore

/// iPhone side of the Watch link. Messages (see WatchProtocol in Shared/WatchProtocol.swift):
///  watch → phone : "ptt.begin", "ptt.audio" (16 kHz mono Int16 PCM chunk), "ptt.end", "ping" {userId}
///  phone → watch : "state" {joined, channel, speaker}, "speed" {mph}, "incoming" {speaker}, "nearby" [...]
@Observable @MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    private var format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: phone → watch

    func sendTalkState(joined: Bool, channel: String, speaker: String?) {
        push(["type": "state", "joined": joined, "channel": channel, "speaker": speaker ?? ""], context: true)
    }
    func sendSpeed(_ mph: Int) { push(["type": "speed", "mph": mph], context: false) }
    func notifyIncoming(speaker: String) { push(["type": "incoming", "speaker": speaker], context: false) }
    func sendNearby(_ list: [(id: UUID, name: String, distanceM: Double, driving: Bool)]) {
        push(["type": "nearby", "items": list.map { ["id": $0.id.uuidString, "name": $0.name, "d": $0.distanceM, "drv": $0.driving] }], context: true)
    }

    private func push(_ msg: [String: Any], context: Bool) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable { s.sendMessage(msg, replyHandler: nil) }
        else if context { try? s.updateApplicationContext(msg) }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.isWatchAppInstalled = session.isWatchAppInstalled; self.isReachable = session.isReachable }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.isWatchAppInstalled = session.isWatchAppInstalled }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in await self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        // Raw PCM chunk from the watch while its Talk button is held.
        Task { @MainActor in self.injectPCM(messageData) }
    }

    private func handle(_ message: [String: Any]) async {
        switch message["type"] as? String {
        case "ptt.begin": TalkService.shared.beginTransmit()
        case "ptt.end": TalkService.shared.endTransmit()
        case "ping":
            if let s = message["userId"] as? String, let id = UUID(uuidString: s) {
                try? await SupabaseService.shared.ping(id, channel: TalkService.shared.conversation?.id)
            }
        default: break
        }
    }

    private func injectPCM(_ data: Data) {
        let frames = UInt32(data.count / 2)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            if let dst = buffer.int16ChannelData?[0], let src = raw.baseAddress {
                memcpy(dst, src, Int(frames) * 2)
            }
        }
        TalkService.shared.injectWatchAudio(buffer)
    }
}
