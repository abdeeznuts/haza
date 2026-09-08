import SwiftUI

/// Apple language with an editorial (Dior-like) accent: monochrome surfaces, hairlines, New York serif for
/// numerals and headlines, SF Pro for everything else. The only colors are semantic: talk-live green, radar red.
enum HazaTheme {
    static let ink = Color("Ink")            // #F4F2EC on dark, #111111 on light — defined in Assets
    static let bg = Color("Bg")              // #0B0B0C / #F6F4EE
    static let surface = Color("Surface")    // #151517 / #FFFFFF
    static let surface2 = Color("Surface2")  // #1E1E21 / #EEECE5
    static let muted = Color("Muted")        // #8E8E89 / #77776F
    static let hair = Color("Hair")          // 14% ink
    static let live = Color(red: 48/255, green: 209/255, blue: 88/255)
    static let alert = Color(red: 255/255, green: 69/255, blue: 58/255)

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static var eyebrow: Font { .system(size: 11, weight: .semibold) }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(HazaTheme.eyebrow).tracking(1.4).foregroundStyle(HazaTheme.muted)
    }
}

struct Headline: View {
    let text: String
    var size: CGFloat = 34
    init(_ text: String, size: CGFloat = 34) { self.text = text; self.size = size }
    var body: some View {
        Text(text).font(HazaTheme.display(size)).lineSpacing(-2).foregroundStyle(HazaTheme.ink).fixedSize(horizontal: false, vertical: true)
    }
}

struct Numeral: View {
    let value: String
    var size: CGFloat = 56
    var body: some View { Text(value).font(HazaTheme.display(size)).monospacedDigit().foregroundStyle(HazaTheme.ink) }
}

struct Pill: View {
    enum Style { case plain, live, alert }
    let text: String
    var style: Style = .plain
    var body: some View {
        HStack(spacing: 6) {
            if style != .plain { Circle().frame(width: 7, height: 7) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(background, in: Capsule())
        .overlay(Capsule().stroke(style == .plain ? HazaTheme.hair : .clear, lineWidth: 1))
        .foregroundStyle(foreground)
    }
    private var background: Color { switch style { case .plain: .clear; case .live: HazaTheme.live; case .alert: HazaTheme.alert } }
    private var foreground: Color { switch style { case .plain: HazaTheme.ink; case .live: .black; case .alert: .white } }
}

struct PrimaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
        }
        .background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(HazaTheme.bg)
    }
}

struct GhostButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
        .foregroundStyle(HazaTheme.ink)
    }
}

/// A list row with the hairline underneath — the app's basic building block.
struct Row<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(HazaTheme.ink)
                    if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(HazaTheme.muted).lineLimit(2) }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 14)
            Rectangle().fill(HazaTheme.hair).frame(height: 1)
        }
    }
}

struct Glyph: View {
    let text: String
    var body: some View {
        Text(text).font(HazaTheme.display(18)).frame(width: 40, height: 40)
            .background(HazaTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(HazaTheme.ink)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(HazaTheme.display(26)).monospacedDigit().foregroundStyle(HazaTheme.ink)
            Eyebrow(label)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16)
            .background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
    }
}
