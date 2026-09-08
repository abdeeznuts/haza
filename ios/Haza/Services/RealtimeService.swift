import Foundation
import Supabase
import Observation
import HazaCore

/// Supabase Realtime Broadcast on private channels (RLS on `realtime.messages` decides who may listen).
///  - `loc:<uid>`  my position stream; I publish, friends subscribe.
///  - `crew:<id>`  crew room: positions + talk state + radar alerts.
@Observable @MainActor
final class RealtimeService {
    static let shared = RealtimeService()

    struct FriendPosition: Identifiable, Equatable {
        var id: UUID
        var point: GeoPoint
        var speed: Double?
        var heading: Double?
        var driving: Bool
        var at: Date
    }

    private(set) var positions: [UUID: FriendPosition] = [:]
    private var myChannel: RealtimeChannelV2?
    private var friendChannels: [UUID: RealtimeChannelV2] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var client: SupabaseClient { SupabaseService.shared.client }

    private struct PositionMessage: Codable {
        var lat: Double, lng: Double, spd: Double?, hdg: Double?, drv: Bool, t: Double
    }

    func joinMyChannel() async {
        guard myChannel == nil, let id = SupabaseService.shared.userID else { return }
        let ch = client.channel("loc:\(id.uuidString.lowercased())") { $0.isPrivate = true }
        await ch.subscribe()
        myChannel = ch
    }

    func broadcastPosition(_ p: GeoPoint, speed: Double?, heading: Double?, driving: Bool) async {
        if myChannel == nil { await joinMyChannel() }
        // Documented signature: broadcast(event:message:) with a [String: AnyJSON] message.
        var msg: [String: AnyJSON] = ["lat": .double(p.latitude), "lng": .double(p.longitude), "drv": .bool(driving), "t": .double(Date().timeIntervalSince1970)]
        if let speed { msg["spd"] = .double(speed) }
        if let heading { msg["hdg"] = .double(heading) }
        try? await myChannel?.broadcast(event: "pos", message: msg)
    }

    /// Listen to a friend's stream. The server snaps positions inside their home bubble in `friends_live()`;
    /// live broadcasts inside the bubble are suppressed by the sender (see LocationService.shareEnabled + home check).
    func follow(_ friend: UUID) async {
        guard friendChannels[friend] == nil else { return }
        let ch = client.channel("loc:\(friend.uuidString.lowercased())") { $0.isPrivate = true }
        let stream = ch.broadcastStream(event: "pos")
        await ch.subscribe()
        friendChannels[friend] = ch
        tasks[friend] = Task { [weak self] in
            for await raw in stream {
                // Broadcast messages arrive as JSONObject; the sender's dictionary sits under "payload".
                guard let self, let data = try? JSONEncoder().encode(raw["payload"] ?? .object(raw)),
                      let m = try? JSONDecoder().decode(PositionMessage.self, from: data) else { continue }
                self.positions[friend] = FriendPosition(id: friend, point: GeoPoint(latitude: m.lat, longitude: m.lng), speed: m.spd, heading: m.hdg, driving: m.drv, at: Date(timeIntervalSince1970: m.t))
            }
        }
    }

    func unfollow(_ friend: UUID) async {
        tasks[friend]?.cancel(); tasks[friend] = nil
        if let ch = friendChannels[friend] { await ch.unsubscribe() }
        friendChannels[friend] = nil
        positions[friend] = nil
    }

    func followAll(_ friends: [UUID]) async {
        for f in friends { await follow(f) }
        for f in friendChannels.keys where !friends.contains(f) { await unfollow(f) }
    }
}
