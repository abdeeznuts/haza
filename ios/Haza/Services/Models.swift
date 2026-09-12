import Foundation
import HazaCore

// Row types matching backend/supabase/migrations/0001_init.sql. Decoded from PostgREST JSON.

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var handle: String?
    var displayName: String
    var avatarUrl: String?
    var units: String
    var shareSpeed: Bool
    var visibility: String
    var homeSource: String?
    var homeConfidence: Double?
    var homeRadiusM: Int
    var inviteCode: String
    var proUntil: Date?
    var onboardingDone: Bool
    var ghostUntil: Date?

    enum CodingKeys: String, CodingKey {
        case id, handle, units, visibility
        case displayName = "display_name", avatarUrl = "avatar_url", shareSpeed = "share_speed"
        case homeSource = "home_source", homeConfidence = "home_confidence", homeRadiusM = "home_radius_m"
        case inviteCode = "invite_code", proUntil = "pro_until", onboardingDone = "onboarding_done", ghostUntil = "ghost_until"
    }
    var usesMetric: Bool { units == "kmh" }
    var isGhost: Bool { ghostUntil.map { $0 > .now } ?? false }
}

struct Vehicle: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var ownerId: UUID
    var make: String
    var model: String
    var year: Int?
    var nickname: String?
    var colorHex: String?
    var isPrimary: Bool
    enum CodingKeys: String, CodingKey { case id, make, model, year, nickname; case ownerId = "owner_id", colorHex = "color_hex", isPrimary = "is_primary" }
    var title: String { [year.map(String.init), make, model].compactMap { $0 }.joined(separator: " ") }
}

struct FriendLive: Codable, Identifiable, Equatable {
    var userId: UUID
    var displayName: String
    var avatarUrl: String?
    var lat: Double
    var lng: Double
    var speedMps: Double?
    var headingDeg: Double?
    var isDriving: Bool
    var vehicleId: UUID?
    var updatedAt: Date
    var atHome: Bool
    var batteryPct: Int?
    var isCharging: Bool?
    var placeName: String?
    var id: UUID { userId }
    enum CodingKeys: String, CodingKey {
        case lat, lng
        case userId = "user_id", displayName = "display_name", avatarUrl = "avatar_url", speedMps = "speed_mps"
        case headingDeg = "heading_deg", isDriving = "is_driving", vehicleId = "vehicle_id", updatedAt = "updated_at", atHome = "at_home"
        case batteryPct = "battery_pct", isCharging = "is_charging", placeName = "place_name"
    }
    /// "At Work", "Driving · 62", "Parked", "At home" — the one-line status under a friend's name.
    func statusLine(metric: Bool) -> String {
        if atHome { return "At home" }
        if let p = placeName { return "At \(p)" }
        if isDriving { return speedMps.map { "Driving · \(Units.formatSpeed($0, metric: metric))" } ?? "Driving" }
        return "Parked"
    }
    var point: GeoPoint { GeoPoint(latitude: lat, longitude: lng) }
}

struct FriendNearby: Codable, Identifiable, Equatable {
    var userId: UUID
    var displayName: String
    var distanceM: Double
    var isDriving: Bool
    var id: UUID { userId }
    enum CodingKeys: String, CodingKey { case userId = "user_id", displayName = "display_name", distanceM = "distance_m", isDriving = "is_driving" }
}

struct Drive: Codable, Identifiable, Equatable {
    var id: UUID
    var userId: UUID
    var vehicleId: UUID?
    var startedAt: Date
    var endedAt: Date?
    var distanceM: Double
    var durationS: Int
    var avgSpeedMps: Double?
    var maxSpeedMps: Double?
    var hardBrakes: Int?
    var rapidAccels: Int?
    var maxG: Double?
    var zeroToSixtyS: Double?
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id", vehicleId = "vehicle_id", startedAt = "started_at", endedAt = "ended_at"
        case distanceM = "distance_m", durationS = "duration_s", avgSpeedMps = "avg_speed_mps", maxSpeedMps = "max_speed_mps"
        case hardBrakes = "hard_brakes", rapidAccels = "rapid_accels", maxG = "max_g", zeroToSixtyS = "zero_to_sixty_s"
    }
}

struct Place: Codable, Identifiable, Equatable {
    var id: UUID
    var userId: UUID
    var name: String
    var kind: String
    var lat: Double
    var lng: Double
    var radiusM: Int
    var shareWith: String
    var point: GeoPoint { GeoPoint(latitude: lat, longitude: lng) }
    enum CodingKeys: String, CodingKey { case id, name, kind, lat, lng; case userId = "user_id", radiusM = "radius_m", shareWith = "share_with" }
}

