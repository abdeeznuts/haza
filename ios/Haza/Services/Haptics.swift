import UIKit

/// One place for the app's touch language. Kept tiny and deliberate: haptics mark moments
/// (a drive starting, a transmission opening, a friend arriving), never every tap.
enum Haptics {
    enum Kind { case tap, start, success, warning, talkOn, talkOff }

    /// Safe from any context: hops to the main actor if needed (UIKit generators are main-actor bound).
    nonisolated static func play(_ kind: Kind) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { fire(kind) }
        } else {
            Task { @MainActor in fire(kind) }
        }
    }

    @MainActor private static func fire(_ kind: Kind) {
        switch kind {
        case .tap: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .talkOn: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case .talkOff: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        }
    }
}
