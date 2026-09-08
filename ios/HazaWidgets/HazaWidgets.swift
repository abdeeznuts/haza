import WidgetKit
import SwiftUI
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct HazaWidgetBundle: WidgetBundle {
    var body: some Widget {
        TalkWidget()
        DriveLiveActivity()
        TalkControl()
    }
}

// MARK: - The CarPlay / Home Screen / StandBy widget

struct TalkEntry: TimelineEntry {
    let date: Date
    let talk: TalkSnapshot
    let drive: DriveSnapshot
}

struct TalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> TalkEntry {
        TalkEntry(date: .now, talk: TalkSnapshot(channelName: "Crew", joined: true, listeners: 3), drive: DriveSnapshot(speedMPH: 62, predictedMPH: 64, speedLimitMPH: 65, nearestFriend: "Ali", nearestFriendDistanceMiles: 0.8))
    }
    func getSnapshot(in context: Context, completion: @escaping (TalkEntry) -> Void) {
        completion(TalkEntry(date: .now, talk: SharedStore.talk, drive: SharedStore.drive))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkEntry>) -> Void) {
        // The app reloads timelines when Talk state or speed changes; this is just the fallback cadence.
        let entry = TalkEntry(date: .now, talk: SharedStore.talk, drive: SharedStore.drive)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }
}

struct TalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.haza.talk", provider: TalkProvider()) { entry in
            TalkWidgetView(entry: entry)
                .containerBackground(Color(red: 0.043, green: 0.043, blue: 0.047), for: .widget)   // removable in CarPlay per Apple
        }
        .configurationDisplayName("Talk")
        .description("Walkie-talkie on/off, your speed now and in 3 seconds, nearest friend.")
        .supportedFamilies([.systemSmall, .systemMedium])   // systemSmall is what CarPlay (iOS 26) shows
    }
}

struct TalkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TalkEntry
    private let live = Color(red: 48/255, green: 209/255, blue: 88/255)
    private let ink = Color(red: 0.957, green: 0.949, blue: 0.925)
    private let muted = Color(red: 0.56, green: 0.56, blue: 0.54)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.talk.channelName.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted).lineLimit(1)
                Spacer()
                if let s = entry.talk.activeSpeaker { Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(live).lineLimit(1) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.drive.speedMPH)").font(.system(size: 34, design: .serif)).monospacedDigit().foregroundStyle(ink)
                Text("\(entry.drive.predictedMPH)").font(.system(size: 15, design: .serif)).monospacedDigit().foregroundStyle(muted)
                Text("mph").font(.system(size: 9, weight: .semibold)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Button(intent: ToggleTalkIntent(on: !entry.talk.joined)) {
                HStack(spacing: 6) {
                    Image(systemName: entry.talk.joined ? "mic.fill" : "mic.slash").font(.system(size: 11, weight: .semibold))
                    Text(entry.talk.joined ? "Talk on" : "Talk off").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(entry.talk.joined ? live : Color(white: 0.16), in: Capsule())
                .foregroundStyle(entry.talk.joined ? .black : ink)
            }
            .buttonStyle(.plain)
            if family == .systemMedium, let n = entry.drive.nearestFriend, let d = entry.drive.nearestFriendDistanceMiles {
                Text(String(format: "%@ · %.1f mi · %@", n, d, entry.drive.radarSummary)).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
            }
        }
    }
}

// MARK: - Control Center / Lock Screen / Action button toggle (iOS 18+)

struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.haza.talk.control") {
            ControlWidgetToggle("Talk", isOn: SharedStore.talk.joined, action: TalkToggleIntent()) { on in
                Label(on ? "On" : "Off", systemImage: on ? "mic.fill" : "mic.slash")
            }
            .tint(.green)
        }
        .displayName("Talk")
        .description("Join or leave your crew channel.")
    }
}

// MARK: - Drive Live Activity (Dynamic Island, Lock Screen, Watch Smart Stack, CarPlay Dashboard)

#if canImport(ActivityKit)
struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.system(size: 13, weight: .semibold))
                    Text("\(context.state.carsInConvoy) cars · \(String(format: "%.1f", context.state.distanceMiles)) mi · \(context.state.radarSummary)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(context.state.speedMPH)").font(.system(size: 30, design: .serif)).monospacedDigit()
                Text("mph").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.043, green: 0.043, blue: 0.047))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.attributes.title).font(.system(size: 13, weight: .semibold)) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.speedMPH) mph").font(.system(size: 15, design: .serif)).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.activeSpeaker.map { "\($0) is talking" } ?? (context.state.talkJoined ? "Talk on · \(context.state.carsInConvoy) cars" : "Talk off")).font(.system(size: 12))
                }
            } compactLeading: {
                Image(systemName: context.state.talkJoined ? "mic.fill" : "car.fill")
            } compactTrailing: {
                Text("\(context.state.speedMPH)").monospacedDigit()
            } minimal: {
                Image(systemName: "car.fill")
            }
        }
        .supplementalActivityFamilies([.small])   // Apple: the same small family serves Watch Smart Stack and CarPlay
    }
}
#endif
