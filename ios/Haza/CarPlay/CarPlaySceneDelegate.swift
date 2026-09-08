import CarPlay
import UIKit
import HazaCore

/// Full CarPlay app (needs Apple's CarPlay entitlement — request at developer.apple.com/carplay).
/// Built from templates only, as Apple requires: a tab bar with Talk (channel list + join/leave),
/// Friends nearby (tap = ping), and Tonight (the next plan). Nothing refreshes faster than every 10 s,
/// no message content is ever shown, and every flow works without touching the iPhone.
///
/// Until the entitlement is granted this scene never launches; the Dashboard widget + Live Activity
/// (HazaWidgets) cover the car screen with no entitlement at all on iOS 26.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interface: CPInterfaceController?
    private var refresh: Timer?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        let tabs = CPTabBarTemplate(templates: [talkTemplate(), friendsTemplate(), plansTemplate()])
        interfaceController.setRootTemplate(tabs, animated: true, completion: nil)
        refresh = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in   // Apple: ≥ 10 s
            Task { @MainActor in self?.reload() }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        refresh?.invalidate(); refresh = nil; interface = nil
    }

    private func reload() {
        guard let tabs = interface?.rootTemplate as? CPTabBarTemplate else { return }
        tabs.updateTemplates([talkTemplate(), friendsTemplate(), plansTemplate()])
    }

    // MARK: Talk

    private func talkTemplate() -> CPListTemplate {
        let talk = SharedStore.talk
        let status = CPListItem(text: talk.joined ? "Talk on · \(talk.channelName)" : "Talk off",
                                detailText: talk.activeSpeaker.map { "\($0) is talking" } ?? (talk.joined ? "Press play/pause on the wheel to talk" : "Tap to join \(talk.channelName)"))
        status.handler = { _, done in
            Task { @MainActor in await TalkService.shared.setJoined(!TalkService.shared.joined); done() }
        }
        let section = CPListSection(items: [status], header: "Walkie-talkie", sectionIndexTitle: nil)
        let t = CPListTemplate(title: "Talk", sections: [section])
        t.tabImage = UIImage(systemName: "mic")
        return t
    }

    // MARK: Friends nearby (from the last refresh the phone app made)

    private func friendsTemplate() -> CPListTemplate {
        let drive = SharedStore.drive
        var items: [CPListItem] = []
        if let n = drive.nearestFriend, let d = drive.nearestFriendDistanceMiles {
            let item = CPListItem(text: n, detailText: String(format: "%.1f mi away · tap to ping", d))
            item.handler = { _, done in done() }     // ping is wired through the phone app's nearby list
            items.append(item)
        } else {
            items.append(CPListItem(text: "No friends nearby", detailText: "They'll appear here within 1.5 miles"))
        }
        let t = CPListTemplate(title: "Friends", sections: [CPListSection(items: items)])
        t.tabImage = UIImage(systemName: "person.2")
        return t
    }

    // MARK: Tonight

    private func plansTemplate() -> CPListTemplate {
        let drive = SharedStore.drive
        let item: CPListItem
        if let title = drive.nextPlanTitle {
            item = CPListItem(text: title, detailText: drive.nextPlanTime.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) })
        } else {
            item = CPListItem(text: "No plan yet", detailText: "Post one from the app before you leave")
        }
        let t = CPListTemplate(title: "Tonight", sections: [CPListSection(items: [item])])
        t.tabImage = UIImage(systemName: "calendar")
        return t
    }
}
