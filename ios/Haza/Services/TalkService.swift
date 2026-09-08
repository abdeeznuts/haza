import Foundation
import PushToTalk
import LiveKit
import AVFAudio
import UIKit
import Observation
import HazaCore

/// The walkie-talkie. Apple's Push to Talk framework owns the system UI, the audio session and the
/// background wake-ups; LiveKit carries the audio. One system PTT channel exists for the whole app
/// (Apple allows one active channel); switching conversations only swaps the descriptor, exactly as
/// Apple's "Handle multiple Push to Talk conversations" section describes.
@Observable @MainActor
final class TalkService: NSObject {
    static let shared = TalkService()

    private(set) var joined = false
    private(set) var transmitting = false
    private(set) var activeSpeaker: String?
    private(set) var listeners = 0
    private(set) var conversation: TalkChannel?
    private(set) var conversationName = "Crew"
    private(set) var status: String = "Off"

    /// `.system` = Apple's Push to Talk framework (Lock Screen UI, background wake-ups; needs the
    /// push-to-talk entitlement, i.e. a paid developer account). `.inApp` = the same LiveKit channel
    /// driven directly by the app — what a build signed with a free Apple ID gets. Every feature
    /// still works in `.inApp`; you just hold the button inside Haza (or on the Watch) instead of
    /// from the Lock Screen / CarPlay play-pause.
    enum Mode { case system, inApp }
    private(set) var mode: Mode = .inApp
    var isSystemPTT: Bool { mode == .system }

    private var channelManager: PTChannelManager?
    private var room: Room?
    private let supabase = SupabaseService.shared
    private var descriptor: PTChannelDescriptor { PTChannelDescriptor(name: "\(HazaBrand.name) · \(conversationName)", image: UIImage(named: "TalkChannel")) }

    /// Stable UUID for the single system channel, so restoration after relaunch maps to the same channel.
    private var systemChannelUUID: UUID {
        if let s = UserDefaults.standard.string(forKey: "ptt.channel"), let u = UUID(uuidString: s) { return u }
        let u = UUID(); UserDefaults.standard.set(u.uuidString, forKey: "ptt.channel"); return u
    }

    /// Initialise the channel manager as early as possible (Apple: so restoration + pushes work).
    func prepare() async {
        guard channelManager == nil else { return }
        // No entitlement in the binary → don't even ask the framework (it would fail, or worse, half-work).
        guard Entitlements.has("com.apple.developer.push-to-talk") else {
            mode = .inApp; status = "Off"; return
        }
        do {
            channelManager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self)
            mode = .system
            // The PTT framework activates/deactivates the audio session; LiveKit must not configure it
            // (documented switch in LiveKit's Docs/audio.md: isAutomaticConfigurationEnabled).
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        } catch {
            mode = .inApp
            status = "Off"
        }
    }

    // MARK: Public controls

    /// Join must be triggered by a user tap while the app is in the foreground (Apple rule).
    func join(_ channel: TalkChannel, named name: String) {
        conversation = channel; conversationName = name
        if mode == .system, let channelManager {
            channelManager.requestJoinChannel(channelUUID: systemChannelUUID, descriptor: descriptor)
        } else {
            Task { await inAppJoin() }
        }
    }

    func leave() {
        if mode == .system, let channelManager {
            channelManager.leaveChannel(channelUUID: systemChannelUUID)
        } else {
            Task { await inAppLeave() }
        }
    }

    // MARK: In-app mode (free Apple ID builds, simulator, or the framework refusing to join)

    private func inAppJoin() async {
        guard let c = conversation else { return }
        status = "Connecting…"
        await connectRoom()
        guard room != nil else { return }               // status already carries the error
        joined = true; status = "Joined"
        try? await supabase.setJoined(true, channel: c.id)
        publishSnapshot()
    }

    private func inAppLeave() async {
        joined = false; transmitting = false; activeSpeaker = nil; status = "Off"
        if let c = conversation { try? await supabase.setJoined(false, channel: c.id) }
        await room?.disconnect(); room = nil
        publishSnapshot()
    }

    private func inAppBeginTransmit() async {
        guard joined, !transmitting else { return }
        transmitting = true
        await setMic(true)
        publishSnapshot()
        if let c = conversation { await supabase.notifyTransmission(channel: c.id, begin: true) }
    }

    private func inAppEndTransmit() async {
        guard transmitting else { return }
        transmitting = false
        await setMic(false)
        publishSnapshot()
    }

    /// Used by the widget/control toggle after the app comes to the foreground.
    func setJoined(_ on: Bool) async {
        if on, !joined, let c = conversation { join(c, named: conversationName) }
        else if !on, joined { leave() }
    }

    /// Switch which conversation the single system channel represents.
    func switchConversation(to channel: TalkChannel, named name: String) async {
        conversation = channel; conversationName = name
        guard joined else { return }
        await connectRoom()
        try? await channelManager?.setChannelDescriptor(descriptor, channelUUID: systemChannelUUID)
        publishSnapshot()
    }

    func beginTransmit() {
        if mode == .system, let channelManager { channelManager.requestBeginTransmitting(channelUUID: systemChannelUUID) }
        else { Task { await inAppBeginTransmit() } }
    }
    func endTransmit() {
        if mode == .system, let channelManager { channelManager.stopTransmitting(channelUUID: systemChannelUUID) }
        else { Task { await inAppEndTransmit() } }
    }

    // MARK: LiveKit room

    private func connectRoom() async {
        guard let c = conversation else { return }
        do {
            let t = try await supabase.liveKitToken(channel: c.id)
            if let room, room.connectionState == .connected, room.name == t.room { return }
            await room?.disconnect()
            let r = Room(delegate: self, roomOptions: RoomOptions(defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellation: true, noiseSuppression: true)))
            try await r.connect(url: t.url.absoluteString, token: t.token)
            room = r
            listeners = r.remoteParticipants.count
            try? await channelManager?.setServiceStatus(.ready, channelUUID: systemChannelUUID)
        } catch {
            status = "Talk server: \(error.localizedDescription)"
            try? await channelManager?.setServiceStatus(.unavailable, channelUUID: systemChannelUUID)
        }
    }

    private func setMic(_ on: Bool) async {
        try? await room?.localParticipant.setMicrophone(enabled: on)
    }

    private func publishSnapshot() {
        SharedStore.talk = TalkSnapshot(channelID: conversation?.id.uuidString, channelName: conversationName, joined: joined, activeSpeaker: activeSpeaker, listeners: listeners)
        WatchBridge.shared.sendTalkState(joined: joined, channel: conversationName, speaker: activeSpeaker)
    }

    /// Audio recorded on the Apple Watch (PCM chunks over WatchConnectivity) is mixed into the
    /// LiveKit publication so a wrist transmission sounds exactly like a phone transmission.
    func injectWatchAudio(_ buffer: AVAudioPCMBuffer) {
        // Documented in LiveKit's Docs/audio.md: `AudioManager.shared.mixer.capture(appAudio:)` mixes
        // custom buffers alongside (or instead of) the microphone; `mixer.appVolume` sets its level.
        AudioManager.shared.mixer.capture(appAudio: buffer)
    }
}

