import Foundation
import UserNotifications
import Observation
import HazaCore
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Notifications

enum NotificationsService {
    static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

// MARK: - Home (manual, contacts card, inferred)

@Observable @MainActor
final class HomeService {
    static let shared = HomeService()
    private var pending: [HomeSample] = []
    private(set) var suggestion: HomeSuggestion?

    /// Overnight dwell sample from LocationService; buffered locally, uploaded in small batches.
    func record(_ s: HomeSample) {
        pending.append(s)
        if pending.count >= 6 { flush() }
        suggestion = HomeInference.suggest(from: pending + stored())
        persist(s)
    }

    func flush() {
        let batch = pending; pending.removeAll()
        Task { try? await SupabaseService.shared.uploadHomeSamples(batch) }
    }

    func refreshSuggestion() async {
        if let s = try? await SupabaseService.shared.homeSuggestion() { suggestion = s }
    }

    func confirm(_ p: GeoPoint, source: String) async {
        try? await SupabaseService.shared.setHome(p, source: source)
    }

    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("home-samples.json") }
    private struct Row: Codable { var t: Double; var la: Double; var lo: Double }
    private func stored() -> [HomeSample] {
        guard let d = try? Data(contentsOf: url), let rows = try? JSONDecoder().decode([Row].self, from: d) else { return [] }
        return rows.suffix(400).map { HomeSample(time: Date(timeIntervalSince1970: $0.t), point: GeoPoint(latitude: $0.la, longitude: $0.lo)) }
    }
    private func persist(_ s: HomeSample) {
        var rows = (try? JSONDecoder().decode([Row].self, from: (try? Data(contentsOf: url)) ?? Data())) ?? []
        rows.append(Row(t: s.time.timeIntervalSince1970, la: s.point.latitude, lo: s.point.longitude))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(rows.suffix(400)).write(to: url, options: .atomic)
    }
}

// MARK: - Live Activity for the active drive (Dynamic Island, Lock Screen, Watch Smart Stack, CarPlay Dashboard)

@MainActor
final class DriveActivityController {
    static let shared = DriveActivityController()
    #if canImport(ActivityKit)
    private var activity: Activity<DriveActivityAttributes>?
    private var lastPush = Date.distantPast
    #endif

    func start(title: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attrs = DriveActivityAttributes(title: title, startedAt: .now)
        let state = DriveActivityAttributes.ContentState(speedMPH: 0, predictedMPH: 0, distanceMiles: 0, elapsedSeconds: 0, carsInConvoy: 1, talkJoined: SharedStore.talk.joined, activeSpeaker: nil, radarSummary: "Radar quiet")
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil), pushType: nil)
        #endif
    }

    func update(speed: Int, predicted: Int, distanceMiles: Double, elapsed: Int) {
        #if canImport(ActivityKit)
        guard let activity, Date.now.timeIntervalSince(lastPush) > 5 else { return }   // ActivityKit throttles; 5 s is plenty
        lastPush = .now
        let talk = SharedStore.talk
        let state = DriveActivityAttributes.ContentState(speedMPH: speed, predictedMPH: predicted, distanceMiles: distanceMiles, elapsedSeconds: elapsed,
                                                          carsInConvoy: max(1, talk.listeners + 1), talkJoined: talk.joined, activeSpeaker: talk.activeSpeaker,
                                                          radarSummary: SharedStore.drive.radarSummary)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .after(.now + 60)) }
        #endif
    }
}
