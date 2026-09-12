import SwiftUI
import MapKit
import HazaCore

/// The card that appears when a drive ends — the numbers people screenshot. Counts up on appear.
struct DriveCompleteCard: View {
    let summary: DriveSummary
    let metric: Bool
    var onOpen: () -> Void
    @State private var shown = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Eyebrow("Drive complete"); Spacer(); Pill(text: "Recorded itself", style: .live) }.padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Numeral(value: shown ? String(format: "%.1f", metric ? summary.distanceM / 1000 : Units.miles(fromMeters: summary.distanceM)) : "0.0", size: 64)
                    .contentTransition(.numericText())
                Eyebrow(metric ? "km" : "miles")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(summary.durationS / 60) min").font(HazaTheme.display(22)).monospacedDigit()
                    Eyebrow("on the road")
                }
            }
            Rectangle().fill(HazaTheme.hair).frame(height: 1)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                Stat(value: Units.formatSpeed(summary.maxMps, metric: metric), label: metric ? "top km/h" : "top mph")
                Stat(value: summary.zeroToSixty.map { String(format: "%.1f s", $0) } ?? "—", label: "0–60")
                Stat(value: String(format: "%.2f g", summary.maxG), label: "peak g")
                Stat(value: "\(summary.hardBrakes)", label: "hard brakes")
                Stat(value: "\(summary.rapidAccels)", label: "launches")
                Stat(value: Units.formatSpeed(summary.avgMps ?? 0, metric: metric), label: metric ? "avg km/h" : "avg mph")
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
            Text(verdict).font(.system(size: 14)).foregroundStyle(HazaTheme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { dismiss(); onOpen() } label: { Text("See the route").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 46) }
                    .background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).foregroundStyle(HazaTheme.bg)
                ShareLink(item: shareText) { Text("Share").font(.system(size: 15, weight: .semibold)).frame(width: 90, height: 46).overlay(RoundedRectangle(cornerRadius: 12).stroke(HazaTheme.hair, lineWidth: 1)) }
            }
            Text("Only you see your stats. Nothing is ranked.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).background(HazaTheme.bg)
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.15)) { shown = true } }
    }

    private var verdict: String {
        if summary.hardBrakes == 0 && summary.rapidAccels <= 1 { return "Smooth one. No hard brakes." }
        if summary.maxG >= 0.8 { return "Spirited. Peak \(String(format: "%.2f", summary.maxG)) g — that's a proper corner." }
        if summary.hardBrakes >= 3 { return "\(summary.hardBrakes) hard brakes — traffic, or someone cut you off." }
        return "Logged with the route. Replay it with whoever was with you."
    }

    private var shareText: String {
        let dist = metric ? String(format: "%.1f km", summary.distanceM / 1000) : String(format: "%.1f mi", Units.miles(fromMeters: summary.distanceM))
        return "\(dist) in \(summary.durationS / 60) min · top \(Units.formatSpeed(summary.maxMps, metric: metric)) \(metric ? "km/h" : "mph")" + (summary.zeroToSixty.map { String(format: " · 0–60 in %.1f s", $0) } ?? "") + " — recorded by Haza"
    }
}

/// Six numbers under a drive: the honest version of Life360's "driving score" — no score, just facts.
struct DriveStatsGrid: View {
    let drive: Drive
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
            Stat(value: drive.zeroToSixtyS.map { String(format: "%.1f s", $0) } ?? "—", label: "0–60")
            Stat(value: drive.maxG.map { String(format: "%.2f g", $0) } ?? "—", label: "peak g")
            Stat(value: drive.hardBrakes.map(String.init) ?? "—", label: "hard brakes")
            Stat(value: drive.rapidAccels.map(String.init) ?? "—", label: "launches")
        }
    }
}

/// This week vs. nothing — no leaderboard, no friends' numbers, just yours.
struct RecapCard: View {
    let recap: SupabaseService.WeeklyRecap
    let metric: Bool
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Eyebrow("This week"); Spacer(); Eyebrow(Date.now.formatted(.dateTime.month(.abbreviated).day())) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(Int((metric ? recap.miles * 1.609344 : recap.miles).rounded()))).font(HazaTheme.display(44)).monospacedDigit().contentTransition(.numericText())
                    Eyebrow(metric ? "km" : "miles")
                    Spacer()
                    Text("\(recap.drives) drives · \(String(format: "%.1f", recap.hours)) h").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                    Stat(value: recap.bestZeroSixty.map { String(format: "%.1f s", $0) } ?? "—", label: "best 0–60")
                    Stat(value: recap.maxG.map { String(format: "%.2f g", $0) } ?? "—", label: "peak g")
                    Stat(value: recap.topSpeedMps.map { Units.formatSpeed($0, metric: metric) } ?? "—", label: metric ? "top km/h" : "top mph")
                    Stat(value: "\(recap.hardBrakes)", label: "hard brakes")
                    Stat(value: "\(recap.rapidAccels)", label: "launches")
                }
            }
        }
    }
}

