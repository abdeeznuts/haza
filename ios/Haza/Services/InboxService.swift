import Foundation
import UIKit
import UserNotifications
import Supabase
import Observation
import HazaCore

/// The user's private Realtime topic `user:<uid>`. Database triggers (`inbox_broadcast`) push pings,
/// friend requests/acceptances and plans going live into it the instant they happen, so the app
/// reacts without APNs — a banner while it's open, a local notification while it's in the background
/// (drives keep it alive). On builds with the push entitlement, APNs covers the closed-app case too.
@Observable @MainActor
final class InboxService {
    static let shared = InboxService()

    struct Item: Identifiable, Equatable {
        enum Kind: String { case ping, friendRequest = "friend_request", friendAccepted = "friend_accepted", planLive = "plan_live", other }
        let id: UUID
        let kind: Kind
        let title: String
        let body: String
        let channelID: UUID?
        let fromUser: UUID?
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
        let title: String, body: String, category: String
        switch kind {
        case .ping:
            switch p["kind"]?.stringValue ?? "talk" {
            case "wave": title = "\(name) waved"; body = "They're nearby."
            case "meet": title = "\(name) wants to meet"; body = "Open the map to see where."
            default: title = "\(name) wants to talk"; body = channelID == nil ? "Open Talk to answer." : "Tap to join the channel."
            }
            category = "PING"
            WatchBridge.shared.notifyIncoming(speaker: name)
        case .friendRequest:
            title = "\(name) wants to add you"; body = "Accept in Profile › Friends."; category = "FRIEND_REQUEST"
            await onFriendsChanged?()
        case .friendAccepted:
            title = "\(name) accepted"; body = "You're on each other's maps now."; category = "GENERAL"
            await onFriendsChanged?()
        case .planLive:
            let planTitle = p["title"]?.stringValue ?? "Your drive"
            title = "\(planTitle) is live"
            body = p["meet_name"]?.stringValue.map { "Everyone's heading to \($0). Talk channel is open." } ?? "Talk channel is open."
            category = "PLAN_LIVE"
        case .other:
            return
        }
        let item = Item(id: UUID(), kind: kind, title: title, body: body, channelID: channelID, fromUser: fromUser, at: .now)
        latest = item
        unread.append(item)
        if UIApplication.shared.applicationState != .active {
            await Self.postLocalNotification(item, category: category)
        }
    }

    /// Local notifications need no APNs entitlement — only the permission the briefing asks for.
    private static func postLocalNotification(_ item: Item, category: String) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        if let c = item.channelID { content.userInfo["channel_id"] = c.uuidString }
        if let f = item.fromUser { content.userInfo["from_user"] = f.uuidString }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil))
    }
}
