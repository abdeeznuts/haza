import SwiftUI
import HazaCore

struct RadarScreen: View {
    private let v1 = V1Client.shared
    @State private var partnerSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Radar"); Headline("Valentine One Gen2", size: 28) }
                    Spacer()
                    statePill
                }.padding(.top, 8)

                V1Panel(display: v1.display, alerts: v1.alerts, firmware: v1.firmware)

                HStack(spacing: 10) {
                    switch v1.state {
                    case .connected: GhostButton(title: "Disconnect") { v1.disconnect() }
                    case .scanning, .connecting: GhostButton(title: "Cancel") { v1.disconnect() }
                    default: PrimaryButton(title: "Pair over Bluetooth") { v1.startScanning() }
                    }
                    GhostButton(title: v1.display?.isMuted == true ? "Unmute" : "Mute") { v1.mute(!(v1.display?.isMuted ?? false)) }
                }

                Rectangle().fill(HazaTheme.hair).frame(height: 1).padding(.top, 8)
                Toggle(isOn: Binding(get: { v1.shareWithCrew }, set: { v1.shareWithCrew = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share alerts with friends").font(.system(size: 16, weight: .medium))
                        Text("Strong alerts drop a pin on your friends' maps for 15 minutes, with band and direction.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                    }
                }.tint(HazaTheme.live).padding(.vertical, 8)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                Button { partnerSheet = true } label: {
                    Row(title: "Escort · Uniden · Radenso", subtitle: "These makers publish no app interface. Ask them to open one — the request is prewritten.") { Glyph(text: "?") } trailing: { Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted) }
                }
                Text("Haza only displays what your detector reports. Radar detectors are illegal in passenger cars in Virginia, Washington D.C., and on military bases, and in commercial vehicles over 10,000 lb everywhere in the U.S.")
                    .font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .sheet(isPresented: $partnerSheet) { PartnerRequestView() }
    }

    @ViewBuilder private var statePill: some View {
        switch v1.state {
        case .off: Pill(text: "Not paired")
        case .scanning: Pill(text: "Looking…")
        case .connecting(let n): Pill(text: "Connecting \(n)")
        case .connected: Pill(text: "Bluetooth", style: .live)
        case .failed(let why): Pill(text: why, style: .alert)
        }
    }
}

/// A faithful rendering of the V1 front panel from infDisplayData + the Alert Table.
struct V1Panel: View {
    let display: ESP.Display?
    let alerts: [ESP.Alert]
    let firmware: String?
    private let led = Color(red: 1, green: 0.18, blue: 0.12)
    private let dim = Color(red: 0.23, green: 0.07, blue: 0.06)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(display.flatMap { $0.bogeyCounter.map(String.init) } ?? "0").font(.system(size: 44, weight: .regular, design: .monospaced)).foregroundStyle(led)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(i < (display?.barGraphLevel ?? 0) ? led : dim).frame(width: 14, height: 18)
                            .shadow(color: i < (display?.barGraphLevel ?? 0) ? led.opacity(0.6) : .clear, radius: 6)
                    }
                }
            }
            HStack {
                HStack(spacing: 14) {
                    band("L", on: display?.band.contains(.laser) ?? false)
                    band("Ka", on: display?.band.contains(.ka) ?? false)
                    band("K", on: display?.band.contains(.k) ?? false)
                    band("X", on: display?.band.contains(.x) ?? false)
                }
                Spacer()
                HStack(spacing: 10) {
                    Text("▲").foregroundStyle(display?.band.contains(.front) == true ? led : dim)
                    Text("◆").foregroundStyle(display?.band.contains(.side) == true ? led : dim)
                    Text("▼").foregroundStyle(display?.band.contains(.rear) == true ? led : dim)
                }.font(.system(size: 20))
            }
            Text(summary).font(.system(size: 12, design: .monospaced)).foregroundStyle(dim.opacity(1.8))
        }
        .padding(18)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
    }

    private func band(_ t: String, on: Bool) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(on ? led : dim).shadow(color: on ? led.opacity(0.6) : .clear, radius: 6)
    }
    private var summary: String {
        if let a = alerts.first(where: { $0.isPriority }) ?? alerts.first {
            return "\(a.band.name) \(Double(a.frequencyMHz) / 1000) GHz · \(a.band.direction) · \(a.bars)/8\(a.isPriority ? " · priority" : "")"
        }
        return "All quiet" + (firmware.map { " · fw \($0)" } ?? "") + (display.map { " · vol \($0.mainVolume)" } ?? "")
    }
}

/// Escort and Uniden expose no API; Haza collects interest and gives the user a prewritten request.
struct PartnerRequestView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Headline("Not connectable yet", size: 26)
                    Text("Escort's Drive Smarter app and Uniden's R/TACH app talk to their detectors over Bluetooth, but neither company publishes an interface for other apps. Valentine Research does, which is why the V1 Gen2 works today.")
                    Text("If you own one of these, send the maker this note. Enough requests is how these things open up.").foregroundStyle(HazaTheme.muted)
                    Card {
                        Text("Hi — I use Haza, a social driving app, with my \u{201C}[Escort Max 360c / Uniden R8]\u{201D}. Valentine One offers a public protocol so apps like Haza can show detector alerts on the map. Would you consider publishing a developer interface for your Bluetooth detectors? Thanks.")
                            .font(.system(size: 14)).textSelection(.enabled)
                    }
                    ShareLink(item: "Hi — I use Haza, a social driving app, with my [Escort Max 360c / Uniden R8]. Valentine One offers a public protocol so apps like Haza can show detector alerts on the map. Would you consider publishing a developer interface for your Bluetooth detectors? Thanks.") {
                        Text("Share the request").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
                    }.background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(HazaTheme.bg)
                }
                .font(.system(size: 15)).foregroundStyle(HazaTheme.ink).padding(20)
            }
            .background(HazaTheme.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
