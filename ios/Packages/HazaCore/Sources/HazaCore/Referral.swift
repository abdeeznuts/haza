import Foundation

/// Invite links and codes. Server truth lives in `claim_invite()` + the `drives_qualify_referral` trigger;
/// this mirrors the rules so the UI can explain them without a round-trip.
public enum Referral {
    public static let referrerRewardDays = 30
    public static let refereeRewardDays = 14
    public static let qualifyingDistanceMeters = 1609.0     // first drive ≥ 1 mile
    public static let linkHost = "haza.app"                  // change with HazaBrand

    /// Codes are 8 hex characters; users may type them with a dash or spaces, any case.
    public static func normalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isHexDigit }
        return cleaned.count == 8 ? cleaned : nil
    }

    public static func display(_ code: String) -> String {
        let c = normalize(code) ?? code
        guard c.count == 8 else { return c }
        return String(c.prefix(4)) + "-" + String(c.suffix(4))
    }

    public static func link(for code: String) -> URL {
        URL(string: "https://\(linkHost)/i/\(normalize(code) ?? code)")!
    }

    /// Extracts a code from a Universal Link (`https://haza.app/i/CODE`), a custom scheme (`haza://i/CODE`) or plain text.
    public static func code(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(of: "i"), i + 1 < parts.count { return normalize(parts[i + 1]) }
        if url.scheme == "pace", let host = url.host, host == "i", let last = parts.last { return normalize(last) }
        return normalize(url.absoluteString.components(separatedBy: "/").last ?? "")
    }

    public static func code(fromPasteboard text: String) -> String? {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil { return code(from: url) }
        return normalize(text)
    }

    public static func rewardSummary(referrals rewarded: Int) -> String {
        let days = rewarded * referrerRewardDays
        switch rewarded {
        case 0: return "Share your link. Each friend who joins and finishes a first drive gives you \(referrerRewardDays) days of Pro."
        case 1: return "1 friend joined — \(days) days of Pro earned. Next friend adds \(referrerRewardDays)."
        default: return "\(rewarded) friends joined — \(days) days of Pro earned. Next friend adds \(referrerRewardDays)."
        }
    }
}