// MARK: - PTChannelManagerDelegate

extension TalkService: PTChannelManagerDelegate {
    nonisolated func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        Task { @MainActor in
            guard let c = self.conversation else { return }
            try? await self.supabase.storePTTToken(pushToken, channel: c.id)
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        Task { @MainActor in
            self.joined = true; self.status = "Joined"
            try? await channelManager.setTransmissionMode(.halfDuplex, channelUUID: channelUUID)
            await self.connectRoom()
            if let c = self.conversation { try? await self.supabase.setJoined(true, channel: c.id) }
            self.publishSnapshot()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        Task { @MainActor in
            self.joined = false; self.transmitting = false; self.activeSpeaker = nil; self.status = "Off"
            if let c = self.conversation { try? await self.supabase.setJoined(false, channel: c.id) }
            await self.room?.disconnect(); self.room = nil
            self.publishSnapshot()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in
            self.transmitting = true
            if let c = self.conversation { await self.supabase.notifyTransmission(channel: c.id, begin: true) }
            await self.connectRoom()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        // The system activated the session (for transmit or receive). Mic on only when we're the speaker.
        Task { @MainActor in
            if self.transmitting { await self.setMic(true) }
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in
            self.transmitting = false
            await self.setMic(false)
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in await self.setMic(false) }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        // The framework refused (another PTT app owns the channel, entitlement mismatch, …): fall back
        // to in-app mode for this session so the user still gets the channel.
        Task { @MainActor in
            self.status = "Couldn't join: \(error.localizedDescription)"
            self.mode = .inApp
            await self.inAppJoin()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in self.transmitting = false; self.status = "Can't talk right now (\(error.localizedDescription))" }
    }

    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        // Return fast (Apple: don't block). Network work happens in the task below.
        // The server only sends "begin" pushes; a remote speaker's end is reported by LiveKit
        // (didUpdateSpeakingParticipants) → setActiveRemoteParticipant(nil). Apple's own sample
        // leaves the channel when a push carries no speaker, so an unexpected payload does the same.
        guard let name = pushPayload["activeSpeaker"] as? String else { return .leaveChannel }
        Task { @MainActor in
            self.activeSpeaker = name; self.publishSnapshot()
            await self.connectRoom()
            WatchBridge.shared.notifyIncoming(speaker: name)
        }
        return .activeRemoteParticipant(PTParticipant(name: name, image: nil))
    }
}

extension TalkService: PTChannelRestorationDelegate {
    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        // Must be fast and synchronous: rebuild from the App Group snapshot, never from the network.
        let snap = SharedStore.talk
        return PTChannelDescriptor(name: "\(HazaBrand.name) · \(snap.channelName)", image: UIImage(named: "TalkChannel"))
    }
}

// MARK: - RoomDelegate (who is speaking, listener count)

extension TalkService: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor in
            let remote = participants.first { !($0 is LocalParticipant) }
            if let remote {
                self.activeSpeaker = remote.name ?? "Friend"
                try? await self.channelManager?.setActiveRemoteParticipant(PTParticipant(name: self.activeSpeaker!, image: nil), channelUUID: self.systemChannelUUID)
            } else if !self.transmitting {
                self.activeSpeaker = nil
                try? await self.channelManager?.setActiveRemoteParticipant(nil, channelUUID: self.systemChannelUUID)
            }
            self.publishSnapshot()
        }
    }
    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in self.listeners = room.remoteParticipants.count; self.publishSnapshot() }
    }
    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in self.listeners = room.remoteParticipants.count; self.publishSnapshot() }
    }
}
