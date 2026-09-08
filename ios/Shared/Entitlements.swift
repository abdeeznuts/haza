import Foundation

/// What this particular signed build is actually allowed to do.
///
/// A build signed with a paid team (TestFlight / App Store) carries every capability in
/// Haza.entitlements. A build signed with a free Apple ID (Sideloadly / AltStore / Xcode "Personal
/// Team") only gets the basics — no push-to-talk, no App Group, no push, no Sign in with Apple,
/// no associated domains. Rather than crash or half-work, each feature asks here and falls back.
///
/// Development, ad-hoc, TestFlight and sideloaded builds embed their provisioning profile
/// (`embedded.mobileprovision`, a CMS-signed plist whose `Entitlements` dictionary is the truth).
/// App Store builds have no embedded profile; there we trust the project's entitlements file.
public enum Entitlements {
    private static let profileEntitlements: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        let obj = try? PropertyListSerialization.propertyList(from: plist, format: nil)
        return (obj as? [String: Any])?["Entitlements"] as? [String: Any]
    }()

    /// True for every build except one installed from the App Store.
    public static var hasEmbeddedProfile: Bool { profileEntitlements != nil }

    /// Whether the running binary holds an entitlement (e.g. `com.apple.developer.push-to-talk`).
    public static func has(_ key: String) -> Bool {
        guard let e = profileEntitlements else { return true }
        return e[key] != nil
    }

    public static var pushToTalk: Bool { has("com.apple.developer.push-to-talk") }
    public static var appGroups: Bool { has("com.apple.security.application-groups") }
    public static var pushNotifications: Bool { has("aps-environment") }
    public static var signInWithApple: Bool { has("com.apple.developer.applesignin") }
    public static var associatedDomains: Bool { has("com.apple.developer.associated-domains") }

    /// A free-Apple-ID build: everything works inside the app; Lock Screen walkie-talkie, widgets
    /// and pushes wait for the signed build from a paid team.
    public static var isFreeAccountBuild: Bool { hasEmbeddedProfile && !pushNotifications && !pushToTalk }
}
