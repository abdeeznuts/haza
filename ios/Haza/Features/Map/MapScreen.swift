import SwiftUI
import MapKit
import HazaCore

/// Home tab: full-bleed Apple map, friends as car chips with heading, live speed (if they share it),
/// a bottom sheet with nearby friends and radar alerts. Google Places data is deliberately not drawn
/// here (Google's terms forbid it on a non-Google map); place search uses MapKit.
struct MapScreen: View {
    @Environment(AppState.self) private var state
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var radar: [RadarAlertRow] = []
    @State private var sheetExpanded = false
    @State private var showProfile = false
    private let location = LocationService.shared
    private let realtime = RealtimeService.shared
    private let talk = TalkService.shared

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                UserAnnotation()
                ForEach(state.friends) { f in
                    Annotation(f.displayName, coordinate: coordinate(for: f)) { FriendChip(friend: f, live: realtime.positions[f.userId], metric: state.profile?.usesMetric ?? false) }
                }
                ForEach(radar) { a in
                    Annotation("\(a.band) · \(a.direction ?? "")", coordinate: CLLocationCoordinate2D(latitude: a.lat, longitude: a.lng)) {
                        Circle().fill(HazaTheme.alert).frame(width: 14, height: 14).shadow(color: HazaTheme.alert.opacity(0.5), radius: 8)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true))
            .mapControls { MapCompass(); MapUserLocationButton() }
            .ignoresSafeArea()

            HStack {
                Button { showProfile = true } label: {
                    HStack(spacing: 8) {
                        Text(String(state.profile?.displayName.prefix(1) ?? "P")).font(.system(size: 12, weight: .bold)).frame(width: 24, height: 24).background(HazaTheme.ink, in: Circle()).foregroundStyle(HazaTheme.bg)
                        Text("\(state.friends.count) friends").font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 10).frame(height: 38).background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button { Task { await talk.setJoined(!talk.joined) } } label: {
                    HStack(spacing: 8) { Image(systemName: talk.joined ? "mic.fill" : "mic.slash"); Text(talk.joined ? "Talk on" : "Talk off") }
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 38)
                        .background(talk.joined ? AnyShapeStyle(HazaTheme.live) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                        .foregroundStyle(talk.joined ? .black : HazaTheme.ink)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { sheet }
        .sheet(isPresented: $showProfile) { ProfileScreen() }
        .task { await refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await refresh()
            }
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(HazaTheme.hair).frame(width: 36, height: 4).frame(maxWidth: .infinity).padding(.top, 6)
                .contentShape(Rectangle()).onTapGesture { withAnimation(.spring(duration: 0.35)) { sheetExpanded.toggle() } }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Numeral(value: Units.formatSpeed(location.speedFilter.speed, metric: state.profile?.usesMetric ?? false), size: 60)
                        Eyebrow(state.profile?.usesMetric == true ? "km/h" : "mph")
                    }
                    Text("Predicted \(Units.formatSpeed(location.speedFilter.predicted(after: 3), metric: state.profile?.usesMetric ?? false)) in 3 s")
                        .font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Pill(text: radar.isEmpty ? "Radar quiet" : "\(radar.first!.band) near \(radar.first!.userId == state.profile?.id ? "you" : "a friend")", style: radar.isEmpty ? .plain : .alert)
                    Pill(text: "\(state.nearby.count) nearby", style: .live)
                }
            }
            if sheetExpanded {
                Eyebrow("Nearby · tap to ping").padding(.top, 6)
                ForEach(state.nearby) { n in
                    Button { Task { try? await SupabaseService.shared.ping(n.userId, channel: talk.conversation?.id) } } label: {
                        Row(title: n.displayName, subtitle: "\(String(format: "%.1f", Units.miles(fromMeters: n.distanceM))) mi · \(n.isDriving ? "driving" : "parked")") {
                            Text(String(n.displayName.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).background(HazaTheme.surface2, in: Circle())
                        } trailing: { Pill(text: "Ping") }
                    }
                }
                if state.nearby.isEmpty { Text("No friends within 1.5 miles right now.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .background(HazaTheme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) { Rectangle().fill(HazaTheme.hair).frame(height: 1) }
    }

    private func coordinate(for f: FriendLive) -> CLLocationCoordinate2D {
        // Prefer the live broadcast when it's fresher than the DB row, unless they're inside their home bubble.
        if !f.atHome, let live = realtime.positions[f.userId], live.at > f.updatedAt { return CLLocationCoordinate2D(latitude: live.point.latitude, longitude: live.point.longitude) }
        return CLLocationCoordinate2D(latitude: f.lat, longitude: f.lng)
    }

    private func refresh() async {
        await state.refreshFriends()
        await realtime.followAll(state.friends.filter { !$0.atHome }.map(\.userId))
        if let loc = location.location {
            radar = (try? await SupabaseService.shared.radarAlertsNear(GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))) ?? []
            var d = SharedStore.drive
            d.radarSummary = radar.isEmpty ? "Radar quiet" : "\(radar.first!.band) ahead"
            if let n = state.nearby.first { d.nearestFriend = n.displayName; d.nearestFriendDistanceMiles = Units.miles(fromMeters: n.distanceM) }
            SharedStore.drive = d
        }
        WatchBridge.shared.sendNearby(state.nearby.map { ($0.userId, $0.displayName, $0.distanceM, $0.isDriving) })
    }
}

struct FriendChip: View {
    let friend: FriendLive
    let live: RealtimeService.FriendPosition?
    let metric: Bool
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 30, height: 30).overlay(Circle().stroke(HazaTheme.ink, style: StrokeStyle(lineWidth: 1.5, dash: friend.atHome ? [3, 3] : [])))
                Text(String(friend.displayName.prefix(1))).font(.system(size: 12, weight: .bold))
                if let h = live?.heading ?? friend.headingDeg, !friend.atHome {
                    Image(systemName: "triangle.fill").font(.system(size: 7)).offset(y: -20).rotationEffect(.degrees(h))
                }
            }
            HStack(spacing: 4) {
                Text(friend.displayName).font(.system(size: 11, weight: .semibold))
                if friend.atHome { Text("· home").font(.system(size: 11)).foregroundStyle(HazaTheme.muted) }
                else if let s = live?.speed ?? friend.speedMps { Text("· \(Units.formatSpeed(s, metric: metric))").font(HazaTheme.display(12)).monospacedDigit() }
            }
            .padding(.horizontal, 7).padding(.vertical, 2).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
