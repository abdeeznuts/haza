import SwiftUI
import MapKit
import HazaCore

struct PlansScreen: View {
    @Environment(AppState.self) private var state
    @State private var plans: [PlannedDrive] = []
    @State private var crews: [Crew] = []
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Plans"); Headline("Upcoming", size: 28) }
                    Spacer()
                    Button("+ New") { creating = true }.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                }.padding(.top, 8)
                if plans.isEmpty {
                    Text("Post a drive: a title, when, where to meet, which crew. At start time it goes live, everyone going shows up on the map, and the plan gets its own walkie-talkie channel.")
                        .font(.system(size: 15)).foregroundStyle(HazaTheme.muted).padding(.vertical, 12)
                }
                ForEach(plans) { p in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Eyebrow(p.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())); Spacer(); Pill(text: p.status.capitalized, style: p.status == "live" ? .live : .plain) }
                            Text(p.title).font(HazaTheme.display(20))
                            if let m = p.meetName { Text("Meet at \(m)").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
                            if let c = crews.first(where: { $0.id == p.crewId }) { Text("\(c.emoji) \(c.name)").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
                            HStack(spacing: 8) {
                                Button("Going") { Task { try? await SupabaseService.shared.rsvp(plan: p.id, status: "going") } }
                                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(HazaTheme.bg)
                                Button("Maybe") { Task { try? await SupabaseService.shared.rsvp(plan: p.id, status: "maybe") } }
                                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                                if let m = p.meetName {
                                    Button("Directions") { openDirections(to: m) }
                                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                                }
                                if p.creatorId == state.profile?.id, p.status != "live" {
                                    Button("Go live") { Task { try? await SupabaseService.shared.goLive(plan: p.id); await load() } }
                                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).background(HazaTheme.live, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.black)
                                }
                            }.padding(.top, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .sheet(isPresented: $creating) { PlanEditor(crews: crews) { creating = false; Task { await load() } } }
        .task { await load() }
    }

    private func load() async {
        async let p = SupabaseService.shared.plans()
        async let c = SupabaseService.shared.crews()
        plans = (try? await p) ?? []; crews = (try? await c) ?? []
    }

    /// Turn-by-turn is Apple Maps' job (no navigation entitlement needed for that).
    private func openDirections(to name: String) {
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = name
        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first else { return }
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        }
    }
}

struct PlanEditor: View {
    let crews: [Crew]
    var onDone: () -> Void
    @State private var title = ""
    @State private var when = Date().addingTimeInterval(3600 * 3)
    @State private var meet = ""
    @State private var crew: Crew?
    @State private var notes = ""
    @State private var results: [MKMapItem] = []
    @State private var chosen: MKMapItem?

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Title (Canyon run · Westheimer loop)", text: $title); DatePicker("When", selection: $when) }
                Section("Meet point") {
                    TextField("Search a place", text: $meet).onChange(of: meet) { _, q in search(q) }
                    ForEach(results, id: \.self) { item in
                        Button { chosen = item; meet = item.name ?? meet; results = [] } label: { Text(item.name ?? "") }
                    }
                    if let c = chosen { Text("Meet at \(c.name ?? "")").foregroundStyle(HazaTheme.muted) }
                }
                Section("Crew") {
                    Picker("Crew", selection: $crew) { Text("Just friends").tag(Crew?.none); ForEach(crews) { Text("\($0.emoji) \($0.name)").tag(Crew?.some($0)) } }
                }
                Section { TextField("Notes", text: $notes, axis: .vertical) }
            }
            .navigationTitle("New plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
                ToolbarItem(placement: .confirmationAction) { Button("Post") { post() }.disabled(title.isEmpty) }
            }
        }
    }

    private func search(_ q: String) {
        guard q.count > 2 else { results = []; return }
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        if let loc = LocationService.shared.location { r.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000) }
        MKLocalSearch(request: r).start { response, _ in results = Array((response?.mapItems ?? []).prefix(5)) }
    }

    private func post() {
        let point = chosen.map { GeoPoint(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude) }
        Task {
            try? await SupabaseService.shared.createPlan(title: title, startsAt: when, crewID: crew?.id, meetName: chosen?.name ?? (meet.isEmpty ? nil : meet), meetPoint: point, notes: notes.isEmpty ? nil : notes)
            onDone()
        }
    }
}

struct CrewCreateView: View {
    var onSaved: () -> Void
    @State private var name = ""
    @State private var emoji = "🏁"
    @State private var code = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Start a crew") {
                TextField("Crew name", text: $name)
                TextField("Emoji", text: $emoji)
                Button("Create crew") { Task { _ = try? await SupabaseService.shared.createCrew(name: name, emoji: emoji); onSaved() } }.disabled(name.isEmpty)
            }
            Section("Or join one") {
                TextField("Crew code", text: $code).textInputAutocapitalization(.characters)
                Button("Join") {
                    Task {
                        do { _ = try await SupabaseService.shared.joinCrew(code: code); onSaved() } catch { self.error = error.localizedDescription }
                    }
                }.disabled(code.count < 6)
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(HazaTheme.alert) }
            }
            Text("A crew gets its own walkie-talkie channel and a place to post drives. Share your crew code to add people.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
        }
        .navigationTitle("Crew")
    }
}
