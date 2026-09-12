import SwiftUI
import MapKit
import StoreKit
import HazaCore

struct ProfileScreen: View {
    @Environment(AppState.self) private var state
    @Environment(Nav.self) private var nav
    @Environment(\.dismiss) private var dismiss
    private let discover = DiscoverEngine.shared
    @State private var confirmDelete = false
    @State private var editingName = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Text(String(state.profile?.displayName.prefix(1) ?? "P")).font(.system(size: 18, weight: .semibold)).frame(width: 52, height: 52).background(HazaTheme.ink, in: Circle()).foregroundStyle(HazaTheme.bg)
                        VStack(alignment: .leading, spacing: 2) {
                            Button { newName = state.profile?.displayName ?? ""; editingName = true } label: {
                                HStack(spacing: 6) { Headline(state.profile?.displayName ?? "You", size: 26); Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
                            }
                            Text(HazaBrand.everythingUnlocked ? (state.profile?.handle.map { "@\($0)" } ?? "Everything unlocked")
                                 : (state.pro.isPro ? "Pro" + (state.pro.proUntil.map { " · until \($0.formatted(.dateTime.month().day()))" } ?? "") : "Free plan"))
                                .font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                        }
                    }.padding(.top, 8)

                    ReferralCard()
                    if !discover.remaining.isEmpty {
                        DiscoverTray { route in
                            dismiss()
                            Task { try? await Task.sleep(for: .milliseconds(450)); nav.go(route) }   // let this sheet finish closing first
                        }
                    }
                    if !HazaBrand.everythingUnlocked {
                        NavigationLink { PaywallView() } label: { Row(title: state.pro.isPro ? "Manage Pro" : "Get Pro", subtitle: "Unlimited history and playback, unlimited crews, all cars, radar sharing") { Glyph(text: "★") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    }
                    NavigationLink { FriendsScreen() } label: { Row(title: "Friends", subtitle: "Requests, add by @handle, your handle") { Glyph(text: "F") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { GarageScreen() } label: { Row(title: "Garage", subtitle: "Your cars") { Glyph(text: "G") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { PlacesScreen() } label: { Row(title: "Places", subtitle: "Work, school, the gym — “At Work” instead of a dot") { Glyph(text: "◎") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { DayTimelineView() } label: { Row(title: "Timeline", subtitle: "Where you were, day by day. Only you.") { Glyph(text: "◷") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { RecapView() } label: { Row(title: "Weekly recap", subtitle: "Miles, best 0–60, peak g, hard brakes") { Glyph(text: "Σ") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { BriefingView(embedded: true) } label: { Row(title: "Briefing", subtitle: "\(state.briefing.count) things you could still set up") { Glyph(text: "\(state.briefing.count)") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }

                    Eyebrow("Where Haza lives").padding(.top, 10)
                    Rectangle().fill(HazaTheme.hair).frame(height: 1)
                    NavigationLink { SurfaceGuide(kind: .carplay) { UserDefaults.standard.set(true, forKey: "briefing.carplay.done") } } label: { Row(title: "CarPlay Dashboard widget", subtitle: "Talk on/off, speed now and predicted, next meet") { Glyph(text: "▭") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { SurfaceGuide(kind: .watch) { UserDefaults.standard.set(true, forKey: "briefing.watch.done") } } label: { Row(title: "Apple Watch", subtitle: "Hold to talk, nearby friends, a tap when someone speaks") { Glyph(text: "◯") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }
                    NavigationLink { SurfaceGuide(kind: .control) { UserDefaults.standard.set(true, forKey: "briefing.control.done") } } label: { Row(title: "Control Center and Lock Screen", subtitle: "Talk control, drive Live Activity, Dynamic Island") { Glyph(text: "◐") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) } }

                    Eyebrow("Privacy").padding(.top, 10)
                    Rectangle().fill(HazaTheme.hair).frame(height: 1)
                    NavigationLink { HomeSetupView(onSaved: {}) } label: { Row(title: "Home", subtitle: homeSubtitle) { Glyph(text: "⌂") } trailing: { Pill(text: state.profile?.homeSource == nil ? "Not set" : "150 m bubble", style: state.profile?.homeSource == nil ? .plain : .live) } }
                    Toggle(isOn: Binding(get: { state.profile?.shareSpeed ?? true }, set: { v in Task { try? await SupabaseService.shared.updateProfile(["share_speed": .bool(v)]); await state.loadSignedIn() } })) {
                        VStack(alignment: .leading, spacing: 2) { Text("Share my speed").font(.system(size: 16, weight: .medium)); Text("Friends see it as a readout, never ranked.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
                    }.tint(HazaTheme.live).padding(.vertical, 8)
                    Picker("Units", selection: Binding(get: { state.profile?.units ?? "mph" }, set: { v in Task { try? await SupabaseService.shared.updateProfile(["units": .string(v)]); await state.loadSignedIn() } })) {
                        Text("mph").tag("mph"); Text("km/h").tag("kmh")
                    }.pickerStyle(.segmented)

                    Eyebrow("Account").padding(.top, 10)
                    Rectangle().fill(HazaTheme.hair).frame(height: 1)
                    Link(destination: HazaBrand.privacyURL) { Row(title: "Privacy policy", subtitle: nil) { Glyph(text: "P") } trailing: { Image(systemName: "arrow.up.right").foregroundStyle(HazaTheme.muted) } }
                    Button { Task { await state.signOut() } } label: { Row(title: "Sign out", subtitle: nil) { Glyph(text: "→") } trailing: { EmptyView() } }
                    Button { confirmDelete = true } label: { Row(title: "Delete account", subtitle: "Removes every drive, friend and setting immediately.") { Glyph(text: "×").foregroundStyle(HazaTheme.alert) } trailing: { EmptyView() } }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
            .background(HazaTheme.bg)
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await state.deleteAccount() } }
            } message: { Text("This can't be undone. Subscriptions are managed separately in your Apple ID settings.") }
            .alert("Your name", isPresented: $editingName) {
                TextField("Name", text: $newName)
                Button("Save") { Task { await state.confirmName(newName) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Shown on your car chip and in the walkie-talkie.") }
        }
    }

    private var homeSubtitle: String {
        switch state.profile?.homeSource {
        case "manual": return "Set by you · friends see the bubble, not your street"
        case "inferred": return "Learned from where your phone sleeps · confirm it"
        case "contacts": return "From your contact card"
        default: return "Set it, or let Haza learn it over a few nights"
        }
    }
}

/// Features not yet introduced, one line each. The moment cards show themselves in context;
/// this is the catalog for the curious — a quiet list, never a tour.
struct DiscoverTray: View {
    var onOpen: (DiscoverEngine.Moment.Route) -> Void
    private let discover = DiscoverEngine.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow("Discover"); Spacer(); Text("\(discover.remaining.count) left").font(.system(size: 12)).foregroundStyle(HazaTheme.muted) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(discover.remaining) { m in
                        Button { discover.markSeen(m.id); onOpen(m.route) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(m.title).font(HazaTheme.display(17)).foregroundStyle(HazaTheme.ink).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text(m.cta + " →").font(.system(size: 13, weight: .semibold)).foregroundStyle(HazaTheme.muted)
                            }
                            .padding(14).frame(width: 190, height: 120, alignment: .topLeading)
                            .background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

struct ReferralCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Eyebrow("Your invite"); Spacer(); Pill(text: "\(state.pro.referrals) joined") }
                HStack {
                    Text(Referral.display(code))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 4).background(HazaTheme.surface2, in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button { UIPasteboard.general.string = Referral.display(code) } label: {
                        Text("Copy").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 12).frame(height: 36).overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                    }
                    ShareLink(item: Referral.link(for: code), message: Text("Join me on \(HazaBrand.name) — we'll see each other on the map and talk like walkie-talkies. My code: \(Referral.display(code)) (paste it on the welcome screen).")) {
                        Text("Share").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(HazaTheme.bg)
                    }
                }
                if HazaBrand.everythingUnlocked {
                    Text("Friends who join with your code are connected to you automatically — no request to accept.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                } else {
                    Text(Referral.rewardSummary(referrals: state.pro.referrals)).font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(HazaTheme.surface2)
                            Capsule().fill(HazaTheme.ink).frame(width: g.size.width * min(1, Double(state.pro.referrals) / 3))
                        }
                    }.frame(height: 6)
                    Text("3 friends = 90 days. It stacks.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                }
            }
        }
    }
    private var code: String { state.profile?.inviteCode ?? "" }
}

struct ReferralView: View { var body: some View { ScrollView { ReferralCard().padding(20) }.background(HazaTheme.bg) } }

struct InviteView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Headline("Haza is empty alone.", size: 28)
                Text(HazaBrand.everythingUnlocked
                     ? "Send your code. When a friend joins with it you're connected automatically — no request to accept."
                     : "Send your link. When a friend joins with it you're connected automatically — no request to accept — and you both get Pro time after their first drive.")
                    .font(.system(size: 15)).foregroundStyle(HazaTheme.muted)
                ReferralCard()
            }.padding(20)
        }.background(HazaTheme.bg)
    }
}

struct PaywallView: View {
    @Environment(AppState.self) private var state
    private let store = StoreService.shared
    @State private var pick: Product?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Pro").padding(.top, 8)
                Headline("Every drive, every crew, every car.", size: 30)
                ForEach(store.products, id: \.id) { p in
                    Button { pick = p } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.id == HazaBrand.Products.yearly ? "Yearly" : "Monthly").font(.system(size: 16, weight: .semibold))
                                Text(p.subscription?.introductoryOffer.map { "\($0.period.value)-\($0.period.unit) free trial" } ?? (p.id == HazaBrand.Products.yearly ? "Best value" : "Cancel anytime")).font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                            }
                            Spacer()
                            Text(p.displayPrice).font(HazaTheme.display(22))
                        }
                        .padding(16).overlay(RoundedRectangle(cornerRadius: 14).stroke((pick ?? store.yearly)?.id == p.id ? HazaTheme.ink : HazaTheme.hair, lineWidth: 1))
                    }.foregroundStyle(HazaTheme.ink)
                }
                if store.products.isEmpty { Text(store.message ?? "Loading prices from the App Store…").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
                PrimaryButton(title: state.pro.isPro ? "You're Pro" : "Continue") {
                    if let p = pick ?? store.yearly { Task { await store.purchase(p); await state.refreshPro() } }
                }.disabled(store.busy || state.pro.isPro)
                Button("Restore purchases") { Task { await store.restore(); await state.refreshPro() } }.font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity)
                Text("Unlimited history and route playback, unlimited crews and plans, all cars, radar alert sharing, map themes. Billed through Apple; manage or cancel in Settings › Apple ID › Subscriptions. Referral rewards add free Pro time on top.")
                    .font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                HStack { Link("Privacy", destination: HazaBrand.privacyURL); Text("·"); Link("Terms", destination: HazaBrand.termsURL) }.font(.system(size: 12)).foregroundStyle(HazaTheme.muted).frame(maxWidth: .infinity)
            }.padding(20)
        }
        .background(HazaTheme.bg)
        .task { if store.products.isEmpty { await store.start() } }
    }
}

/// Manual pin, contact-card address, or the inferred suggestion — the user always confirms.
struct HomeSetupView: View {
    var onSaved: () -> Void
    @Environment(AppState.self) private var state
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var suggestion: HomeSuggestion?
    @State private var address = ""
    private let home = HomeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Home").padding(.top, 8)
            Headline("Where should the bubble be?", size: 26)
            Text("Inside 150 m of home, friends see the pin, never your exact spot. Drag the map so the crosshair sits on your house.").font(.system(size: 14)).foregroundStyle(HazaTheme.muted)
            Map(position: $position) {
                if let s = suggestion { Marker("Learned", coordinate: CLLocationCoordinate2D(latitude: s.point.latitude, longitude: s.point.longitude)) }
            }
            .onMapCameraChange { ctx in center = ctx.camera.centerCoordinate }
            .overlay { Image(systemName: "plus").font(.system(size: 22, weight: .thin)).foregroundStyle(HazaTheme.ink) }
            .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
            if let s = suggestion {
                Card { HStack { VStack(alignment: .leading, spacing: 2) { Text("Haza learned a likely home").font(.system(size: 15, weight: .semibold)); Text("\(s.nights) nights · \(Int(s.confidence * 100))% sure").font(.system(size: 12)).foregroundStyle(HazaTheme.muted) }; Spacer(); Button("Use it") { Task { await home.confirm(s.point, source: "inferred"); await state.loadSignedIn(); onSaved() } }.font(.system(size: 14, weight: .semibold)) } }
            }
            HStack(spacing: 8) {
                TextField("Or type your address", text: $address).textContentType(.fullStreetAddress).padding(.horizontal, 12).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                Button("Find") { geocode(address) }.font(.system(size: 14, weight: .semibold)).disabled(address.count < 5)
            }
            PrimaryButton(title: "Set home here") {
                guard let c = center else { return }
                Task { await home.confirm(GeoPoint(latitude: c.latitude, longitude: c.longitude), source: "manual"); await state.loadSignedIn(); onSaved() }
            }
        }
        .padding(20).background(HazaTheme.bg)
        .task { await home.refreshSuggestion(); suggestion = home.suggestion }
    }

    private func geocode(_ address: String) {
        CLGeocoder().geocodeAddressString(address) { marks, _ in
            guard let c = marks?.first?.location?.coordinate else { return }
            Task { @MainActor in position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 400, longitudinalMeters: 400)) }
        }
    }
}
