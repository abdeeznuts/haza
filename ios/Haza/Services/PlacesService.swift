import Foundation
import Observation
import HazaCore

/// Saved places (Work, School, the gym…) and arrive/leave detection, done without GPS: every
/// location the engine already has (significant-change fixes, visits, drive points) is checked
/// against the user's places; a state change becomes a `place_events` row, which the server turns
/// into "Ali arrived at Work" for friends who asked for it. Home stays the privacy bubble in `profiles`.
@Observable @MainActor
final class PlacesService {
    static let shared = PlacesService()

    private(set) var places: [Place] = []
    private var inside: Set<UUID> = []
    private var lastEventAt: [UUID: Date] = [:]
    private var loaded = false

    func load() async {
        places = (try? await SupabaseService.shared.myPlaces()) ?? []
        loaded = true
        // Restore "inside" state from the last known position, silently (no events).
        if let loc = LocationService.shared.location {
            let p = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            inside = Set(places.filter { Geo.distance(p, $0.point) <= Double($0.radiusM) }.map(\.id))
        }
    }

    func add(name: String, kind: String, point: GeoPoint, radius: Int, shareWithFriends: Bool) async throws {
        try await SupabaseService.shared.addPlace(name: name, kind: kind, point: point, radius: radius, shareWithFriends: shareWithFriends)
        await load()
        DiscoverEngine.shared.note(.placeAdded)
    }

    func delete(_ place: Place) async {
        try? await SupabaseService.shared.deletePlace(place.id)
        await load()
    }

    /// Called for every fix the location engine gets. Hysteresis: leave only once we're 40 m past the edge.
    func check(_ p: GeoPoint) async {
        if !loaded { await load() }
        for place in places {
            let d = Geo.distance(p, place.point)
            let r = Double(place.radiusM)
            if !inside.contains(place.id), d <= r { inside.insert(place.id); await emit(place, "arrive") }
            else if inside.contains(place.id), d > r + 40 { inside.remove(place.id); await emit(place, "leave") }
        }
    }

    func noteArrival(at p: GeoPoint) async { await check(p) }
    func noteDeparture(at p: GeoPoint) async {
        if !loaded { await load() }
        for place in places where inside.contains(place.id) && Geo.distance(p, place.point) <= Double(place.radiusM) + 200 {
            inside.remove(place.id); await emit(place, "leave")
        }
    }

    private func emit(_ place: Place, _ event: String) async {
        // Don't flap: one event per place per 3 minutes.
        if let t = lastEventAt[place.id], Date.now.timeIntervalSince(t) < 180 { return }
        lastEventAt[place.id] = .now
        try? await SupabaseService.shared.placeEvent(place.id, event: event)
    }

    /// Label for the map ("At Work") — nil when at none of them.
    func currentPlaceName() -> String? {
        places.first { inside.contains($0.id) }?.name
    }
}
