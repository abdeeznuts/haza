import SwiftUI
import HazaCore

/// Ghost mode (Life360 "bubbles" / Snap "ghost"): hide from everyone for an hour, until tomorrow,
/// or until turned off. The home bubble applies regardless. One tap turns it back on.
struct GhostModeButton: View {
    let profile: Profile?
    var onChanged: () async -> Void
    @State private var busy = false

    private var isGhost: Bool { profile?.isGhost ?? false }

    var body: some View {
        Menu {
            if isGhost {
                Button { set(nil) } label: { Label("Show me again", systemImage: "eye") }
            } else {
                Button { set(.now.addingTimeInterval(3600)) } label: { Label("Hide for 1 hour", systemImage: "moon") }
                Button { set(Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 6), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(8 * 3600)) } label: { Label("Hide until morning", systemImage: "moon.zzz") }
                Button { set(.distantFuture) } label: { Label("Hide until I turn it off", systemImage: "eye.slash") }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isGhost ? "eye.slash.fill" : "eye")
                if isGhost { Text(label).font(.system(size: 13, weight: .semibold)) }
            }
            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 11).frame(height: 38)
            .background(isGhost ? AnyShapeStyle(HazaTheme.ink) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .foregroundStyle(isGhost ? HazaTheme.bg : HazaTheme.ink)
        }
        .disabled(busy)
    }

    private var label: String {
        guard let until = profile?.ghostUntil else { return "Ghost" }
        if until.timeIntervalSinceNow > 365 * 86400 { return "Ghost" }
        return "Ghost · \(until.formatted(.dateTime.hour().minute()))"
    }

    private func set(_ until: Date?) {
        busy = true
        Haptics.play(.tap)
        Task {
            try? await SupabaseService.shared.setGhost(until: until)
            LocationService.shared.ghostUntil = until
            await onChanged()
            busy = false
        }
    }
}

/// "I'm here, all good" — a one-tap location + note to the friends you pick (Life360 check-in).
struct CheckInSheet: View {
    let friends: [FriendLive]
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<UUID> = []
    @State private var note = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Check in").padding(.top, 20)
            Headline("Tell them where you are.", size: 26)
            Text(PlacesService.shared.currentPlaceName().map { "You're at \($0)." } ?? "Your exact spot right now, once. Nothing keeps sharing afterwards.")
                .font(.system(size: 14)).foregroundStyle(HazaTheme.muted)
            TextField("Add a note — “Made it”, “Running 10 late”…", text: $note).padding(.horizontal, 14).frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HazaTheme.hair, lineWidth: 1))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { withAnimation { picked = picked.count == friends.count ? [] : Set(friends.map(\.userId)) } } label: {
                        Text(picked.count == friends.count ? "None" : "Everyone").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
                            .overlay(Capsule().stroke(HazaTheme.hair, lineWidth: 1))
                    }
                    ForEach(friends) { f in
                        Button { withAnimation(.snappy) { if picked.contains(f.userId) { picked.remove(f.userId) } else { picked.insert(f.userId) } } } label: {
                            Text(f.displayName).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
                                .background(picked.contains(f.userId) ? HazaTheme.ink : .clear, in: Capsule())
                                .overlay(Capsule().stroke(picked.contains(f.userId) ? .clear : HazaTheme.hair, lineWidth: 1))
                                .foregroundStyle(picked.contains(f.userId) ? HazaTheme.bg : HazaTheme.ink)
                        }
                    }
                }
            }
            PrimaryButton(title: sent ? "Sent" : "Check in with \(picked.count)") { send() }.disabled(picked.isEmpty || sent)
            Spacer()
        }
        .padding(.horizontal, 20).background(HazaTheme.bg)
        .onAppear { picked = Set(friends.map(\.userId)) }
    }

    private func send() {
        guard let loc = LocationService.shared.location else { return }
        Task {
            try? await SupabaseService.shared.checkIn(to: Array(picked), at: GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude), note: note)
            Haptics.play(.success); sent = true
            try? await Task.sleep(for: .seconds(0.6)); dismiss()
        }
    }
}

/// Hold 1.5 s to send an SOS with your location to every friend (loud alert on their side).
/// Long-press so a pocket tap can't fire it; the ring shows the hold filling.
struct SOSButton: View {
    var onSent: (Int) -> Void
    @State private var holding = false
    @State private var progress: Double = 0
    @State private var fired = false

    var body: some View {
        ZStack {
            Capsule().fill(holding ? HazaTheme.alert : Color.clear)
            Capsule().fill(.ultraThinMaterial).opacity(holding ? 0 : 1)
            Capsule().trim(from: 0, to: progress).stroke(HazaTheme.alert, lineWidth: 2).opacity(holding ? 1 : 0)
            Text("SOS").font(.system(size: 13, weight: .bold)).foregroundStyle(holding ? .white : HazaTheme.alert)
        }
        .frame(width: 56, height: 38)
        .scaleEffect(holding ? 1.08 : 1)
        .animation(.spring(duration: 0.2), value: holding)
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 30) { fire() } onPressingChanged: { pressing in pressing ? begin() : cancel() }
        .accessibilityLabel("Hold to send SOS")
    }

    private func begin() {
        guard !fired else { return }
        holding = true; progress = 0
        Haptics.play(.warning)
        withAnimation(.linear(duration: 1.5)) { progress = 1 }
    }

    private func cancel() {
        holding = false; fired = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }

    private func fire() {
        guard !fired else { return }
        fired = true; holding = false; progress = 0
        Haptics.play(.success)
        Task {
            guard let loc = LocationService.shared.location else { onSent(0); return }
            let n = (try? await SupabaseService.shared.sendSOS(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, note: nil)) ?? 0
            onSent(n)
        }
    }
}
