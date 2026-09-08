import Foundation

/// App Group storage read by the widgets, the Live Activity, the Control and the Watch bridge.
/// The app writes; extensions read. Everything here is small and non-sensitive.
public struct TalkSnapshot: Codable, Equatable {
    public var channelID: String?
    public var channelName: String
    public var joined: Bool
    public var activeSpeaker: String?
    public var listeners: Int
    public init(channelID: String? = nil, channelName: String = "No channel", joined: Bool = false, activeSpeaker: String? = nil, listeners: Int = 0) {
        self.channelID = channelID; self.channelName = channelName; self.joined = joined; self.activeSpeaker = activeSpeaker; self.listeners = listeners
    }
}

public struct DriveSnapshot: Codable, Equatable {
    public var speedMPH: Int
    public var predictedMPH: Int
    public var speedLimitMPH: Int?
    public var roadName: String?
    public var nearestFriend: String?
    public var nearestFriendDistanceMiles: Double?
    public var nextPlanTitle: String?
    public var nextPlanTime: Date?
    public var radarSummary: String
    public var updatedAt: Date
    public init(speedMPH: Int = 0, predictedMPH: Int = 0, speedLimitMPH: Int? = nil, roadName: String? = nil, nearestFriend: String? = nil, nearestFriendDistanceMiles: Double? = nil, nextPlanTitle: String? = nil, nextPlanTime: Date? = nil, radarSummary: String = "Radar quiet", updatedAt: Date = .now) {
        self.speedMPH = speedMPH; self.predictedMPH = predictedMPH; self.speedLimitMPH = speedLimitMPH; self.roadName = roadName
        self.nearestFriend = nearestFriend; self.nearestFriendDistanceMiles = nearestFriendDistanceMiles
        self.nextPlanTitle = nextPlanTitle; self.nextPlanTime = nextPlanTime; self.radarSummary = radarSummary; self.updatedAt = updatedAt
    }
}

public enum SharedStore {
    /// The App Group container when this build is entitled to it; otherwise the app's own defaults
    /// (a free-Apple-ID build has no group, and asking for one just logs errors).
    static let defaults: UserDefaults = {
        guard Entitlements.appGroups, let d = UserDefaults(suiteName: HazaBrand.appGroup) else { return .standard }
        return d
    }()
    static let talkKey = "talk.snapshot", driveKey = "drive.snapshot", pendingToggleKey = "talk.pendingToggle"

    public static var talk: TalkSnapshot {
        get { load(talkKey) ?? TalkSnapshot() }
        set { save(newValue, talkKey) }
    }
    public static var drive: DriveSnapshot {
        get { load(driveKey) ?? DriveSnapshot() }
        set { save(newValue, driveKey) }
    }
    /// Set by the widget/control intent; the app consumes it on next launch/foreground.
    public static var pendingTalkToggle: Bool? {
        get { defaults.object(forKey: pendingToggleKey) as? Bool }
        set { if let v = newValue { defaults.set(v, forKey: pendingToggleKey) } else { defaults.removeObject(forKey: pendingToggleKey) } }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private static func save<T: Encodable>(_ v: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(v), forKey: key)
    }
}
