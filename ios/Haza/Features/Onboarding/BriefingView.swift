import SwiftUI
import CoreLocation
import HazaCore

/// "What you're missing" — every row is one tap. Shown at launch until setup items are done,
/// then reachable from Profile as "Briefing".
struct BriefingView: View {
    @Environment(AppState.self) private var state
    @State private var sheet: BriefingItem.Action?
    var embedded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Briefing").padding(.top, embedded ? 0 : 24)
                Headline(Briefing.headline(remaining: state.briefing.count))
                Text("Haza works better the more it knows. Each row is one tap; the rest can wait.")
                    .font(.system(size: 15)).foregroundStyle(HazaTheme.muted).padding(.bottom, 10)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                ForEach(Array(state.briefing.enumerated()), id: \.element.id) { i, item in
                    Button { perform(item) } label: {
                        Row(title: item.title, subtitle: item.detail) { Glyph(text: "\(i + 1)") } trailing: {
                            Image(systemName: "chevron.right").foregroundStyle(HazaTheme.muted)
                        }
                    }
                }
                if !embedded {
                    PrimaryButton(title: state.briefing.contains { $0.severity == .setup } ? "Do the rest later" : "Open the map") {
                        Task { await state.finishBriefing() }
                    }.padding(.top, 16)
                    Text("Radar detectors are illegal in passenger cars in Virginia, Washington D.C., on military bases, and in commercial vehicles over 10,000 lb. Haza only displays your detector's alerts.")
                        .font(.system(size: 12)).foregroundStyle(HazaTheme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .sheet(item: $sheet) { action in BriefingActionSheet(action: action).presentationDetents([.medium, .large]) }
        .task { await state.refreshBriefing() }
    }

    private func perform(_ item: BriefingItem) {
        switch item.action {
        case .requestLocationAlways:
            let loc = LocationService.shared
            if loc.authorization == .notDetermined { loc.start() } else { loc.requestAlways() }
            Task { try? await Task.sleep(for: .seconds(2)); await state.refreshBriefing() }
        case .enableNotifications:
            Task { _ = await NotificationsService.request(); await state.refreshBriefing() }
        default:
            sheet = item.action
        }
    }
}

extension BriefingItem.Action: Identifiable { public var id: String { String(describing: self) } }

/// One sheet per action so the briefing stays a single tap deep.
struct BriefingActionSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let action: BriefingItem.Action

    var body: some View {
        NavigationStack {
            Group {
                switch action {
                case .addVehicle: GarageScreen(onSaved: { done() })
                case .inviteFriend: VStack(spacing: 0) { InviteView(); FriendsScreen() }
                case .setHome, .confirmHome: HomeSetupView(onSaved: { done() })
                case .createCrew: CrewCreateView(onSaved: { done() })
                case .pairRadar: RadarScreen()
                case .installWatchApp: SurfaceGuide(kind: .watch) { mark("briefing.watch.done") }
                case .addCarPlayWidget: SurfaceGuide(kind: .carplay) { mark("briefing.carplay.done") }
                case .addControl: SurfaceGuide(kind: .control) { mark("briefing.control.done") }
                case .viewReferrals: ReferralView()
                default: Text("Done").padding()
                }
            }
            .background(HazaTheme.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { done() } } }
        }
    }

    private func mark(_ key: String) { UserDefaults.standard.set(true, forKey: key); done() }
    private func done() { Task { await state.refreshBriefing() }; dismiss() }
}

/// Plain-language guide for the three system surfaces the user has to add themselves.
struct SurfaceGuide: View {
    enum Kind { case watch, carplay, control }
    let kind: Kind
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch kind {
                case .watch:
                    Headline("Talk from your wrist")
                    Text("Open the Watch app on your iPhone, scroll to Available Apps, and install \(HazaBrand.name). Hold the green button to talk; you'll feel a tap when someone speaks.")
                case .carplay:
                    Headline("Talk on the car's screen")
                    Text("On iPhone: Settings › General › CarPlay › your car › Widgets, then add \(HazaBrand.name). The widget shows Talk on/off, your speed now and in three seconds, and your next meet. During a drive, the live drive card appears on the Dashboard too.")
                    Text("This works on iOS 26 without any special approval. The full CarPlay app (ping friends, crew channels) arrives when Apple approves our CarPlay entitlement.").foregroundStyle(HazaTheme.muted)
                case .control:
                    Headline("Talk in Control Center")
                    Text("Press and hold an empty spot in Control Center › Add a Control › \(HazaBrand.name) › Talk. You can also put it on the Lock Screen or the Action button.")
                }
                PrimaryButton(title: "Done", action: onDone).padding(.top, 8)
            }
            .font(.system(size: 15)).foregroundStyle(HazaTheme.ink).padding(20)
        }
    }
}
