import AppIntents
import Foundation

/// "Turn Talk on/off" — used by the CarPlay/Home Screen widget button, the Control Center control,
/// Siri and Shortcuts. Joining a PTT channel must happen in the foreground with user interaction
/// (Apple rule), so the intent records the wish and opens the app, which completes it on activation.
struct ToggleTalkIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Talk"
    static var description = IntentDescription("Join or leave your walkie-talkie channel.")
    static var openAppWhenRun = true

    @Parameter(title: "On") var on: Bool

    init() {}
    init(on: Bool) { self.on = on }

    func perform() async throws -> some IntentResult {
        SharedStore.pendingTalkToggle = on
        return .result()
    }
}

/// Backs the Control Center / Lock Screen / Action button toggle.
struct TalkToggleIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Talk"
    static var openAppWhenRun = true
    @Parameter(title: "Talk on") var value: Bool
    init() {}
    func perform() async throws -> some IntentResult {
        SharedStore.pendingTalkToggle = value
        return .result()
    }
}
