import Foundation
import UIKit
import UserNotifications
import Supabase
import Observation
import HazaCore

/// The user's private Realtime topic `user:<uid>`. Database triggers (`inbox_broadcast`) push pings,
/// friend requests/acceptances, plans going live, friends' place arrivals, drive starts, convoy
/// suggestions, check-ins and SOS into it the instant they happen, so the app reacts without APNs —
/// a banner while it's open, a local notification while it's in the background (drives keep it
/// alive). On builds with the push entitlement, APNs covers the closed-app case too.
@Observable @MainActor
final class InboxService {
    static let shared = InboxService()

    struct Item: Identifiable, Equatable {
        enum Kind: String {
            case ping, friendRequest = "friend_request", friendAccepted = "friend_accepted", planLive = "plan_live"
            case place, driveStarted = "drive_started", convoySuggest = "convoy_suggest", other
        }
        let id: UUID
        let kind: Kind
        let title: String
        let body: String
        let channelID: UUID?
        let fromUser: UUID?
        let point: GeoPoint?
        let urgent: Bool          // SOS: stays until dismissed, red, loud
        let at: Date
    }

    /// The newest item, for the in-app banner (RootView clears it).
    private(set) var latest: Item?
    private(set) var unread: [Item] = []
    var onFriendsChanged: (() async -> Void)?

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?
    private var client: SupabaseClient { SupabaseService.shared.client }

    func start() async {
        guard channel == nil, let uid = SupabaseService.shared.userID else { return }
        let ch = client.channel("user:\(uid.uuidString.lowercased())") { $0.isPrivate = true }
        let stream = ch.broadcastStream(event: "inbox")
        await ch.subscribe()
        channel = ch
        task = Task { [weak self] in
            for await raw in stream {
                guard let self else { return }
                await self.handle(raw)
            }
        }
    }

    func stop() async {
        task?.cancel(); task = nil
        if let ch = channel { await ch.unsubscribe() }
        channel = nil; latest = nil; unread = []
    }

    func dismiss() { latest = nil }

    private func handle(_ raw: JSONObject) async {
        let p = raw["payload"]?.objectValue ?? raw
        let kind = Item.Kind(rawValue: p["type"]?.stringValue ?? "") ?? .other
        let name = p["from_name"]?.stringValue ?? p["name"]?.stringValue ?? "A friend"
        let channelID = p["channel_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let fromUser = (p["from_user"]?.stringValue ?? p["user_id"]?.stringValue).flatMap(UUID.init(uuidString:))
        var point: GeoPoint?
        if let lat = p["lat"]?.number, let lng = p["lng"]?.number { point = GeoPoint(latitude: lat, longitude: lng) }
        let title: String, body: String, category: String
        var urgent = false
        switch kind {
        case .ping:
            let note = p["note"]?.stringValue
            switch p["kind"]?.stringValue ?? "talk" {
            case "wave": title = "\(name) waved"; body = "They're nearby."
            case "meet": title = "\(name) wants to meet"; body = "Open the map to see where."
            case "checkin": title = "\(name) checked in"; body = note.map { "“\($0)”" } ?? "They're sharing where they are right now."
            case "sos":
                title = "SOS from \(name)"; body = note ?? "They need help. Their location is on the map."; urgent = true
                Haptics.play(.warning)
            default: title = "\(name) wants to talk"; body = channelID == nil ? "Open Talk to answer." : "Tap to join the channel."
            }
            category = urgent ? "SOS" : "PING"
            if !urgent { WatchBridge.shared.notifyIncoming(speaker: name) }
        case .friendRequest:
            title = "\(name) wants to add you"; body = "Accept in Profile › Friends."; category = "FRIEND_REQUEST"
            await onFriendsChanged?()
        case .friendAccepted:
            title = "\(name) accepted"; body = "You're on each other's maps now."; category = "GENERAL"
            DiscoverEngine.shared.note(.friendAdded)
            await onFriendsChanged?()
        case .planLive:
            let planTitle = p["title"]?.stringValue ?? "Your drive"
            title = "\(planTitle) is live"
            body = p["meet_name"]?.stringValue.map { "Everyone's heading to \($0). Talk channel is open." } ?? "Talk channel is open."
            category = "PLAN_LIVE"
        case .place:
            let placeName = p["place_name"]?.stringValue ?? "a place"
            let arrived = (p["event"]?.stringValue ?? "arrive") == "arrive"
            title = arrived ? "\(name) arrived at \(placeName)" : "\(name) left \(placeName)"
            body = arrived ? "Just now." : "On the move."
            category = "PLACE"
            await onFriendsChanged?()
        case .driveStarted:
            title = "\(name) is driving"; body = "Open Talk to ride along."; category = "DRIVE"
            DiscoverEngine.shared.note(.friendOnline)
            await onFriendsChanged?()
        case .convoySuggest:
            let d = p["distance_m"]?.number ?? 0
            let miles = Units.miles(fromMeters: d)
            title = "\(name) is driving \(String(format: "%.1f", miles)) mi from you"
            body = "Ping them and roll together."
            category = "CONVOY"
            Haptics.play(.tap)
        case .other:
            return
        }
        let item = Item(id: UUID(), kind: kind, title: title, body: body, channelID: channelID, fromUser: fromUser, point: point, urgent: urgent, at: .now)
        latest = item
        unread.append(item)
        if UIApplication.shared.applicationState != .active || urgent {
            await Self.postLocalNotification(item, category: category)
        }
    }

    /// Local notifications need no APNs entitlement — only the permission the briefing asks for.
    private static func postLocalNotification(_ item: Item, category: String) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = item.urgent ? .defaultCritical : .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive   // critical alerts need Apple's entitlement; time-sensitive is the honest ceiling here
        if let c = item.channelID { content.userInfo["channel_id"] = c.uuidString }
        if let f = item.fromUser { content.userInfo["from_user"] = f.uuidString }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil))
    }
}

private extension AnyJSON {
    /// Postgres renders whole doubles without a decimal point, which decodes as `.integer`.
    var number: Double? { doubleValue ?? intValue.map(Double.init) }
}
