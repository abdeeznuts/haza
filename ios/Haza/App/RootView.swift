import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    private let inbox = InboxService.shared

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
                    .task(id: item.id) { try? await Task.sleep(for: .seconds(12)); if inbox.latest?.id == item.id { inbox.dismiss() } }
            }
        }
        .animation(.spring(duration: 0.35), value: inbox.latest?.id)
        .preferredColorScheme(nil)
        // The welcome screen shows sign-in errors inline; everywhere else a plain alert.
        .alert("Something went wrong", isPresented: Binding(get: { state.lastError != nil && state.route != .welcome }, set: { if !$0 { state.lastError = nil } })) {
            Button("OK") { state.lastError = nil }
        } message: { Text(state.lastError ?? "") }
    }
}

/// "Ali wants to talk — Join": the in-app face of a ping, friend request or plan going live.
struct InboxBanner: View {
    let item: InboxService.Item
    private let inbox = InboxService.shared

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(item.kind == .ping ? HazaTheme.live : HazaTheme.ink).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(item.body).font(.system(size: 12)).foregroundStyle(HazaTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let c = item.channelID {
                Button("Join") { Task { await join(c) } }
                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 30)
                    .background(HazaTheme.live, in: Capsule()).foregroundStyle(.black)
            }
            Button { inbox.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(HazaTheme.muted).frame(width: 30, height: 30) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 16).padding(.top, 6)
    }

    private func join(_ id: UUID) async {
        guard let channels = try? await SupabaseService.shared.channels(), let c = channels.first(where: { $0.id == id }) else { return }
        TalkService.shared.join(c, named: c.kind == "crew" ? "Crew" : c.kind == "plan" ? "Planned drive" : "Direct")
        inbox.dismiss()
    }
}

struct MainTabs: View {
    @State private var tab: Tab = .map
    enum Tab: String, CaseIterable { case map = "Map", talk = "Talk", drives = "Drives", plans = "Plans", radar = "Radar" }

    var body: some View {
        TabView(selection: $tab) {
            MapScreen().tag(Tab.map).tabItem { Label("Map", systemImage: "map") }
            TalkScreen().tag(Tab.talk).tabItem { Label("Talk", systemImage: "mic") }
            DrivesScreen().tag(Tab.drives).tabItem { Label("Drives", systemImage: "car") }
            PlansScreen().tag(Tab.plans).tabItem { Label("Plans", systemImage: "calendar") }
            RadarScreen().tag(Tab.radar).tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
        }
        .tint(HazaTheme.ink)
    }
}
