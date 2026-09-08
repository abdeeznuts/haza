import SwiftUI
import HazaCore

struct TalkScreen: View {
    @Environment(AppState.self) private var state
    @State private var channels: [TalkChannel] = []
    @State private var crews: [Crew] = []
    @State private var friendsByID: [UUID: FriendLive] = [:]
    private let talk = TalkService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Talk"); Headline(talk.conversationName, size: 28) }
                    Spacer()
                    if talk.joined { Pill(text: "Joined", style: .live) } else { Pill(text: talk.status) }
                }.padding(.top, 8)

                HoldToTalkButton().frame(maxWidth: .infinity).padding(.vertical, 10)

                Group {
                    if talk.transmitting { Text("You are transmitting to **\(talk.listeners) people**") }
                    else if let s = talk.activeSpeaker { Text("**\(s)** is talking") }
                    else { Text("Channel quiet · \(talk.listeners) listening") }
                }.font(.system(size: 15)).foregroundStyle(HazaTheme.muted).frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Button { Task { await talk.setJoined(!talk.joined) } } label: { Card { Stat(value: talk.joined ? "Leave" : "Join", label: "channel") } }
                    Button { Task { if let f = state.nearby.first { try? await SupabaseService.shared.ping(f.userId, channel: talk.conversation?.id) } } } label: { Card { Stat(value: "Ping", label: state.nearby.first?.displayName ?? "nearest") } }
                    Card { Stat(value: "Car", label: talk.isSystemPTT ? "play/pause keys mic" : "CarPlay widget") }
                }
                if !talk.isSystemPTT {
                    Text("In-app mode: hold the button here or on your Watch. The Lock Screen / steering-wheel walkie-talkie switches on once the app is signed by a developer account with Push to Talk.")
                        .font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                }

                Eyebrow("Channels").padding(.top, 12)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                ForEach(channels, id: \.id) { c in
                    Button { Task { await pick(c) } } label: {
                        Row(title: name(for: c), subtitle: subtitle(for: c)) { Glyph(text: glyph(for: c)) } trailing: {
                            if talk.conversation?.id == c.id { Pill(text: "Now", style: .live) } else { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) }
                        }
                    }
                }
                ForEach(state.friends.filter { f in !channels.contains { $0.kind == "direct" && ($0.peerA == f.userId || $0.peerB == f.userId) } }) { f in
                    Button { Task { await startDirect(with: f) } } label: {
                        Row(title: f.displayName, subtitle: "Start a direct channel") {
                            Text(String(f.displayName.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).background(HazaTheme.surface2, in: Circle())
                        } trailing: { Image(systemName: "plus").foregroundStyle(HazaTheme.muted) }
                    }
                }
                Text("One channel is active at a time (a system rule). Picking a conversation swaps the channel name, so the walkie-talkie keeps working from the Lock Screen, Control Center, CarPlay and your Watch.")
                    .font(.system(size: 12)).foregroundStyle(HazaTheme.muted).padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .task { await load() }
    }

    private func load() async {
        async let ch = SupabaseService.shared.channels()
        async let cr = SupabaseService.shared.crews()
        channels = (try? await ch) ?? []
        crews = (try? await cr) ?? []
        friendsByID = Dictionary(uniqueKeysWithValues: state.friends.map { ($0.userId, $0) })
        if talk.conversation == nil, let first = channels.first { await talk.switchConversation(to: first, named: name(for: first)) }
    }

    private func pick(_ c: TalkChannel) async {
        if talk.joined { await talk.switchConversation(to: c, named: name(for: c)) }
        else { talk.join(c, named: name(for: c)) }
    }

    private func startDirect(with f: FriendLive) async {
        guard let id = try? await SupabaseService.shared.directChannel(with: f.userId) else { return }
        await load()
        if let c = channels.first(where: { $0.id == id }) { await pick(c) }
    }

    private func name(for c: TalkChannel) -> String {
        switch c.kind {
        case "crew": return crews.first { $0.id == c.crewId }?.name ?? "Crew"
        case "plan": return "Planned drive"
        default:
            let other = [c.peerA, c.peerB].compactMap { $0 }.first { $0 != state.profile?.id }
            return other.flatMap { friendsByID[$0]?.displayName } ?? "Direct"
        }
    }
    private func subtitle(for c: TalkChannel) -> String {
        switch c.kind { case "crew": return "Crew channel"; case "plan": return "Goes live with the drive"; default: return "Direct" }
    }
    private func glyph(for c: TalkChannel) -> String { c.kind == "crew" ? "C" : c.kind == "plan" ? "P" : String(name(for: c).prefix(1)) }
}

/// The one object on the Talk screen. Press and hold; release sends. Mirrors the system PTT state.
struct HoldToTalkButton: View {
    private let talk = TalkService.shared
    @State private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(HazaTheme.hair, lineWidth: 1).frame(width: 196, height: 196)
            if talk.transmitting && !reduceMotion {
                Circle().stroke(HazaTheme.live, lineWidth: 2).frame(width: 196, height: 196)
                    .scaleEffect(pressing ? 1.35 : 1).opacity(pressing ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pressing)
            }
            Circle().fill(fill).frame(width: 150, height: 150)
                .overlay(VStack(spacing: 4) {
                    Text(title).font(HazaTheme.display(22))
                    Text(subtitle.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.3).opacity(0.7)
                }.foregroundStyle(foreground))
                .scaleEffect(talk.transmitting ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: talk.transmitting)
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressing { pressing = true; talk.beginTransmit() } }
            .onEnded { _ in pressing = false; talk.endTransmit() })
        .accessibilityLabel("Hold to talk")
        .accessibilityAddTraits(.isButton)
        .disabled(!talk.joined)
        .opacity(talk.joined ? 1 : 0.5)
    }

    private var fill: Color { talk.transmitting ? HazaTheme.live : (talk.activeSpeaker != nil ? HazaTheme.surface2 : HazaTheme.ink) }
    private var foreground: Color { talk.transmitting ? .black : (talk.activeSpeaker != nil ? HazaTheme.ink : HazaTheme.bg) }
    private var title: String { talk.transmitting ? "Talking" : (talk.activeSpeaker ?? "Hold") }
    private var subtitle: String { talk.transmitting ? "release to send" : (talk.activeSpeaker != nil ? "is talking" : "to talk") }
}
