import Foundation
import Observation

/// Progressive disclosure. The app never explains everything at once: each feature introduces
/// itself the first time it becomes relevant, as one small card ("moment"), once. Anything not yet
/// seen waits in the Discover tray on the Profile tab. Triggers are counted locally; nothing is sent.
@Observable @MainActor
final class DiscoverEngine {
    static let shared = DiscoverEngine()

    enum Event: String { case appOpened, driveStarted, driveEnded, friendOnline, friendAdded, talkJoined, planCreated, placeAdded, radarOpened, recapSeen }

    struct Moment: Identifiable, Equatable {
        let id: String
        let title: String
        let body: String
        let cta: String
        let route: Route
        enum Route: Equatable { case none, talk, drives, plans, profile, friends, places, radar, recap }
    }

    /// The card to show right now (RootView presents it).
    private(set) var current: Moment?
    private(set) var counts: [String: Int] = [:]

    private let seenKey = "discover.seen", countsKey = "discover.counts"
    private var seen: Set<String>

    private init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        counts = (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
    }

    /// Everything, in the order it should be discovered.
    static let all: [Moment] = [
        Moment(id: "first_drive", title: "That drive recorded itself.", body: "No button. Every drive lands in Drives with the route, and you can replay it with the friends who were with you.", cta: "Replay it", route: .drives),
        Moment(id: "talk_intro", title: "A friend is on the road.", body: "Hold the Talk button and they hear you — on iPhone, Watch or CarPlay. Ping first if they're not listening.", cta: "Open Talk", route: .talk),
        Moment(id: "plans_intro", title: "Plan the next one.", body: "Post a drive with a meet point. When it goes live everyone's on one map with a channel of their own, and you see each other's ETA.", cta: "Post a drive", route: .plans),
        Moment(id: "places_intro", title: "Places tell your friends where you are.", body: "Add Work or the gym and friends see \"At Work\" instead of a dot — and can get a nudge when you arrive or leave.", cta: "Add a place", route: .places),
        Moment(id: "stats_intro", title: "Your driving, in numbers.", body: "0–60, peak G, hard brakes, quick launches — per drive and in your weekly recap. Only you see them.", cta: "See the recap", route: .recap),
        Moment(id: "radar_intro", title: "Got a radar detector?", body: "A Valentine One Gen2 pairs over Bluetooth and its alerts land on the map — yours and your crew's.", cta: "Pair it", route: .radar),
        Moment(id: "ghost_intro", title: "Need a minute off the map?", body: "Ghost mode hides you until you turn it off. Your home bubble is always on regardless.", cta: "Got it", route: .none),
    ]

    func note(_ event: Event) {
        counts[event.rawValue, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: countsKey)
        guard current == nil else { return }
        if let m = nextMoment(after: event) { current = m }
    }

    private func nextMoment(after event: Event) -> Moment? {
        func unseen(_ id: String) -> Moment? { seen.contains(id) ? nil : Self.all.first { $0.id == id } }
        switch event {
        case .driveEnded: return unseen("first_drive")
        case .friendOnline: return unseen("talk_intro")
        case .talkJoined: return counts["talkJoined", default: 0] >= 2 ? unseen("plans_intro") : nil
        case .driveStarted: return counts["driveStarted", default: 0] >= 3 ? unseen("stats_intro") : nil
        case .appOpened:
            let n = counts["appOpened", default: 0]
            if n == 4 { return unseen("places_intro") }
            if n == 8 { return unseen("ghost_intro") }
            if n == 12 { return unseen("radar_intro") }
            return nil
        default: return nil
        }
    }

    func dismiss(_ m: Moment) {
        seen.insert(m.id)
        UserDefaults.standard.set(Array(seen), forKey: seenKey)
        if current?.id == m.id { current = nil }
    }

    /// For the Discover tray: not yet seen, in order.
    var remaining: [Moment] { Self.all.filter { !seen.contains($0.id) } }
    func markSeen(_ id: String) { seen.insert(id); UserDefaults.standard.set(Array(seen), forKey: seenKey) }
}
