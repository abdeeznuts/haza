import SwiftUI
import MapKit
import HazaCore

/// Home tab: full-bleed Apple map, friends as car chips with heading, live speed (if they share it),
/// battery and place ("At Work"), a bottom sheet with your speed, nearby friends and radar alerts.
/// Top row: profile, Ghost mode, Check-in, hold-for-SOS, Talk. Google Places data is deliberately
/// not drawn here (Google's terms forbid it on a non-Google map); place search uses MapKit.
struct MapScreen: View {
    @Environment(AppState.self) private var state
    @Environment(Nav.self) private var nav
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var radar: [RadarAlertRow] = []
    @State private var sheetExpanded = false
    @State private var checkingIn = false
    @State private var sosSent: Int?
    @State private var focusedID: UUID?
    private let location = LocationService.shared
    private let realtime = RealtimeService.shared
    private let talk = TalkService.shared
    private let places = PlacesService.shared

    private var metric: Bool { state.profile?.usesMetric ?? false }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: $focusedID) {
                UserAnnotation()
                ForEach(state.friends) { f in
                    Annotation(f.displayName, coordinate: coordinate(for: f)) {
                        FriendChip(friend: f, live: realtime.positions[f.userId], metric: metric)
                    }
                    .tag(f.userId)
                }
                ForEach(places.places) { p in
                    MapCircle(center: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng), radius: CLLocationDistance(p.radiusM))
                        .foregroundStyle(HazaTheme.ink.opacity(0.06)).stroke(HazaTheme.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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

            HStack(spacing: 8) {
                Button { nav.sheet = .profile } label: {
                    HStack(spacing: 8) {
                        Text(String(state.profile?.displayName.prefix(1) ?? "P")).font(.system(size: 12, weight: .bold)).frame(width: 24, height: 24).background(HazaTheme.ink, in: Circle()).foregroundStyle(HazaTheme.bg)
                        Text("\(state.friends.count)").font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 10).frame(height: 38).background(.ultraThinMaterial, in: Capsule())
                }
                GhostModeButton(profile: state.profile) { await state.loadSignedIn() }
                Button { checkingIn = true } label: { chip("Check in", "hand.wave") }.disabled(state.friends.isEmpty)
                SOSButton { n in sosSent = n }
                Spacer()
                Button { Task { await talk.setJoined(!talk.joined) } } label: {
                    HStack(spacing: 8) { Image(systemName: talk.joined ? "mic.fill" : "mic.slash"); Text(talk.joined ? "On" : "Talk") }
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 38)
                        .background(talk.joined ? AnyShapeStyle(HazaTheme.live) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                        .foregroundStyle(talk.joined ? .black : HazaTheme.ink)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { sheet }
        .sheet(isPresented: $checkingIn) { CheckInSheet(friends: state.friends).presentationDetents([.medium]) }
        .sheet(item: Binding(get: { state.friends.first { $0.userId == focusedID } }, set: { if $0 == nil { focusedID = nil } })) { f in
            FriendCard(friend: f, metric: metric).presentationDetents([.height(300)]).presentationDragIndicator(.visible)
        }
        .alert("SOS sent", isPresented: Binding(get: { sosSent != nil }, set: { if !$0 { sosSent = nil } })) {
            Button("OK") { sosSent = nil }
        } message: { Text("\(sosSent ?? 0) friends got your location with a loud alert. Call emergency services if you need them.") }
        .task { await refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await refresh()
            }
        }
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 6) { Image(systemName: symbol); Text(text) }
            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 11).frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule()).foregroundStyle(HazaTheme.ink)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(HazaTheme.hair).frame(width: 36, height: 4).frame(maxWidth: .infinity).padding(.top, 6)
                .contentShape(Rectangle()).onTapGesture { withAnimation(.spring(duration: 0.35)) { sheetExpanded.toggle() } }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Numeral(value: Units.formatSpeed(location.speedFilter.speed, metric: metric), size: 60)
                            .contentTransition(.numericText()).animation(.snappy(duration: 0.25), value: Int(location.speedFilter.speed))
                        Eyebrow(metric ? "km/h" : "mph")
                    }
                    if location.isDriving, let d = location.currentDrive {
                        Text("Driving · \(String(format: "%.1f", metric ? d.distance / 1000 : Units.miles(fromMeters: d.distance))) \(metric ? "km" : "mi") · \(Int(d.elapsed) / 60) min")
                            .font(.system(size: 12)).foregroundStyle(HazaTheme.live)
                    } else if let name = places.currentPlaceName() {
                        Text("At \(name)").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                    } else {
                        Text("Predicted \(Units.formatSpeed(location.speedFilter.predicted(after: 3), metric: metric)) in 3 s")
                            .font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Pill(text: radar.isEmpty ? "Radar quiet" : "\(radar.first!.band) near \(radar.first!.userId == state.profile?.id ? "you" : "a friend")", style: radar.isEmpty ? .plain : .alert)
                    Pill(text: "\(state.nearby.count) nearby", style: state.nearby.isEmpty ? .plain : .live)
                }
            }
            if sheetExpanded {
                if location.isDriving {
                    Button { location.stopDriveNow() } label: { Text("End drive now").font(.system(size: 13, weight: .semibold)).foregroundStyle(HazaTheme.muted) }
                }
                Eyebrow("Friends").padding(.top, 6)
                ForEach(state.friends) { f in
                    Button { focusedID = f.userId } label: {
                        Row(title: f.displayName, subtitle: f.statusLine(metric: metric) + " · " + f.updatedAt.formatted(.relative(presentation: .named))) {
                            Text(String(f.displayName.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).background(HazaTheme.surface2, in: Circle())
                        } trailing: { BatteryBadge(pct: f.batteryPct, charging: f.isCharging ?? false) }
                    }
                }
                if state.friends.isEmpty { Text("No friends yet. Share your invite code from your profile.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
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
    @State private var pulse = false

    private var driving: Bool { live?.driving ?? friend.isDriving }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if driving && !friend.atHome {
                    Circle().stroke(HazaTheme.live.opacity(0.6), lineWidth: 2).frame(width: 30, height: 30)
                        .scaleEffect(pulse ? 1.7 : 1).opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                }
                Circle().fill(.ultraThinMaterial).frame(width: 30, height: 30)
                    .overlay(Circle().stroke(driving ? HazaTheme.live : HazaTheme.ink, style: StrokeStyle(lineWidth: 1.5, dash: friend.atHome ? [3, 3] : [])))
                Text(String(friend.displayName.prefix(1))).font(.system(size: 12, weight: .bold))
                if let h = live?.heading ?? friend.headingDeg, !friend.atHome, driving {
                    Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(HazaTheme.live).offset(y: -20).rotationEffect(.degrees(h))
                }
            }
            HStack(spacing: 4) {
                Text(friend.displayName).font(.system(size: 11, weight: .semibold))
                if friend.atHome { Text("· home").font(.system(size: 11)).foregroundStyle(HazaTheme.muted) }
                else if let p = friend.placeName { Text("· \(p)").font(.system(size: 11)).foregroundStyle(HazaTheme.muted) }
                else if driving, let s = live?.speed ?? friend.speedMps { Text("· \(Units.formatSpeed(s, metric: metric))").font(HazaTheme.display(12)).monospacedDigit() }
                if let b = friend.batteryPct, b <= 20 { Image(systemName: "battery.25percent").font(.system(size: 10)).foregroundStyle(HazaTheme.alert) }
            }
            .padding(.horizontal, 7).padding(.vertical, 2).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .onAppear { pulse = true }
    }
}

/// Battery like Find My shows it: a glance, not a number to obsess over.
struct BatteryBadge: View {
    let pct: Int?
    let charging: Bool
    var body: some View {
        if let pct {
            HStack(spacing: 4) {
                Image(systemName: charging ? "battery.100percent.bolt" : pct <= 20 ? "battery.25percent" : pct <= 55 ? "battery.50percent" : "battery.100percent")
                    .foregroundStyle(pct <= 20 && !charging ? HazaTheme.alert : HazaTheme.muted)
                Text("\(pct)%").font(.system(size: 12)).monospacedDigit().foregroundStyle(HazaTheme.muted)
            }
        }
    }
}

/// Tap a friend on the map: where they are, how fast, battery, and the two things you do next.
struct FriendCard: View {
    let friend: FriendLive
    let metric: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(Nav.self) private var nav
    @State private var pinged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(String(friend.displayName.prefix(1))).font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44).background(HazaTheme.surface2, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName).font(HazaTheme.display(22))
                    Text(friend.statusLine(metric: metric) + " · " + friend.updatedAt.formatted(.relative(presentation: .named))).font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                }
                Spacer()
                BatteryBadge(pct: friend.batteryPct, charging: friend.isCharging ?? false)
            }
            HStack(spacing: 8) {
                Button { Task { try? await SupabaseService.shared.ping(friend.userId, channel: TalkService.shared.conversation?.id); pinged = true; Haptics.play(.tap) } } label: {
                    Label(pinged ? "Pinged" : "Ping to talk", systemImage: "mic").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 44)
                }.background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(HazaTheme.bg).disabled(pinged)
                Button { directions() } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 44)
                }.overlay(RoundedRectangle(cornerRadius: 12).stroke(HazaTheme.hair, lineWidth: 1)).disabled(friend.atHome)
            }
            Button { dismiss(); nav.sheet = .friends } label: { Text("Notify me when \(friend.displayName) drives or arrives somewhere →").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
            Spacer()
        }
        .padding(20).background(HazaTheme.bg)
    }

    private func directions() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: friend.lat, longitude: friend.lng)))
        item.name = friend.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
