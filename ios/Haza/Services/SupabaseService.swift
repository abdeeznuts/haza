import Foundation
import Supabase
import HazaCore

/// Thin wrapper over supabase-swift. All RPC names match backend/supabase/migrations/0001_init.sql.
final class SupabaseService: @unchecked Sendable {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private let decoder: JSONDecoder

    private init() {
        client = SupabaseClient(supabaseURL: HazaBrand.supabaseURL, supabaseKey: HazaBrand.supabaseKey)
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(), debugDescription: "bad date \(s)")
        }
        decoder = d
    }

    var userID: UUID? { client.auth.currentUser?.id }

    // MARK: Auth

    func restoreSession() async throws -> Bool {
        do { _ = try await client.auth.session; return true } catch { return false }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        _ = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        if let fullName, !fullName.isEmpty {
            try await client.from("profiles").update(["display_name": fullName]).eq("id", value: userID!.uuidString).execute()
        }
    }

    /// Beta sign-in with no email round-trip: the `signup` function creates a confirmed user (or reports
    /// that one exists), then we sign in with the password. Returns true when the account was just created.
    func signInOrSignUp(email: String, password: String, displayName: String?) async throws -> Bool {
        struct R: Decodable { var ok: Bool; var created: Bool?; var exists: Bool? }
        var body: [String: String] = ["email": email, "password": password]
        if let displayName, !displayName.isEmpty { body["display_name"] = displayName }
        let r: R = try await client.functions.invoke("signup", options: .init(body: body))
        do {
            try await client.auth.signIn(email: email, password: password)
        } catch {
            if r.exists == true { throw ServiceError.wrongPassword }
            throw error
        }
        return r.created == true
    }

    func sendMagicLink(email: String) async throws {
        try await client.auth.signInWithOTP(email: email, redirectTo: URL(string: "haza://auth"))
    }

    /// The 6-digit code from the same email (Supabase "Magic Link" template must include {{ .Token }}),
    /// or — safety net when the template has no code and the link can't open the app — the pasted
    /// link itself: its `token` query item is a token hash the API accepts directly.
    func verifyEmailCode(email: String, code: String) async throws {
        if let hash = Self.tokenHash(fromLink: code) {
            try await client.auth.verifyOTP(tokenHash: hash, type: .magiclink)
            return
        }
        try await client.auth.verifyOTP(email: email, token: code.filter(\.isNumber), type: .email)
    }

    static func tokenHash(fromLink text: String) -> String? {
        guard text.contains("token="), let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first { $0.name == "token" || $0.name == "token_hash" }?.value
    }

    /// `haza://auth#access_token=…` — the magic link redirected into the app.
    func session(from url: URL) async throws {
        _ = try await client.auth.session(from: url)
    }

    func signOut() async throws { try await client.auth.signOut() }

    /// Ordinary alert pushes (pings, plans going live, referral rewards) go to `device_tokens`;
    /// the PTT ephemeral token is separate (see TalkService).
    func registerAPNsToken(_ token: Data) async {
        guard let id = userID else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await client.from("device_tokens").upsert([
            "user_id": AnyJSON.string(id.uuidString),
            "token": .string(token.map { String(format: "%02x", $0) }.joined()),
            "platform": .string("ios"),
            "environment": .string(environment),
            "updated_at": .string(ISO8601DateFormatter().string(from: .now)),
        ]).execute()
    }

    // MARK: Profile & briefing

    func myProfile() async throws -> Profile {
        guard let id = userID else { throw ServiceError.notSignedIn }
        let data = try await client.from("profiles").select().eq("id", value: id.uuidString).single().execute().data
        return try decoder.decode(Profile.self, from: data)
    }

    func updateProfile(_ fields: [String: AnyJSON]) async throws {
        guard let id = userID else { throw ServiceError.notSignedIn }
        try await client.from("profiles").update(fields).eq("id", value: id.uuidString).execute()
    }

    func markOnboardingDone() async throws { try await updateProfile(["onboarding_done": .bool(true)]) }

    func myBriefing() async throws -> [ServerBriefingRow] {
        struct Row: Decodable { var key, severity, title, detail: String }
        let data = try await client.rpc("my_briefing").execute().data
        return try decoder.decode([Row].self, from: data).map { ServerBriefingRow(key: $0.key, severity: $0.severity, title: $0.title, detail: $0.detail) }
    }

    func myPro() async throws -> ProStatus {
        let data = try await client.rpc("my_pro").execute().data
        return try decoder.decode(ProStatus.self, from: data)
    }

    func claimInvite(code: String, deviceHash: String) async throws -> Bool {
        struct R: Decodable { var ok: Bool; var reason: String? }
        let data = try await client.rpc("claim_invite", params: ["p_code": code, "p_device_hash": deviceHash]).execute().data
        return try decoder.decode(R.self, from: data).ok
    }

    func setHome(_ p: GeoPoint, source: String) async throws {
        // PostGIS accepts EWKT through PostgREST.
        try await updateProfile(["home_point": .string("SRID=4326;POINT(\(p.longitude) \(p.latitude))"), "home_source": .string(source), "home_confidence": .double(1)])
    }

    func homeSuggestion() async throws -> HomeSuggestion? {
        struct Row: Decodable { var lat: Double; var lng: Double; var confidence: Double; var nightCount: Int
            enum CodingKeys: String, CodingKey { case lat, lng, confidence; case nightCount = "night_count" } }
        let data = try await client.rpc("my_home_suggestion").execute().data
        guard let r = try decoder.decode([Row].self, from: data).first else { return nil }
        return HomeSuggestion(point: GeoPoint(latitude: r.lat, longitude: r.lng), nights: r.nightCount, confidence: r.confidence)
    }

    func uploadHomeSamples(_ samples: [HomeSample]) async throws {
        guard let id = userID else { return }
        let rows = samples.map { ["user_id": AnyJSON.string(id.uuidString), "ts": .string(ISO8601DateFormatter().string(from: $0.time)),
                                  "point": .string("SRID=4326;POINT(\($0.point.longitude) \($0.point.latitude))")] }
        try await client.from("home_samples").upsert(rows).execute()
    }

    func deleteMyAccount() async throws { try await client.rpc("delete_my_account").execute() }

    // MARK: Friends & location

    func friendsLive() async throws -> [FriendLive] {
        try decoder.decode([FriendLive].self, from: try await client.rpc("friends_live").execute().data)
    }

    func friendsNearby(radiusMeters: Int) async throws -> [FriendNearby] {
        try decoder.decode([FriendNearby].self, from: try await client.rpc("friends_nearby", params: ["p_radius_m": radiusMeters]).execute().data)
    }

    func upsertLiveLocation(_ p: GeoPoint, speed: Double?, heading: Double?, accuracy: Double?, driving: Bool, vehicleID: UUID?, battery: Int? = nil, charging: Bool? = nil) async throws {
        guard let id = userID else { return }
        var row: [String: AnyJSON] = [
            "user_id": .string(id.uuidString),
            "point": .string("SRID=4326;POINT(\(p.longitude) \(p.latitude))"),
            "is_driving": .bool(driving),
            "updated_at": .string(ISO8601DateFormatter().string(from: .now)),
        ]
        if let speed { row["speed_mps"] = .double(speed) }
        if let heading { row["heading_deg"] = .double(heading) }
        if let accuracy { row["accuracy_m"] = .double(accuracy) }
        if let vehicleID { row["vehicle_id"] = .string(vehicleID.uuidString) }
        if let battery { row["battery_pct"] = .integer(battery) }
        if let charging { row["is_charging"] = .bool(charging) }
        try await client.from("live_locations").upsert(row).execute()
    }

    // MARK: Places, prefs, ghost, check-in, SOS, ETAs, timeline, recap

    func myPlaces() async throws -> [Place] {
        try decoder.decode([Place].self, from: try await client.rpc("my_places").execute().data)
    }

    func addPlace(name: String, kind: String, point: GeoPoint, radius: Int, shareWithFriends: Bool) async throws {
        guard let id = userID else { throw ServiceError.notSignedIn }
        try await client.from("places").insert([
            "user_id": AnyJSON.string(id.uuidString), "name": .string(name), "kind": .string(kind),
            "point": .string("SRID=4326;POINT(\(point.longitude) \(point.latitude))"),
            "radius_m": .integer(radius), "share_with": .string(shareWithFriends ? "friends" : "nobody"),
        ]).execute()
    }

    func deletePlace(_ id: UUID) async throws {
        try await client.from("places").delete().eq("id", value: id.uuidString).execute()
    }

    func placeEvent(_ placeID: UUID, event: String) async throws {
        guard let id = userID else { return }
        try await client.from("place_events").insert(["user_id": id.uuidString, "place_id": placeID.uuidString, "event": event]).execute()
    }

    func driveEvent(_ event: String, at p: GeoPoint) async throws {
        guard let id = userID else { return }
        try await client.from("drive_events").insert([
            "user_id": AnyJSON.string(id.uuidString), "event": .string(event),
            "point": .string("SRID=4326;POINT(\(p.longitude) \(p.latitude))"),
        ]).execute()
    }

    func friendPrefs() async throws -> [FriendPref] {
        try decoder.decode([FriendPref].self, from: try await client.rpc("my_friend_prefs").execute().data)
    }

    func setFriendPref(_ friend: UUID, notifyDrives: Bool, notifyPlaces: Bool) async throws {
        guard let id = userID else { return }
        try await client.from("friend_prefs").upsert([
            "user_id": AnyJSON.string(id.uuidString), "friend_id": .string(friend.uuidString),
            "notify_drives": .bool(notifyDrives), "notify_places": .bool(notifyPlaces),
        ]).execute()
    }

    /// nil = visible; a date = hidden until then; .distantFuture = until turned off.
    func setGhost(until: Date?) async throws {
        let iso = ISO8601DateFormatter()
        try await client.rpc("set_ghost", params: ["p_until": until.map { AnyJSON.string(iso.string(from: $0)) } ?? .null]).execute()
    }

    func checkIn(to friends: [UUID], at p: GeoPoint, note: String?) async throws {
        guard let id = userID else { return }
        let rows: [[String: AnyJSON]] = friends.map { f in
            var r: [String: AnyJSON] = ["from_user": .string(id.uuidString), "to_user": .string(f.uuidString), "kind": .string("checkin"),
                                        "point": .string("SRID=4326;POINT(\(p.longitude) \(p.latitude))")]
            if let note, !note.isEmpty { r["note"] = .string(note) }
            return r
        }
        if !rows.isEmpty { try await client.from("pings").insert(rows).execute() }
    }

    func sendSOS(lat: Double, lng: Double, note: String?) async throws -> Int {
        var params: [String: AnyJSON] = ["p_lat": .double(lat), "p_lng": .double(lng)]
        if let note { params["p_note"] = .string(note) }
        let data = try await client.rpc("send_sos", params: params).execute().data
        return (try? decoder.decode(Int.self, from: data)) ?? 0
    }

    func planETAs(_ plan: UUID) async throws -> [PlanETA] {
        try decoder.decode([PlanETA].self, from: try await client.rpc("plan_etas", params: ["p_plan": plan.uuidString]).execute().data)
    }

    func setPlanETA(_ plan: UUID, eta: Date) async throws {
        try await client.rpc("set_plan_eta", params: ["p_plan": AnyJSON.string(plan.uuidString), "p_eta": .string(ISO8601DateFormatter().string(from: eta))]).execute()
    }

    func planMeetPoint(_ plan: UUID) async throws -> GeoPoint? {
        struct Row: Decodable { var lat: Double?; var lng: Double? }
        let data = try await client.rpc("plan_meet_point", params: ["p_plan": plan.uuidString]).execute().data
        guard let r = try decoder.decode([Row].self, from: data).first, let lat = r.lat, let lng = r.lng else { return nil }
        return GeoPoint(latitude: lat, longitude: lng)
    }

    func timeline(day: Date) async throws -> [TimelineItem] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return try decoder.decode([TimelineItem].self, from: try await client.rpc("my_timeline", params: ["p_day": f.string(from: day)]).execute().data)
    }

    struct WeeklyRecap: Decodable {
        var drives: Int; var miles: Double; var hours: Double
        var bestZeroSixty: Double?; var maxG: Double?; var hardBrakes: Int; var rapidAccels: Int; var topSpeedMps: Double?
        enum CodingKeys: String, CodingKey { case drives, miles, hours; case bestZeroSixty = "best_zero_sixty", maxG = "max_g", hardBrakes = "hard_brakes", rapidAccels = "rapid_accels", topSpeedMps = "top_speed_mps" }
    }
    func weeklyRecap() async throws -> WeeklyRecap {
        try decoder.decode(WeeklyRecap.self, from: try await client.rpc("weekly_recap").execute().data)
    }

    func findProfile(handle: String) async throws -> FoundProfile? {
        let data = try await client.rpc("find_profile", params: ["p_handle": handle]).execute().data
        return try decoder.decode([FoundProfile].self, from: data).first
    }

    func pendingRequests() async throws -> [PendingRequest] {
        try decoder.decode([PendingRequest].self, from: try await client.rpc("pending_requests").execute().data)
    }

    func respond(to from: UUID, accept: Bool) async throws {
        try await client.rpc("respond_request", params: ["p_from": AnyJSON.string(from.uuidString), "p_accept": .bool(accept)]).execute()
    }

    func setHandle(_ handle: String) async throws { try await updateProfile(["handle": .string(handle)]) }

    func sendFriendRequest(to friend: UUID) async throws {
        guard let id = userID else { return }
        try await client.from("friendships").insert(["user_id": id.uuidString, "friend_id": friend.uuidString, "status": "pending"]).execute()
    }

    func ping(_ friend: UUID, kind: String = "talk", channel: UUID?) async throws {
        guard let id = userID else { return }
        var row: [String: AnyJSON] = ["from_user": .string(id.uuidString), "to_user": .string(friend.uuidString), "kind": .string(kind)]
        if let channel { row["channel_id"] = .string(channel.uuidString) }
        try await client.from("pings").insert(row).execute()
    }

    // MARK: Garage, drives, crews, plans

    func vehicles() async throws -> [Vehicle] {
        guard let id = userID else { return [] }
        return try decoder.decode([Vehicle].self, from: try await client.from("vehicles").select().eq("owner_id", value: id.uuidString).order("is_primary", ascending: false).execute().data)
    }

    func addVehicle(make: String, model: String, year: Int?, colorHex: String?, primary: Bool) async throws {
        guard let id = userID else { return }
        var row: [String: AnyJSON] = ["owner_id": .string(id.uuidString), "make": .string(make), "model": .string(model), "is_primary": .bool(primary)]
        if let year { row["year"] = .integer(year) }
        if let colorHex { row["color_hex"] = .string(colorHex) }
        try await client.from("vehicles").insert(row).execute()
    }

    func drives(limit: Int = 60) async throws -> [Drive] {
        guard let id = userID else { return [] }
        return try decoder.decode([Drive].self, from: try await client.from("drives").select().eq("user_id", value: id.uuidString).order("started_at", ascending: false).limit(limit).execute().data)
    }

    /// The simplified route of one of my drives as [lng, lat] pairs (GeoJSON order).
    func driveRoute(_ drive: UUID) async throws -> [GeoPoint] {
        let data = try await client.rpc("drive_route", params: ["p_drive": drive.uuidString]).execute().data
        return try decoder.decode([[Double]].self, from: data).compactMap { $0.count >= 2 ? GeoPoint(latitude: $0[1], longitude: $0[0]) : nil }
    }

    /// Friends whose drives overlapped mine in time, with their (home-clipped) routes.
    func driveCompanions(_ drive: UUID) async throws -> [DriveCompanion] {
        struct Row: Decodable { var driveId: UUID; var userId: UUID; var displayName: String; var startedAt: Date; var endedAt: Date?; var coordinates: [[Double]]
            enum CodingKeys: String, CodingKey { case coordinates; case driveId = "drive_id", userId = "user_id", displayName = "display_name", startedAt = "started_at", endedAt = "ended_at" } }
        let data = try await client.rpc("drive_companions", params: ["p_drive": drive.uuidString]).execute().data
        return try decoder.decode([Row].self, from: data).map { r in
            DriveCompanion(driveId: r.driveId, userId: r.userId, displayName: r.displayName, startedAt: r.startedAt, endedAt: r.endedAt,
                           route: r.coordinates.compactMap { $0.count >= 2 ? GeoPoint(latitude: $0[1], longitude: $0[0]) : nil })
        }
    }

    func insertDrive(startedAt: Date, endedAt: Date, distanceM: Double, durationS: Int, avg: Double?, max: Double?, vehicleID: UUID?, route: [GeoPoint],
                     hardBrakes: Int = 0, rapidAccels: Int = 0, maxG: Double? = nil, zeroToSixty: Double? = nil) async throws -> UUID {
        guard let id = userID else { throw ServiceError.notSignedIn }
        let iso = ISO8601DateFormatter()
        var row: [String: AnyJSON] = [
            "user_id": .string(id.uuidString), "started_at": .string(iso.string(from: startedAt)), "ended_at": .string(iso.string(from: endedAt)),
            "distance_m": .double(distanceM), "duration_s": .integer(durationS), "is_auto": .bool(true),
            "hard_brakes": .integer(hardBrakes), "rapid_accels": .integer(rapidAccels),
        ]
        if let maxG, maxG > 0 { row["max_g"] = .double(maxG) }
        if let zeroToSixty { row["zero_to_sixty_s"] = .double(zeroToSixty) }
        if let avg { row["avg_speed_mps"] = .double(avg) }
        if let max { row["max_speed_mps"] = .double(max) }
        if let vehicleID { row["vehicle_id"] = .string(vehicleID.uuidString) }
        if let first = route.first { row["start_point"] = .string("SRID=4326;POINT(\(first.longitude) \(first.latitude))") }
        if let last = route.last { row["end_point"] = .string("SRID=4326;POINT(\(last.longitude) \(last.latitude))") }
        if route.count >= 2 {
            let wkt = route.map { "\($0.longitude) \($0.latitude)" }.joined(separator: ",")
            row["route"] = .string("SRID=4326;LINESTRING(\(wkt))")
        }
        struct R: Decodable { var id: UUID }
        let data = try await client.from("drives").insert(row).select("id").single().execute().data
        return try decoder.decode(R.self, from: data).id
    }

    func crews() async throws -> [Crew] {
        try decoder.decode([Crew].self, from: try await client.from("crews").select().execute().data)
    }

    func createCrew(name: String, emoji: String) async throws -> Crew {
        guard let id = userID else { throw ServiceError.notSignedIn }
        let data = try await client.from("crews").insert(["name": name, "emoji": emoji, "created_by": id.uuidString]).select().single().execute().data
        let crew = try decoder.decode(Crew.self, from: data)
        try await client.from("crew_members").insert(["crew_id": crew.id.uuidString, "user_id": id.uuidString, "role": "owner"]).execute()
        try await client.from("talk_channels").insert(["kind": "crew", "crew_id": crew.id.uuidString]).execute()
        return crew
    }

    func joinCrew(code: String) async throws -> UUID {
        let data = try await client.rpc("join_crew", params: ["p_code": code]).execute().data
        return try decoder.decode(UUID.self, from: data)
    }

    func goLive(plan: UUID) async throws {
        try await client.rpc("go_live", params: ["p_plan": plan.uuidString]).execute()
    }

    func plans() async throws -> [PlannedDrive] {
        try decoder.decode([PlannedDrive].self, from: try await client.from("planned_drives").select().gte("starts_at", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-6 * 3600))).order("starts_at").execute().data)
    }

    func createPlan(title: String, startsAt: Date, crewID: UUID?, meetName: String?, meetPoint: GeoPoint?, notes: String?) async throws {
        guard let id = userID else { return }
        var row: [String: AnyJSON] = ["creator_id": .string(id.uuidString), "title": .string(title), "starts_at": .string(ISO8601DateFormatter().string(from: startsAt))]
        if let crewID { row["crew_id"] = .string(crewID.uuidString) }
        if let meetName { row["meet_name"] = .string(meetName) }
        if let meetPoint { row["meet_point"] = .string("SRID=4326;POINT(\(meetPoint.longitude) \(meetPoint.latitude))") }
        if let notes { row["notes"] = .string(notes) }
        struct R: Decodable { var id: UUID }
        let data = try await client.from("planned_drives").insert(row).select("id").single().execute().data
        let planID = try decoder.decode(R.self, from: data).id
        try await client.from("plan_rsvps").insert(["plan_id": planID.uuidString, "user_id": id.uuidString, "status": "going"]).execute()
        try await client.from("talk_channels").insert(["kind": "plan", "plan_id": planID.uuidString]).execute()
    }

    func rsvp(plan: UUID, status: String) async throws {
        guard let id = userID else { return }
        try await client.from("plan_rsvps").upsert(["plan_id": plan.uuidString, "user_id": id.uuidString, "status": status]).execute()
    }

    // MARK: Talk

    func channels() async throws -> [TalkChannel] {
        try decoder.decode([TalkChannel].self, from: try await client.from("talk_channels").select().execute().data)
    }

    func directChannel(with friend: UUID) async throws -> UUID {
        let data = try await client.rpc("direct_channel", params: ["p_friend": friend.uuidString]).execute().data
        return try decoder.decode(UUID.self, from: data)
    }

    func liveKitToken(channel: UUID) async throws -> (token: String, url: URL, room: String) {
        struct R: Decodable { var token: String; var url: URL; var room: String }
        let r: R = try await client.functions.invoke("livekit-token", options: .init(body: ["channel_id": channel.uuidString]))
        return (r.token, r.url, r.room)
    }

    func notifyTransmission(channel: UUID, begin: Bool) async {
        struct R: Decodable { var sent: Int }
        _ = try? await client.functions.invoke("ptt-notify", options: .init(body: ["channel_id": channel.uuidString, "event": begin ? "begin" : "end"])) as R
    }

    func storePTTToken(_ token: Data, channel: UUID) async throws {
        guard let id = userID else { return }
        try await client.from("talk_members").upsert([
            "channel_id": AnyJSON.string(channel.uuidString), "user_id": .string(id.uuidString),
            "ptt_token": .string(token.map { String(format: "%02x", $0) }.joined()),
            "ptt_token_at": .string(ISO8601DateFormatter().string(from: .now)), "joined": .bool(true),
        ]).execute()
    }

    func setJoined(_ joined: Bool, channel: UUID) async throws {
        guard let id = userID else { return }
        try await client.from("talk_members").update(["joined": joined]).eq("channel_id", value: channel.uuidString).eq("user_id", value: id.uuidString).execute()
    }

    // MARK: Radar

    func shareRadarAlert(band: String, freq: Int?, strength: Int, direction: String, at p: GeoPoint, heading: Double?) async throws {
        guard let id = userID else { return }
        var row: [String: AnyJSON] = ["user_id": .string(id.uuidString), "band": .string(band), "strength": .integer(strength), "direction": .string(direction),
                                     "point": .string("SRID=4326;POINT(\(p.longitude) \(p.latitude))")]
        if let freq { row["freq_mhz"] = .integer(freq) }
        if let heading { row["heading_deg"] = .double(heading) }
        try await client.from("radar_alerts").insert(row).execute()
    }

    func radarAlertsNear(_ p: GeoPoint, radius: Int = 8000) async throws -> [RadarAlertRow] {
        try decoder.decode([RadarAlertRow].self, from: try await client.rpc("radar_alerts_near", params: ["p_lat": p.latitude, "p_lng": p.longitude, "p_radius_m": Double(radius)]).execute().data)
    }

    func registerRadarDevice(brand: String, model: String?, identifier: String?, firmware: String?) async throws {
        guard let id = userID else { return }
        var row: [String: AnyJSON] = ["user_id": .string(id.uuidString), "brand": .string(brand), "last_seen_at": .string(ISO8601DateFormatter().string(from: .now))]
        if let model { row["model"] = .string(model) }
        if let identifier { row["ble_identifier"] = .string(identifier) }
        if let firmware { row["firmware"] = .string(firmware) }
        try await client.from("radar_devices").insert(row).execute()
    }

    // MARK: Purchases

    func verifyTransaction(jws: String) async throws -> ProStatus {
        struct R: Decodable { var ok: Bool; var is_pro: Bool }
        let r: R = try await client.functions.invoke("iap/verify-transaction", options: .init(body: ["jws_representation": jws]))
        var p = try await myPro(); p.isPro = p.isPro || r.is_pro
        return p
    }
}

enum ServiceError: LocalizedError {
    case notSignedIn, notConfigured(String), wrongPassword
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're signed out."
        case .notConfigured(let what): return "\(what) isn't set up yet."
        case .wrongPassword: return "That email already has an account and the password doesn't match."
        }
    }
}
