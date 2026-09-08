#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity for an active drive/convoy. Shown in the Dynamic Island, Lock Screen, the Apple Watch
/// Smart Stack and — with `.supplementalActivityFamilies([.small])` — the CarPlay Dashboard on iOS 26.
public struct DriveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var speedMPH: Int
        public var predictedMPH: Int
        public var distanceMiles: Double
        public var elapsedSeconds: Int
        public var carsInConvoy: Int
        public var talkJoined: Bool
        public var activeSpeaker: String?
        public var radarSummary: String
        public init(speedMPH: Int, predictedMPH: Int, distanceMiles: Double, elapsedSeconds: Int, carsInConvoy: Int, talkJoined: Bool, activeSpeaker: String?, radarSummary: String) {
            self.speedMPH = speedMPH; self.predictedMPH = predictedMPH; self.distanceMiles = distanceMiles; self.elapsedSeconds = elapsedSeconds
            self.carsInConvoy = carsInConvoy; self.talkJoined = talkJoined; self.activeSpeaker = activeSpeaker; self.radarSummary = radarSummary
        }
    }
    public var title: String
    public var startedAt: Date
    public init(title: String, startedAt: Date) { self.title = title; self.startedAt = startedAt }
}
#endif
