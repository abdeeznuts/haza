import SwiftUI
import HazaCore

/// Friends without a link: pick a handle, find people by exact @handle, accept requests.
/// Invite links stay the fast path (they auto-friend); this is the manual one.
struct FriendsScreen: View {
    @Environment(AppState.self) private var state
    @State private var handle = ""
    @State private var handleSaved = false
    @State private var query = ""
    @State private var found: FoundProfile?
    @State private var searched = false
    @State private var pending: [PendingRequest] = []
    @State private var prefs: [UUID: FriendPref] = [:]
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Friends").padding(.top, 8)
                Headline("People you drive with", size: 28)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Your handle")
                        HStack(spacing: 8) {
                            Text("@").foregroundStyle(HazaTheme.muted)
                            TextField("handle", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .onChange(of: handle) { _, v in handle = String(v.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(20)); handleSaved = false }
                            Button(handleSaved ? "Saved" : "Save") { Task { await saveHandle() } }
                                .font(.system(size: 14, weight: .semibold)).disabled(handle.count < 3 || handleSaved)
                        }
                        Text("3–20 letters, numbers or underscores. Friends find you by it; nobody can browse a list.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                    }
                }

                if !pending.isEmpty {
                    Eyebrow("Requests").padding(.top, 6)
                    Rectangle().fill(HazaTheme.hair).frame(height: 1)
                    ForEach(pending) { r in
                        Row(title: r.displayName, subtitle: r.handle.map { "@\($0)" } ?? "wants to add you") {
                            Text(String(r.displayName.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).background(HazaTheme.surface2, in: Circle())
                        } trailing: {
                            HStack(spacing: 6) {
                                Button("Accept") { Task { try? await SupabaseService.shared.respond(to: r.userId, accept: true); await load() } }
                                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 30).background(HazaTheme.ink, in: Capsule()).foregroundStyle(HazaTheme.bg)
                                Button("No") { Task { try? await SupabaseService.shared.respond(to: r.userId, accept: false); await load() } }
                                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 30).overlay(Capsule().stroke(HazaTheme.hair, lineWidth: 1))
                            }
                        }
                    }
                }

                Eyebrow("Add by handle").padding(.top, 6)
                HStack(spacing: 8) {
                    TextField("@friend", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 14).frame(height: 46).overlay(RoundedRectangle(cornerRadius: 12).stroke(HazaTheme.hair, lineWidth: 1))
                    Button("Find") { Task { await search() } }.font(.system(size: 15, weight: .semibold)).frame(width: 70, height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(HazaTheme.hair, lineWidth: 1)).disabled(query.count < 3)
                }
                if let f = found {
                    Row(title: f.displayName, subtitle: f.handle.map { "@\($0)" }) {
                        Text(String(f.displayName.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).background(HazaTheme.surface2, in: Circle())
                    } trailing: {
                        if f.isFriend { Pill(text: "Friends", style: .live) }
                        else if f.requestPending { Pill(text: "Pending") }
                        else {
                            Button("Add") { Task { try? await SupabaseService.shared.sendFriendRequest(to: f.id); await search(); message = "Request sent" } }
                                .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 30).background(HazaTheme.ink, in: Capsule()).foregroundStyle(HazaTheme.bg)
                        }
                    }
                } else if searched {
                    Text("No one with that handle. Handles are exact — ask them for it, or send your invite link instead.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                }
                if let message { Text(message).font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }

                Eyebrow("Friends · \(state.friends.count)").padding(.top, 6)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                ForEach(state.friends) { f in
                    Row(title: f.displayName, subtitle: f.statusLine(metric: state.profile?.usesMetric ?? false)) {
                        Text(String(f.displayName.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).background(HazaTheme.surface2, in: Circle())
                    } trailing: {
                        Menu {
                            Section("Notify me when \(f.displayName)…") {
                                Toggle(isOn: binding(f.userId, \.notifyDrives)) { Label("starts driving", systemImage: "car") }
                                Toggle(isOn: binding(f.userId, \.notifyPlaces)) { Label("arrives or leaves a place", systemImage: "mappin.and.ellipse") }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bell\((prefs[f.userId]?.notifyDrives ?? false) || (prefs[f.userId]?.notifyPlaces ?? false) ? ".fill" : "")")
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 14)).foregroundStyle(HazaTheme.muted).frame(height: 32).padding(.horizontal, 8)
                            .overlay(Capsule().stroke(HazaTheme.hair, lineWidth: 1))
                        }
                    }
                }
                if !state.friends.isEmpty {
                    Text("Nudges arrive as notifications: “Ali is driving”, “Ali arrived at Work”. Each friend chooses which places are visible.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                }
                if state.friends.isEmpty { Text("No friends yet. Your invite link is the fastest way — it connects you automatically.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted) }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .task { handle = state.profile?.handle ?? ""; handleSaved = !(handle.isEmpty); await load() }
    }

    private func load() async {
        pending = (try? await SupabaseService.shared.pendingRequests()) ?? []
        prefs = Dictionary(uniqueKeysWithValues: ((try? await SupabaseService.shared.friendPrefs()) ?? []).map { ($0.friendId, $0) })
        await state.refreshFriends()
    }

    private func binding(_ friend: UUID, _ key: WritableKeyPath<FriendPref, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[friend]?[keyPath: key] ?? false },
            set: { v in
                var p = prefs[friend] ?? FriendPref(friendId: friend, notifyDrives: false, notifyPlaces: false)
                p[keyPath: key] = v
                prefs[friend] = p
                Haptics.play(.tap)
                Task { try? await SupabaseService.shared.setFriendPref(friend, notifyDrives: p.notifyDrives, notifyPlaces: p.notifyPlaces) }
            })
    }
    private func search() async {
        found = try? await SupabaseService.shared.findProfile(handle: query)
        searched = true
    }
    private func saveHandle() async {
        do { try await SupabaseService.shared.setHandle(handle); handleSaved = true; await state.loadSignedIn() }
        catch { message = "That handle is taken or invalid." }
    }
}
