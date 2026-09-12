import SwiftUI
import MapKit
import HazaCore

/// Saved places: "At Work" instead of a dot, and arrive/leave nudges for the friends who asked.
/// Detection costs nothing extra — it rides on fixes the engine already gets.
struct PlacesScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    private let places = PlacesService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Places"); Headline("Where you usually are", size: 28) }
                    Spacer()
                    Button("+ Add") { adding = true }.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                }.padding(.top, 8)
                Text("Friends see “At Work” instead of a dot while you're inside a place. Home is separate — it's the privacy bubble in your profile.")
                    .font(.system(size: 14)).foregroundStyle(HazaTheme.muted)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                if places.places.isEmpty {
                    Text("No places yet. Work, school, the gym, a friend's house — anywhere you'd rather friends saw a name.")
                        .font(.system(size: 14)).foregroundStyle(HazaTheme.muted).padding(.vertical, 12)
                }
                ForEach(places.places) { p in
                    Row(title: p.name, subtitle: "\(PlaceKind.label(p.kind)) · \(p.radiusM) m · \(p.shareWith == "friends" ? "friends get arrive/leave nudges" : "only you")") {
                        Glyph(text: PlaceKind.glyph(p.kind))
                    } trailing: {
                        Menu { Button("Delete", role: .destructive) { Task { await places.delete(p) } } } label: {
                            Image(systemName: "ellipsis").frame(width: 32, height: 32).foregroundStyle(HazaTheme.muted)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $adding) { NavigationStack { PlaceEditor { adding = false } } }
        .task { await places.load() }
    }
}

struct PlaceKind: Identifiable {
    let key: String, label: String, glyph: String
    var id: String { key }
    static let all: [PlaceKind] = [
        PlaceKind(key: "work", label: "Work", glyph: "W"), PlaceKind(key: "school", label: "School", glyph: "S"), PlaceKind(key: "gym", label: "Gym", glyph: "G"),
        PlaceKind(key: "friend", label: "Friend's", glyph: "F"), PlaceKind(key: "other", label: "Place", glyph: "•"),
    ]
    static func label(_ k: String) -> String { all.first { $0.key == k }?.label ?? "Place" }
    static func glyph(_ k: String) -> String { all.first { $0.key == k }?.glyph ?? "•" }
}

/// Drag the map so the crosshair sits on the place, name it, pick how big it is.
struct PlaceEditor: View {
    var onDone: () -> Void
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var kind = "work"
    @State private var radius = 150
    @State private var share = true
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("New place").padding(.top, 8)
                Headline("Put the crosshair on it.", size: 26)
                HStack(spacing: 8) {
                    TextField("Search a place or address", text: $query).onChange(of: query) { _, q in search(q) }
                        .padding(.horizontal, 12).frame(height: 40).overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        results = []; query = item.name ?? query
                        if name.isEmpty { name = item.name ?? "" }
                        position = .region(MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 500, longitudinalMeters: 500))
                    } label: { Row(title: item.name ?? "", subtitle: item.placemark.title) { Glyph(text: "◎") } trailing: { EmptyView() } }
                }
                Map(position: $position) {
                    if let c = center { MapCircle(center: c, radius: CLLocationDistance(radius)).foregroundStyle(HazaTheme.ink.opacity(0.08)).stroke(HazaTheme.ink.opacity(0.5), lineWidth: 1) }
                }
                .onMapCameraChange { ctx in center = ctx.camera.centerCoordinate }
                .overlay { Image(systemName: "plus").font(.system(size: 22, weight: .thin)).foregroundStyle(HazaTheme.ink) }
                .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
                TextField("Name (Work, Gym, Ali's)", text: $name).padding(.horizontal, 12).frame(height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlaceKind.all) { k in
                            Button { withAnimation(.snappy) { kind = k.key; if name.isEmpty || PlaceKind.all.contains(where: { $0.label == name }) { name = k.label } } } label: {
                                Text(k.label).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
                                    .background(kind == k.key ? HazaTheme.ink : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(kind == k.key ? .clear : HazaTheme.hair, lineWidth: 1))
                                    .foregroundStyle(kind == k.key ? HazaTheme.bg : HazaTheme.ink)
                            }
                        }
                    }
                }
                HStack {
                    Text("Size").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Picker("Size", selection: $radius) { Text("Small").tag(100); Text("Normal").tag(150); Text("Big").tag(300); Text("Campus").tag(600) }.pickerStyle(.segmented).frame(maxWidth: 260)
                }
                Toggle(isOn: $share) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Friends can see it").font(.system(size: 15, weight: .medium))
                        Text("They see “At \(name.isEmpty ? "Work" : name)” and can ask for a nudge when you arrive or leave.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                    }
                }.tint(HazaTheme.live)
                PrimaryButton(title: saving ? "Saving…" : "Save place") { save() }.disabled(name.isEmpty || center == nil || saving).padding(.top, 4)
            }
            .padding(20)
        }
        .background(HazaTheme.bg)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) } }
    }

    private func search(_ q: String) {
        guard q.count > 2 else { results = []; return }
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        if let loc = LocationService.shared.location { r.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000) }
        MKLocalSearch(request: r).start { response, _ in
            let items = Array((response?.mapItems ?? []).prefix(4))
            Task { @MainActor in results = items }
        }
    }

    private func save() {
        guard let c = center else { return }
        saving = true
        Task {
            try? await PlacesService.shared.add(name: name.trimmingCharacters(in: .whitespaces), kind: kind, point: GeoPoint(latitude: c.latitude, longitude: c.longitude), radius: radius, shareWithFriends: share)
            Haptics.play(.success)
            onDone()
        }
    }
}