struct RecapView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var recap: SupabaseService.WeeklyRecap?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Recap").padding(.top, 8)
                Headline("Your week, in numbers.", size: 28)
                if let recap { RecapCard(recap: recap, metric: state.profile?.usesMetric ?? false) }
                else { Text("Loading…").font(.system(size: 14)).foregroundStyle(HazaTheme.muted) }
                Text("Every drive records itself; the recap adds them up each Monday. Only you see this.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
            }.padding(20)
        }
        .background(HazaTheme.bg)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { recap = try? await SupabaseService.shared.weeklyRecap(); DiscoverEngine.shared.note(.recapSeen) }
    }
}

/// One day, top to bottom: the trail on a map (positions sampled every 15 min, so it costs
/// nothing), then drives and place arrivals as a list — Life360's history, built from events.
struct DayTimelineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var items: [TimelineItem] = []
    @State private var loading = true
    @State private var camera: MapCameraPosition = .automatic

    private var trail: [CLLocationCoordinate2D] { items.filter { $0.kind == "position" }.compactMap { it in it.lat.flatMap { la in it.lng.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } } } }
    private var events: [TimelineItem] { items.filter { $0.kind != "position" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Timeline"); Headline(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), size: 28) }
                    Spacer()
                    HStack(spacing: 6) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36).overlay(Circle().stroke(HazaTheme.hair, lineWidth: 1)) }
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36).overlay(Circle().stroke(HazaTheme.hair, lineWidth: 1)) }.disabled(Calendar.current.isDateInToday(day))
                    }
                }.padding(.top, 8)
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    if trail.count >= 2 { MapPolyline(coordinates: trail).stroke(HazaTheme.ink, style: StrokeStyle(lineWidth: 3, dash: [5, 5])) }
                    ForEach(events) { it in
                        if let la = it.lat, let ln = it.lng {
                            Annotation(title(it), coordinate: CLLocationCoordinate2D(latitude: la, longitude: ln)) {
                                Circle().fill(color(it.kind)).frame(width: 12, height: 12).overlay(Circle().stroke(HazaTheme.bg, lineWidth: 2))
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
                .overlay { if !loading && trail.isEmpty && events.isEmpty { Text("Nothing recorded this day.").font(.system(size: 13)).foregroundStyle(HazaTheme.muted).padding(10).background(HazaTheme.surface, in: RoundedRectangle(cornerRadius: 10)) } }
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                if loading { Text("Loading…").font(.system(size: 14)).foregroundStyle(HazaTheme.muted) }
                ForEach(events) { it in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle().fill(color(it.kind)).frame(width: 10, height: 10).padding(.top, 6)
                            Rectangle().fill(HazaTheme.hair).frame(width: 1).frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(it)).font(.system(size: 15, weight: .medium))
                            Text(it.at.formatted(.dateTime.hour().minute())).font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
                        }
                        .padding(.bottom, 18)
                        Spacer()
                    }
                }
                Text("Positions are sampled every 15 minutes from what your phone already knows — no extra GPS. Only you can see this.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task(id: day) {
            loading = true
            items = (try? await SupabaseService.shared.timeline(day: day)) ?? []
            loading = false
            frame()
        }
    }

    private func frame() {
        let all = trail + events.compactMap { it in it.lat.flatMap { la in it.lng.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } } }
        guard !all.isEmpty else { camera = .userLocation(fallback: .automatic); return }
        var rect = MKMapRect.null
        for c in all { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1))) }
        camera = .rect(rect.insetBy(dx: -max(rect.size.width * 0.25, 600), dy: -max(rect.size.height * 0.25, 600)))
    }

    private func shift(_ d: Int) { day = Calendar.current.date(byAdding: .day, value: d, to: day) ?? day }
    private func color(_ k: String) -> Color { k == "drive" ? HazaTheme.live : k == "sos" ? HazaTheme.alert : HazaTheme.ink }
    private func title(_ it: TimelineItem) -> String {
        switch it.kind {
        case "drive": return it.title ?? "Drive"
        case "place_arrive": return "Arrived at \(it.title ?? "a place")"
        case "place_leave": return "Left \(it.title ?? "a place")"
        default: return it.title ?? it.kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
