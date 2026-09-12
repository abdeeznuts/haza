import SwiftUI
import MapKit
import HazaCore

struct DrivesScreen: View {
    @Environment(AppState.self) private var state
    @Environment(Nav.self) private var nav
    @State private var drives: [Drive] = []
    @State private var vehicles: [Vehicle] = []
    @State private var selected: Drive?
    @State private var recap: SupabaseService.WeeklyRecap?

    private var monthDrives: [Drive] { drives.filter { Calendar.current.isDate($0.startedAt, equalTo: .now, toGranularity: .month) } }
    private var metric: Bool { state.profile?.usesMetric ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Drives"); Headline(Date.now.formatted(.dateTime.month(.wide)), size: 28) }
                    Spacer()
                    Button { nav.sheet = .timeline } label: {
                        HStack(spacing: 6) { Image(systemName: "clock.arrow.circlepath"); Text("Timeline") }.font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).frame(height: 34).overlay(Capsule().stroke(HazaTheme.hair, lineWidth: 1))
                    }
                }.padding(.top, 8)
                if let recap, recap.drives > 0 { RecapCard(recap: recap, metric: metric) }
                HStack(spacing: 10) {
                    Stat(value: String(Int(metric ? monthDrives.map(\.distanceM).reduce(0, +) / 1000 : Units.miles(fromMeters: monthDrives.map(\.distanceM).reduce(0, +)))), label: metric ? "km driven" : "miles driven")
                    Spacer()
                    Stat(value: String(monthDrives.map(\.durationS).reduce(0, +) / 3600) + " h", label: "behind wheel")
                    Spacer()
                    Stat(value: String(monthDrives.count), label: "drives")
                }.padding(.vertical, 8)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                if drives.isEmpty {
                    Text("Your first drive records itself. Just drive.").font(.system(size: 15)).foregroundStyle(HazaTheme.muted).padding(.vertical, 20)
                }
                ForEach(drives) { d in
                    Button { selected = d } label: {
                        Row(title: title(for: d), subtitle: subtitle(for: d)) { Glyph(text: "→") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .sheet(item: $selected) { d in DriveDetailView(drive: d, vehicle: vehicles.first { v in v.id == d.vehicleId }, metric: metric, isPro: state.pro.isPro || HazaBrand.everythingUnlocked) }
        .task {
            drives = (try? await SupabaseService.shared.drives()) ?? []
            vehicles = (try? await SupabaseService.shared.vehicles()) ?? []
            recap = try? await SupabaseService.shared.weeklyRecap()
        }
        .refreshable {
            drives = (try? await SupabaseService.shared.drives()) ?? []
            recap = try? await SupabaseService.shared.weeklyRecap()
        }
    }

    private func title(for d: Drive) -> String {
        vehicles.first { $0.id == d.vehicleId }?.nickname ?? d.startedAt.formatted(.dateTime.weekday(.wide).hour().minute())
    }
    private func subtitle(for d: Drive) -> String {
        let dist = metric ? "\(String(format: "%.1f", d.distanceM / 1000)) km" : "\(String(format: "%.1f", Units.miles(fromMeters: d.distanceM))) mi"
        return "\(d.startedAt.formatted(.dateTime.month(.abbreviated).day())) · \(dist) · \(d.durationS / 60) min"
    }
}

struct DriveDetailView: View {
    let drive: Drive
    let vehicle: Vehicle?
    let metric: Bool
    let isPro: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(drive.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())).padding(.top, 20)
                Headline(vehicle?.title ?? "Drive", size: 28)
                HStack(spacing: 10) {
                    Stat(value: metric ? String(format: "%.1f", drive.distanceM / 1000) : String(format: "%.1f", Units.miles(fromMeters: drive.distanceM)), label: metric ? "km" : "miles")
                    Spacer()
                    Stat(value: "\(drive.durationS / 3600):\(String(format: "%02d", (drive.durationS % 3600) / 60))", label: "time")
                    Spacer()
                    Stat(value: Units.formatSpeed(drive.avgSpeedMps ?? 0, metric: metric), label: metric ? "avg km/h" : "avg mph")
                }.padding(.vertical, 8)
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your top speed").font(.system(size: 15, weight: .semibold))
                                Text("Private. Never shared or ranked.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                            }
                            Spacer()
                            Text(Units.formatSpeed(drive.maxSpeedMps ?? 0, metric: metric)).font(HazaTheme.display(28)).monospacedDigit()
                        }
                        Rectangle().fill(HazaTheme.hair).frame(height: 1)
                        DriveStatsGrid(drive: drive)
                    }
                }
                Eyebrow("Playback").padding(.top, 8)
                if isPro {
                    RoutePlayback(drive: drive)
                } else {
                    Card {
                        Text("Route playback with the cars that were with you is part of Pro.")
                            .font(.system(size: 13)).foregroundStyle(HazaTheme.muted).frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .presentationDetents([.large])
    }
}

