// The "briefing": what this person is missing and what they haven't used yet.
// Server facts come from `my_briefing()`; device facts are collected by the app. Merged and ordered here.
import Foundation

public struct BriefingItem: Identifiable, Equatable, Sendable {
    public enum Severity: String, Sendable { case setup, privacy, feature, pro }
    public enum Action: Equatable, Sendable {
        case requestLocationAlways, addVehicle, confirmHome, setHome, inviteFriend, createCrew, pairRadar
        case installWatchApp, addCarPlayWidget, addControl, enableNotifications, viewReferrals
    }
    public var id: String { key }
    public var key: String
    public var severity: Severity
    public var title: String
    public var detail: String
    public var action: Action

    public init(key: String, severity: Severity, title: String, detail: String, action: Action) {
        self.key = key; self.severity = severity; self.title = title; self.detail = detail; self.action = action
    }
}

public struct DeviceFacts: Equatable, Sendable {
    public var locationAlways: Bool
    public var notificationsAllowed: Bool
    public var watchAppInstalled: Bool
    public var carPlayWidgetSeen: Bool       // user has opened the CarPlay setup page or the widget reported a render
    public var controlAdded: Bool
    public init(locationAlways: Bool = false, notificationsAllowed: Bool = false, watchAppInstalled: Bool = false, carPlayWidgetSeen: Bool = false, controlAdded: Bool = false) {
        self.locationAlways = locationAlways; self.notificationsAllowed = notificationsAllowed
        self.watchAppInstalled = watchAppInstalled; self.carPlayWidgetSeen = carPlayWidgetSeen; self.controlAdded = controlAdded
    }
}

public struct ServerBriefingRow: Equatable, Sendable {
    public var key: String, severity: String, title: String, detail: String
    public init(key: String, severity: String, title: String, detail: String) {
        self.key = key; self.severity = severity; self.title = title; self.detail = detail
    }
}

public enum Briefing {
    static let order: [String] = ["location_always", "no_vehicle", "home_inferred", "no_home", "no_friends", "notifications",
                                  "no_crew", "watch_app", "carplay_widget", "control", "no_radar", "referral_progress"]

    public static func merge(server: [ServerBriefingRow], device: DeviceFacts) -> [BriefingItem] {
        var items: [BriefingItem] = []
        if !device.locationAlways {
            items.append(.init(key: "location_always", severity: .setup, title: "Location: Always",
                               detail: "So drives record themselves and friends can find you when the app is closed. You can pick 'While Using' instead — drives then only record while Haza is open.",
                               action: .requestLocationAlways))
        }
        if !device.notificationsAllowed {
            items.append(.init(key: "notifications", severity: .setup, title: "Allow notifications",
                               detail: "Pings, 'wants to talk', and plan updates arrive as notifications.", action: .enableNotifications))
        }
        for row in server {
            let action: BriefingItem.Action
            switch row.key {
            case "no_vehicle": action = .addVehicle
            case "no_friends": action = .inviteFriend
            case "no_home": action = .setHome
            case "home_inferred": action = .confirmHome
            case "no_crew": action = .createCrew
            case "no_radar": action = .pairRadar
            case "referral_progress": action = .viewReferrals
            default: continue
            }
            items.append(.init(key: row.key, severity: BriefingItem.Severity(rawValue: row.severity) ?? .feature,
                               title: row.title, detail: row.detail, action: action))
        }
        if !device.watchAppInstalled {
            items.append(.init(key: "watch_app", severity: .feature, title: "Install the Watch app",
                               detail: "Hold to talk from your wrist and feel a tap when someone speaks.", action: .installWatchApp))
        }
        if !device.carPlayWidgetSeen {
            items.append(.init(key: "carplay_widget", severity: .feature, title: "Add the CarPlay widget",
                               detail: "Talk on/off and your speed on the car's Dashboard. Settings › General › CarPlay › your car.", action: .addCarPlayWidget))
        }
        if !device.controlAdded {
            items.append(.init(key: "control", severity: .feature, title: "Put Talk in Control Center",
                               detail: "One toggle to join or leave your crew channel from anywhere.", action: .addControl))
        }
        return items.sorted { (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99) }
    }

    /// Headline for the briefing page.
    public static func headline(remaining: Int) -> String {
        switch remaining {
        case 0: return "You're set. Go drive."
        case 1: return "One thing before your first drive."
        case 2: return "Two things before your first drive."
        case 3: return "Three things before your first drive."
        case 4: return "Four things before your first drive."
        default: return "A few things before your first drive."
        }
    }
}
