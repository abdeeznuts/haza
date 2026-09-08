import Foundation

/// One place to rename the product. Also change PRODUCT_BUNDLE_IDENTIFIER in project.yml,
/// `applinks:` in the entitlements, `Referral.linkHost` in HazaCore and APNS_BUNDLE_ID on the server.
public enum HazaBrand {
    public static let name = "Haza"
    public static let bundleID = "app.haza.ios"
    public static let appGroup = "group.app.haza"
    public static let universalLinkHost = "haza.app"
    public static let supportEmail = "support@haza.app"
    public static let privacyURL = URL(string: "https://haza.app/privacy")!
    public static let termsURL = URL(string: "https://haza.app/terms")!

    /// Launch phase: every feature is free for everyone; Pro / paywall UI is hidden. The server
    /// mirrors this (`private.settings.everything_unlocked`). Flip both together when it's time to sell.
    public static let everythingUnlocked = true

    /// Supabase project (public values — safe to ship). Secrets never live in the app.
    public static let supabaseURL = URL(string: "https://ooeykcnrnvneklwoxyti.supabase.co")!
    public static let supabaseKey = "sb_publishable_CJVZYYyfc3ITVFq-XLmaKg_GvVyjRbk"
    /// Older supabase-swift versions only accept the legacy JWT-style anon key; swap this in if sign-in fails with a key error.
    public static let supabaseLegacyAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vZXlrY25ybnZuZWtsd294eXRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MzczOTAsImV4cCI6MjEwNDMxMzM5MH0.12b63KSPzna9rJqVbuA405zQNFXKgVNN3eQRk0xzuDs"

    public enum Products {
        public static let monthly = "app.haza.pro.monthly"
        public static let yearly = "app.haza.pro.yearly"
        public static let all = [monthly, yearly]
    }
}