struct FriendPref: Codable, Identifiable, Equatable {
    var friendId: UUID
    var notifyDrives: Bool
    var notifyPlaces: Bool
    var id: UUID { friendId }
    enum CodingKeys: String, CodingKey { case friendId = "friend_id", notifyDrives = "notify_drives", notifyPlaces = "notify_places" }
}

struct PlanETA: Codable, Identifiable, Equatable {
    var userId: UUID
    var displayName: String
    var status: String
    var etaAt: Date?
    var etaUpdatedAt: Date?
    var isDriving: Bool
    var id: UUID { userId }
    enum CodingKeys: String, CodingKey { case status; case userId = "user_id", displayName = "display_name", etaAt = "eta_at", etaUpdatedAt = "eta_updated_at", isDriving = "is_driving" }
}

struct TimelineItem: Codable, Identifiable, Equatable {
    var kind: String
    var at: Date
    var title: String?
    var lat: Double?
    var lng: Double?
    var refId: UUID?
    var id: String { "\(kind)-\(at.timeIntervalSince1970)" }
    enum CodingKeys: String, CodingKey { case kind, at, title, lat, lng; case refId = "ref_id" }
}

/// A friend's drive that overlapped one of mine — drawn on the playback map.
struct DriveCompanion: Identifiable, Equatable {
    var driveId: UUID
    var userId: UUID
    var displayName: String
    var startedAt: Date
    var endedAt: Date?
    var route: [GeoPoint]
    var id: UUID { driveId }
}

struct Crew: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    var inviteCode: String
    enum CodingKeys: String, CodingKey { case id, name, emoji; case inviteCode = "invite_code" }
}

struct PlannedDrive: Codable, Identifiable, Equatable {
    var id: UUID
    var crewId: UUID?
    var creatorId: UUID
    var title: String
    var notes: String?
    var startsAt: Date
    var meetName: String?
    var status: String
    enum CodingKeys: String, CodingKey { case id, title, notes, status; case crewId = "crew_id", creatorId = "creator_id", startsAt = "starts_at", meetName = "meet_name" }
}

struct TalkChannel: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var kind: String
    var crewId: UUID?
    var planId: UUID?
    var peerA: UUID?
    var peerB: UUID?
    var livekitRoom: String
    enum CodingKeys: String, CodingKey { case id, kind; case crewId = "crew_id", planId = "plan_id", peerA = "peer_a", peerB = "peer_b", livekitRoom = "livekit_room" }
}

struct RadarAlertRow: Codable, Identifiable, Equatable {
    var id: UUID
    var userId: UUID
    var band: String
    var freqMhz: Int?
    var strength: Int?
    var direction: String?
    var lat: Double
    var lng: Double
    var ts: Date
    enum CodingKeys: String, CodingKey { case id, band, strength, direction, lat, lng, ts; case userId = "user_id", freqMhz = "freq_mhz" }
}

struct ProStatus: Codable, Equatable {
    var isPro = false
    var proUntil: Date?
    var referrals = 0
    var subscriptionProduct: String?
    var subscriptionExpires: Date?
    struct Sub: Codable { var productId: String?; var expiresAt: Date?; var status: String?
        enum CodingKeys: String, CodingKey { case productId = "product_id", expiresAt = "expires_at", status } }
    enum CodingKeys: String, CodingKey { case isPro = "is_pro", proUntil = "pro_until", referrals, subscription }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isPro = try c.decodeIfPresent(Bool.self, forKey: .isPro) ?? false
        proUntil = try c.decodeIfPresent(Date.self, forKey: .proUntil)
        referrals = try c.decodeIfPresent(Int.self, forKey: .referrals) ?? 0
        let sub = try c.decodeIfPresent(Sub.self, forKey: .subscription)
        subscriptionProduct = sub?.productId; subscriptionExpires = sub?.expiresAt
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isPro, forKey: .isPro); try c.encode(proUntil, forKey: .proUntil); try c.encode(referrals, forKey: .referrals)
    }
}

struct FoundProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var handle: String?
    var displayName: String
    var avatarUrl: String?
    var isFriend: Bool
    var requestPending: Bool
    enum CodingKeys: String, CodingKey { case id, handle; case displayName = "display_name", avatarUrl = "avatar_url", isFriend = "is_friend", requestPending = "request_pending" }
}

struct PendingRequest: Codable, Identifiable, Equatable {
    var userId: UUID
    var handle: String?
    var displayName: String
    var avatarUrl: String?
    var createdAt: Date
    var id: UUID { userId }
    enum CodingKeys: String, CodingKey { case handle; case userId = "user_id", displayName = "display_name", avatarUrl = "avatar_url", createdAt = "created_at" }
}
