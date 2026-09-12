import SwiftUI
import Observation
import HazaCore

/// Root observable state: session, profile, Pro status, briefing. Feature screens read from here
/// and call services directly.
@Observable @MainActor
final class AppState {
    enum Route { case welcome, name, briefing, main }

    var route: Route = .welcome
    var profile: Profile?
    var pro = ProStatus()
    var briefing: [BriefingItem] = []
    var pendingInviteCode: String?
    var friends: [FriendLive] = []
    var nearby: [FriendNearby] = []
    var lastError: String?

    private let supabase = SupabaseService.shared

    func bootstrap() async {
        // Invite codes arrive via Universal Link (handle(url:)) or the user pasting on WelcomeView;
        // the pasteboard is never read without a tap.
        do {
            if try await supabase.restoreSession() {
                await loadSignedIn()
                DiscoverEngine.shared.note(.appOpened)      // once per launch: paces the feature intros
            } else {
                route = .welcome
            }
        } catch {
            lastError = error.localizedDescription
            route = .welcome
        }
    }

    func handle(url: URL) async {
        // haza://auth#access_token=… — the magic link landed back in the app.
        if url.scheme == "haza", url.host == "auth" {
            do { try await supabase.session(from: url); await loadSignedIn() }
            catch { lastError = "That sign-in link didn't work — request a new one." }
            return
        }
        // https://haza.app/i/CODE (Universal Link) or haza://i/CODE (URL-scheme fallback).
        if let code = Referral.code(from: url) ?? Self.schemeInviteCode(url) {
            pendingInviteCode = code
            if profile != nil { await claimInvite(code) }
        }
    }

    private static func schemeInviteCode(_ url: URL) -> String? {
        guard url.scheme == "haza", url.host == "i" else { return nil }
        return Referral.normalize(url.lastPathComponent)
    }

    /// Email OTP: the same email carries a link and a 6-digit code; typing the code never leaves the app.
    func verifyEmailCode(email: String, code: String) async -> Bool {
        do { try await supabase.verifyEmailCode(email: email, code: code); await loadSignedIn(); return true }
        catch { lastError = "Wrong or expired code."; return false }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        do {
            try await supabase.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            await loadSignedIn()
        } catch { lastError = error.localizedDescription }
    }

    /// Email + password (beta): new accounts are created on the spot, no email to wait for.
    func signInWithPassword(email: String, password: String, name: String?) async -> Bool {
        do {
            let created = try await supabase.signInOrSignUp(email: email, password: password, displayName: name)
            if created, let name, !name.isEmpty { UserDefaults.standard.set(true, forKey: "name.confirmed") }
            await loadSignedIn()
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    func signInWithEmail(_ email: String) async {
        do { try await supabase.sendMagicLink(email: email) } catch { lastError = error.localizedDescription }
    }

    func loadSignedIn() async {
        do {
            profile = try await supabase.myProfile()
            LocationService.shared.ghostUntil = profile?.ghostUntil
            if let code = pendingInviteCode { await claimInvite(code) }
            await refreshPro()
            await refreshBriefing()
            // Onboarding = name → briefing → main. After that, profile edits must never bounce the
            // user back into onboarding (this runs after every profile change).
            if profile?.onboardingDone == true {
                route = .main
            } else if !UserDefaults.standard.bool(forKey: "name.confirmed") {
                route = .name          // once: "what should friends call you?" (email sign-ins have no name)
            } else {
                route = .briefing
            }
            await StoreService.shared.start()
            LocationService.shared.start()
            await TalkService.shared.prepare()
            InboxService.shared.onFriendsChanged = { [weak self] in await self?.refreshFriends() }
            await InboxService.shared.start()
            await PlacesService.shared.load()
        } catch {
            lastError = error.localizedDescription
            route = .welcome
        }
    }

    func confirmName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != profile?.displayName {
            try? await supabase.updateProfile(["display_name": .string(String(trimmed.prefix(40)))])
        }
        UserDefaults.standard.set(true, forKey: "name.confirmed")
        await loadSignedIn()
    }

    func claimInvite(_ code: String) async {
        guard let normalized = Referral.normalize(code) else { return }
        _ = try? await supabase.claimInvite(code: normalized, deviceHash: DeviceIdentity.hash)
        pendingInviteCode = nil
    }

    func refreshPro() async {
        if let p = try? await supabase.myPro() { pro = p }
    }

    func refreshBriefing() async {
        let server = (try? await supabase.myBriefing()) ?? []
        let facts = await DeviceFacts.current()
        briefing = Briefing.merge(server: server, device: facts)
    }

    func finishBriefing() async {
        try? await supabase.markOnboardingDone()
        route = .main
    }

    func refreshFriends() async {
        async let live = supabase.friendsLive()
        async let near = supabase.friendsNearby(radiusMeters: 1500)
        friends = (try? await live) ?? []
        nearby = (try? await near) ?? []
    }

    func signOut() async {
        await InboxService.shared.stop()
        TalkService.shared.leave()
        try? await supabase.signOut()
        profile = nil; friends = []; nearby = []; route = .welcome
    }

    func deleteAccount() async {
        do { try await supabase.deleteMyAccount(); await signOut() } catch { lastError = error.localizedDescription }
    }
}

extension DeviceFacts {
    /// Things only the phone knows. Location + notifications are real checks; Watch/CarPlay/Control
    /// completion is recorded when the user goes through the relevant briefing step.
    @MainActor
    static func current() async -> DeviceFacts {
        let loc = LocationService.shared.authorization == .authorizedAlways
        let notif = await NotificationsService.isAuthorized()
        let d = UserDefaults.standard
        return DeviceFacts(locationAlways: loc,
                           notificationsAllowed: notif,
                           watchAppInstalled: WatchBridge.shared.isWatchAppInstalled || d.bool(forKey: "briefing.watch.done"),
                           carPlayWidgetSeen: d.bool(forKey: "briefing.carplay.done"),
                           controlAdded: d.bool(forKey: "briefing.control.done"))
    }
}

enum DeviceIdentity {
    /// Stable per-install hash used only for referral abuse checks (never sent anywhere else).
    static var hash: String {
        let key = "device.hash"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}
