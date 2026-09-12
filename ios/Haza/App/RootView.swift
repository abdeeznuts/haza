import SwiftUI
import Observation
import HazaCore

/// Where the app is pointed: the selected tab plus one optional sheet. Discover moments, inbox
/// banners and notification taps all route through here so a CTA can land anywhere in one hop.
@Observable @MainActor
final class Nav {
    enum Sheet: String, Identifiable { case profile, friends, places, recap, timeline; var id: String { rawValue } }
    var tab: MainTabs.Tab = .map
    var sheet: Sheet?

    func go(_ route: DiscoverEngine.Moment.Route) {
        switch route {
        case .none: break
        case .talk: tab = .talk
        case .drives: tab = .drives
        case .plans: tab = .plans
        case .radar: tab = .radar
        case .profile: sheet = .profile
        case .friends: sheet = .friends
        case .places: sheet = .places
        case .recap: sheet = .recap
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var nav = Nav()
    private let inbox = InboxService.shared
    private let discover = DiscoverEngine.shared
    private let location = LocationService.shared

    var body: some View {
        ZStack(alignment: .top) {
            HazaTheme.bg.ignoresSafeArea()
            switch state.route {
            case .welcome: WelcomeView()
            case .name: NameView()
            case .briefing: BriefingView()
            case .main: MainTabs()
            }
            if let item = inbox.latest, state.route == .main {
                InboxBanner(item: item)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: item.id) {
                        guard !item.urgent else { return }          // SOS stays until dismissed
                        try? await Task.sleep(for: .seconds(12)); if inbox.latest?.id == item.id { inbox.dismiss() }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: inbox.latest?.id)
        .preferredColorScheme(nil)
        // One feature intro at a time, from the bottom, only when it has just become relevant.
        .overlay(alignment: .bottom) {
            if let m = discover.current, state.route == .main {
                DiscoverCard(moment: m) { route in discover.dismiss(m); nav.go(route) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 64)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: discover.current?.id)
        // The drive that just ended, as a card — the moment people screenshot.
        .sheet(isPresented: Binding(get: { location.lastDriveSummary != nil && state.route == .main }, set: { if !$0 { location.clearSummary() } })) {
            if let s = location.lastDriveSummary {
                DriveCompleteCard(summary: s, metric: state.profile?.usesMetric ?? false) { location.clearSummary(); nav.tab = .drives }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
        .sheet(item: Binding(get: { nav.sheet }, set: { nav.sheet = $0 })) { sheet in
            switch sheet {
            case .profile: ProfileScreen()
            case .friends: NavigationStack { FriendsScreen() }
            case .places: NavigationStack { PlacesScreen() }
            case .recap: NavigationStack { RecapView() }
            case .timeline: NavigationStack { DayTimelineView() }
            }
        }
        // Crash check: full screen, impossible to miss, one big button.
        .fullScreenCover(isPresented: Binding(get: { location.possibleCrash != nil }, set: { if !$0 { location.dismissCrash() } })) {
            CrashCheckView(since: location.possibleCrash ?? .now) { location.dismissCrash() }
        }
        // The welcome screen shows sign-in errors inline; everywhere else a plain alert.
        .alert("Something went wrong", isPresented: Binding(get: { state.lastError != nil && state.route != .welcome }, set: { if !$0 { state.lastError = nil } })) {
            Button("OK") { state.lastError = nil }
        } message: { Text(state.lastError ?? "") }
        .environment(nav)   // outermost so overlays and every sheet see it
    }
}

/// "Ali wants to talk — Join": the in-app face of a ping, friend request, plan going live, place
/// arrival, drive start, convoy suggestion, check-in or SOS.
struct InboxBanner: View {
    let item: InboxService.Item
    @Environment(Nav.self) private var nav
    private let inbox = InboxService.shared

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 8, height: 8)
                .overlay { if item.urgent { Circle().stroke(HazaTheme.alert.opacity(0.5), lineWidth: 6).scaleEffect(1.6) } }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(item.body).font(.system(size: 12)).foregroundStyle(HazaTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            action
            Button { inbox.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(HazaTheme.muted).frame(width: 30, height: 30) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(item.urgent ? HazaTheme.alert : HazaTheme.hair, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 16).padding(.top, 6)
    }

    private var dot: Color {
        if item.urgent { return HazaTheme.alert }
        switch item.kind { case .ping, .driveStarted, .convoySuggest, .planLive: return HazaTheme.live; default: return HazaTheme.ink }
    }

    @ViewBuilder private var action: some View {
        if let c = item.channelID {
            capsule("Join") { Task { await join(c) } }
        } else if item.urgent || item.kind == .convoySuggest || item.kind == .driveStarted || item.point != nil {
            capsule(item.urgent ? "Map" : "See") { nav.tab = .map; inbox.dismiss() }
        } else if item.kind == .friendRequest {
            capsule("Open") { nav.sheet = .friends; inbox.dismiss() }
        } else if item.kind == .planLive {
            capsule("Plans") { nav.tab = .plans; inbox.dismiss() }
        }
    }

    private func capsule(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 30)
            .background(item.urgent ? HazaTheme.alert : HazaTheme.live, in: Capsule()).foregroundStyle(item.urgent ? .white : .black)
    }

    private func join(_ id: UUID) async {
        guard let channels = try? await SupabaseService.shared.channels(), let c = channels.first(where: { $0.id == id }) else { return }
        TalkService.shared.join(c, named: c.kind == "crew" ? "Crew" : c.kind == "plan" ? "Planned drive" : "Direct")
        inbox.dismiss()
    }
}

/// One feature, introduced the moment it becomes relevant. Never a tour.
struct DiscoverCard: View {
    let moment: DiscoverEngine.Moment
    var onAction: (DiscoverEngine.Moment.Route) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("New for you")
                Spacer()
                Button { onAction(.none) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(HazaTheme.muted).frame(width: 28, height: 28) }
            }
            Text(moment.title).font(HazaTheme.display(22)).foregroundStyle(HazaTheme.ink).fixedSize(horizontal: false, vertical: true)
            Text(moment.body).font(.system(size: 14)).foregroundStyle(HazaTheme.muted).fixedSize(horizontal: false, vertical: true)
            Button { Haptics.play(.tap); onAction(moment.route) } label: {
                Text(moment.cta).font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 44)
            }
            .background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).foregroundStyle(HazaTheme.bg)
        }
        .padding(18)
        .background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .padding(.horizontal, 16)
        .scaleEffect(appeared ? 1 : 0.94)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }; Haptics.play(.success) }
    }
}

