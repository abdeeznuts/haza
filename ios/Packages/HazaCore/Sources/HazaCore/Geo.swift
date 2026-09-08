import Foundation

public struct GeoPoint: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public enum Geo {
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres.
    public static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la = a.latitude * .pi / 180, lb = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from a to b in degrees (0 = north, clockwise).
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let la = a.latitude * .pi / 180, lb = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lb)
        let x = cos(la) * sin(lb) - sin(la) * cos(lb) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Applies the home privacy bubble: inside `radius` of home the shared point becomes home itself.
    public static func privacySnapped(_ p: GeoPoint, home: GeoPoint?, radius: Double = 150) -> (point: GeoPoint, atHome: Bool) {
        guard let home, distance(p, home) <= radius else { return (p, false) }
        return (home, true)
    }

    /// Douglas–Peucker simplification (tolerance in metres) for storing drive routes.
    public static func simplify(_ points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (s, e) = stack.popLast() {
            var maxD = 0.0, idx = -1
            for i in (s + 1)..<e {
                let d = perpendicularDistance(points[i], points[s], points[e])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > tolerance, idx > 0 { keep[idx] = true; stack.append((s, idx)); stack.append((idx, e)) }
        }
        return points.enumerated().filter { keep[$0.offset] }.map(\.element)
    }

    private static func perpendicularDistance(_ p: GeoPoint, _ a: GeoPoint, _ b: GeoPoint) -> Double {
        // local equirectangular projection around a
        let kx = cos(a.latitude * .pi / 180) * 111_320.0, ky = 110_540.0
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * kx, by = (b.latitude - a.latitude) * ky
        let px = (p.longitude - a.longitude) * kx, py = (p.latitude - a.latitude) * ky
        let len2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
        if len2 == 0 { return sqrt(px * px + py * py) }
        let t = max(0, min(1, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2))
        let cx = ax + t * (bx - ax), cy = ay + t * (by - ay)
        return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
    }
}
