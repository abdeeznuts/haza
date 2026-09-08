// On-device home inference (mirrors the server's `infer_home`): where does this phone sleep?
// Only samples taken between 00:00 and 05:00 local time count. The densest 150 m cluster seen on
// at least `minNights` distinct nights becomes the suggestion; the app asks the user to confirm.
import Foundation

public struct HomeSample: Sendable {
    public var time: Date
    public var point: GeoPoint
    public init(time: Date, point: GeoPoint) { self.time = time; self.point = point }
}

public struct HomeSuggestion: Equatable, Sendable {
    public var point: GeoPoint
    public var nights: Int
    public var confidence: Double   // 0…1
}

public enum HomeInference {
    public static func overnight(_ sample: HomeSample, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: sample.time)
        return h >= 0 && h < 5
    }

    public static func suggest(from samples: [HomeSample], radius: Double = 150, minNights: Int = 3, calendar: Calendar = .current) -> HomeSuggestion? {
        let night = samples.filter { overnight($0, calendar: calendar) }
        guard !night.isEmpty else { return nil }
        let totalNights = Set(night.map { calendar.startOfDay(for: $0.time) }).count
        guard totalNights >= minNights else { return nil }

        // Greedy clustering: each sample joins the first centroid within `radius`, else starts one.
        var clusters: [(centroid: GeoPoint, members: [HomeSample])] = []
        for s in night {
            if let i = clusters.firstIndex(where: { Geo.distance($0.centroid, s.point) <= radius }) {
                clusters[i].members.append(s)
                let m = clusters[i].members
                clusters[i].centroid = GeoPoint(latitude: m.map(\.point.latitude).reduce(0, +) / Double(m.count),
                                                longitude: m.map(\.point.longitude).reduce(0, +) / Double(m.count))
            } else {
                clusters.append((s.point, [s]))
            }
        }
        let scored = clusters.map { c -> (GeoPoint, Int) in
            (c.centroid, Set(c.members.map { calendar.startOfDay(for: $0.time) }).count)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= minNights else { return nil }
        let confidence = min(1, Double(best.1) / Double(max(totalNights, 5)))
        return HomeSuggestion(point: best.0, nights: best.1, confidence: confidence)
    }
}