/// The drive on a map with a scrubber: your car moves along the route; friends who were driving at the
/// same time appear as their own (home-clipped) lines. Positions come from the stored simplified route,
/// so time along the scrubber is proportional to distance — good enough to relive a run.
struct RoutePlayback: View {
    let drive: Drive
    @State private var route: [GeoPoint] = []
    @State private var companions: [DriveCompanion] = []
    @State private var progress: Double = 1
    @State private var playing = false
    @State private var loaded = false
    @State private var camera: MapCameraPosition = .automatic

    private var coords: [CLLocationCoordinate2D] { route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                if coords.count >= 2 {
                    MapPolyline(coordinates: coords).stroke(HazaTheme.ink, lineWidth: 4)
                }
                ForEach(companions) { c in
                    let cc = c.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    if cc.count >= 2 {
                        MapPolyline(coordinates: cc).stroke(HazaTheme.muted, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                        Annotation(c.displayName, coordinate: cc[cc.count / 2]) {
                            Text(String(c.displayName.prefix(1))).font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22)
                                .background(HazaTheme.surface2, in: Circle()).overlay(Circle().stroke(HazaTheme.muted, lineWidth: 1))
                        }
                    }
                }
                if let first = coords.first {
                    Annotation("Start", coordinate: first) { Circle().fill(HazaTheme.live).frame(width: 10, height: 10) }
                }
                if let car = position(at: progress) {
                    Annotation("", coordinate: car) {
                        Image(systemName: "car.fill").font(.system(size: 13, weight: .bold)).padding(6)
                            .background(HazaTheme.ink, in: Circle()).foregroundStyle(HazaTheme.bg)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
            .overlay {
                if loaded && route.count < 2 {
                    Text("No route was saved for this drive.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                        .padding(10).background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            HStack(spacing: 12) {
                Button { toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
                        .background(HazaTheme.ink, in: Circle()).foregroundStyle(HazaTheme.bg)
                }.disabled(route.count < 2)
                Slider(value: $progress, in: 0...1).tint(HazaTheme.ink)
                Text(elapsedLabel).font(HazaTheme.display(15)).monospacedDigit().frame(width: 58, alignment: .trailing)
            }
            if !companions.isEmpty {
                Text("With you: " + companions.map(\.displayName).joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
            }
        }
        .task {
            route = (try? await SupabaseService.shared.driveRoute(drive.id)) ?? []
            companions = (try? await SupabaseService.shared.driveCompanions(drive.id)) ?? []
            loaded = true
            frameEverything()
        }
    }

    /// Fit my route and the companions' routes with a little breathing room.
    private func frameEverything() {
        let all = coords + companions.flatMap { $0.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
        guard !all.isEmpty else { return }
        var rect = MKMapRect.null
        for c in all { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1))) }
        let padded = rect.insetBy(dx: -max(rect.size.width * 0.2, 400), dy: -max(rect.size.height * 0.2, 400))
        camera = .rect(padded)
    }

    private var elapsedLabel: String {
        let s = Int(Double(drive.durationS) * progress)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Position along the polyline at a distance fraction (0…1).
    private func position(at fraction: Double) -> CLLocationCoordinate2D? {
        guard route.count >= 2 else { return nil }
        var legs: [Double] = []
        for i in 1..<route.count { legs.append(Geo.distance(route[i - 1], route[i])) }
        let total = legs.reduce(0, +)
        guard total > 0 else { return coords.first }
        var target = max(0, min(1, fraction)) * total
        for (i, leg) in legs.enumerated() {
            if target <= leg || i == legs.count - 1 {
                let t = leg > 0 ? min(1, target / leg) : 0
                let a = route[i], b = route[i + 1]
                return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
            }
            target -= leg
        }
        return coords.last
    }

    private func toggle() {
        playing.toggle()
        guard playing else { return }
        if progress >= 1 { progress = 0 }
        Task { @MainActor in
            // ~20 s for the whole drive regardless of length.
            while playing, progress < 1 {
                try? await Task.sleep(for: .milliseconds(50))
                progress = min(1, progress + 0.0025)
            }
            playing = false
        }
    }
}