/// "Are you OK?" — after a > 4 g impact. 45 s, then friends get an SOS with the location.
struct CrashCheckView: View {
    let since: Date
    var onOK: () -> Void
    @State private var now = Date()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Are you OK?").font(HazaTheme.display(40)).foregroundStyle(.white)
            Text("Haza felt a hard impact. If you don't answer, your friends get an SOS with your location in")
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 30)
            Text("\(max(0, 45 - Int(now.timeIntervalSince(since)))) s").font(HazaTheme.display(64)).monospacedDigit().foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
            Spacer()
            Button { Haptics.play(.success); onOK() } label: {
                Text("I'm OK").font(.system(size: 20, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 64)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).foregroundStyle(HazaTheme.alert)
            .padding(.horizontal, 24)
            Button { onOK(); Task { await sendSOSNow() } } label: { Text("Send SOS now").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9)) }
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HazaTheme.alert.ignoresSafeArea())
        .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); withAnimation { now = .now } } }
    }

    private func sendSOSNow() async {
        guard let loc = LocationService.shared.location else { return }
        _ = try? await SupabaseService.shared.sendSOS(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, note: "SOS (sent by hand after an impact)")
    }
}

struct MainTabs: View {
    @Environment(Nav.self) private var nav
    enum Tab: String, CaseIterable { case map = "Map", talk = "Talk", drives = "Drives", plans = "Plans", radar = "Radar" }

    var body: some View {
        @Bindable var nav = nav
        TabView(selection: $nav.tab) {
            MapScreen().tag(Tab.map).tabItem { Label("Map", systemImage: "map") }
            TalkScreen().tag(Tab.talk).tabItem { Label("Talk", systemImage: "mic") }
            DrivesScreen().tag(Tab.drives).tabItem { Label("Drives", systemImage: "car") }
            PlansScreen().tag(Tab.plans).tabItem { Label("Plans", systemImage: "calendar") }
            RadarScreen().tag(Tab.radar).tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
        }
        .tint(HazaTheme.ink)
        .onChange(of: nav.tab) { _, t in if t == .radar { DiscoverEngine.shared.note(.radarOpened) } }
    }
}
