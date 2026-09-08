import SwiftUI
import UserNotifications
import HazaCore

@main
struct HazaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .tint(HazaTheme.ink)
                .onOpenURL { url in Task { await state.handle(url: url) } }
                .task { await state.bootstrap() }
        }
    }
}

/// UIKit hooks the SwiftUI lifecycle doesn't expose: APNs registration and scene routing (CarPlay).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let ping = UNNotificationCategory(identifier: "PING", actions: [UNNotificationAction(identifier: "JOIN", title: "Join and talk", options: [.foreground])], intentIdentifiers: [])
        let live = UNNotificationCategory(identifier: "PLAN_LIVE", actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([ping, live])
        // A free-Apple-ID build has no aps-environment; registering would only produce an error.
        if Entitlements.pushNotifications { application.registerForRemoteNotifications() }
        return true
    }

    /// Show pushes even while the app is open (a ping while you're on the map matters).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// The tap is a user interaction in the foreground, which is what Apple requires for joining a PTT channel.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let s = info["channel_id"] as? String, let id = UUID(uuidString: s) {
            await MainActor.run { NotificationRouter.pendingChannel = id }
            await NotificationRouter.joinPending()
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await SupabaseService.shared.registerAPNsToken(deviceToken) }
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func sceneDidBecomeActive(_ scene: UIScene) {
        // A widget/control may have asked to toggle Talk while we were suspended.
        if let toggle = SharedStore.pendingTalkToggle {
            SharedStore.pendingTalkToggle = nil
            Task { await TalkService.shared.setJoined(toggle) }
        }
    }
}

/// Bridges a tapped notification to the Talk service once channels are loaded.
@MainActor
enum NotificationRouter {
    static var pendingChannel: UUID?
    static func joinPending() async {
        guard let id = pendingChannel else { return }
        guard let channels = try? await SupabaseService.shared.channels(), let c = channels.first(where: { $0.id == id }) else { return }
        pendingChannel = nil
        TalkService.shared.join(c, named: c.kind == "crew" ? "Crew" : c.kind == "plan" ? "Planned drive" : "Direct")
    }
}
