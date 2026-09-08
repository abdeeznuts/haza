import Foundation
import CoreLocation
import CoreMotion
import Observation
import HazaCore

/// Location, drive detection and position sharing.
///  - Foreground: continuous updates.
///  - Background (Always): a `CLBackgroundActivitySession` keeps updates flowing while a drive is active;
///    Core Motion's automotive state starts/stops drives so the user never taps anything.
///  - Sharing: broadcast on Realtime `loc:<uid>` every 3 s while driving / 60 s parked, plus the
///    last-known row in `live_locations`.
@Observable @MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    private(set) var speedFilter = SpeedFilter()
    private(set) var isDriving = false
    private(set) var currentDrive: DriveRecorder?
    var primaryVehicleID: UUID?
    var shareEnabled = true

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var lastShare = Date.distantPast
    private var lastHomeSample = Date.distantPast
    private var stillSince: Date?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    func start() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        startMotion()
    }

    /// Called from the Briefing "Location: Always" row — after When-In-Use is granted.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    private func startMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let a = activity else { return }
            let automotive = a.automotive && a.confidence != .low
            let still = a.stationary && a.confidence == .high
            Task { @MainActor [weak self] in
                guard let self else { return }
                if automotive { self.beginDriveIfNeeded() } else if still { self.noteStill() }
            }
        }
    }

    private func beginDriveIfNeeded() {
        guard !isDriving else { return }
        isDriving = true
        stillSince = nil
        currentDrive = DriveRecorder(vehicleID: primaryVehicleID)
        if authorization == .authorizedAlways { backgroundSession = CLBackgroundActivitySession() }
        DriveActivityController.shared.start(title: "Drive")
        Task { await RealtimeService.shared.joinMyChannel() }
    }

    private func noteStill() {
        guard isDriving else { return }
        if stillSince == nil { stillSince = .now }
        // Parked for 4 minutes → the drive is over.
        if let s = stillSince, Date.now.timeIntervalSince(s) > 240 { endDrive() }
    }

    func endDrive() {
        guard isDriving, let recorder = currentDrive else { return }
        isDriving = false
        backgroundSession?.invalidate(); backgroundSession = nil
        currentDrive = nil
        DriveActivityController.shared.end()
        Task { await recorder.finishAndUpload() }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.consume(loc) }
        }
    }

    private func consume(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }
        location = loc
        if loc.speed >= 0 {
            speedFilter.update(measuredSpeed: loc.speed, accuracy: loc.speedAccuracy >= 0 ? loc.speedAccuracy : 3, at: loc.timestamp.timeIntervalSince1970)
        }
        // GPS says we're moving at road speed: start a drive even if Core Motion hasn't caught up.
        if loc.speed > 6, !isDriving { beginDriveIfNeeded() }
        currentDrive?.add(loc, filteredSpeed: speedFilter.speed)
        updateSnapshots(loc)
        shareIfDue(loc)
        sampleHomeIfNight(loc)
    }

    private func updateSnapshots(_ loc: CLLocation) {
        var d = SharedStore.drive
        d.speedMPH = Int(speedFilter.speedMPH.rounded())
        d.predictedMPH = Int(speedFilter.predictedMPH(after: 3).rounded())
        d.updatedAt = .now
        SharedStore.drive = d
        DriveActivityController.shared.update(speed: d.speedMPH, predicted: d.predictedMPH, distanceMiles: Units.miles(fromMeters: currentDrive?.distance ?? 0), elapsed: Int(currentDrive?.elapsed ?? 0))
        WatchBridge.shared.sendSpeed(d.speedMPH)
    }

    private func shareIfDue(_ loc: CLLocation) {
        guard shareEnabled else { return }
        let interval: TimeInterval = isDriving ? 3 : 60
        guard Date.now.timeIntervalSince(lastShare) >= interval else { return }
        lastShare = .now
        let p = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        let speed = speedFilter.speed
        let heading = loc.course >= 0 ? loc.course : nil
        let driving = isDriving
        let vehicle = primaryVehicleID
        Task {
            await RealtimeService.shared.broadcastPosition(p, speed: speed, heading: heading, driving: driving)
            try? await SupabaseService.shared.upsertLiveLocation(p, speed: speed, heading: heading, accuracy: loc.horizontalAccuracy, driving: driving, vehicleID: vehicle)
        }
    }

    /// Overnight dwell samples for home inference — one every 20 minutes between midnight and 5 a.m., only when parked.
    private func sampleHomeIfNight(_ loc: CLLocation) {
        let hour = Calendar.current.component(.hour, from: loc.timestamp)
        guard hour < 5, !isDriving, Date.now.timeIntervalSince(lastHomeSample) > 1200 else { return }
        lastHomeSample = .now
        HomeService.shared.record(HomeSample(time: loc.timestamp, point: GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)))
    }
}

/// Accumulates one drive and uploads it when it ends.
@MainActor
final class DriveRecorder {
    let startedAt = Date()
    let vehicleID: UUID?
    private(set) var points: [GeoPoint] = []
    private(set) var distance: Double = 0
    private(set) var maxSpeed: Double = 0
    private var speedSum = 0.0, speedCount = 0
    private var last: CLLocation?

    init(vehicleID: UUID?) { self.vehicleID = vehicleID }
    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    func add(_ loc: CLLocation, filteredSpeed: Double) {
        if let last, loc.timestamp.timeIntervalSince(last.timestamp) > 0.5 {
            distance += loc.distance(from: last)
        }
        last = loc
        points.append(GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
        maxSpeed = max(maxSpeed, filteredSpeed)
        speedSum += filteredSpeed; speedCount += 1
    }

    func finishAndUpload() async {
        let endedAt = Date()
        guard distance > 200, elapsed > 60 else { return }   // ignore parking-lot shuffles
        let route = Geo.simplify(points, tolerance: 12)
        let avg = speedCount > 0 ? speedSum / Double(speedCount) : nil
        _ = try? await SupabaseService.shared.insertDrive(startedAt: startedAt, endedAt: endedAt, distanceM: distance, durationS: Int(elapsed),
                                                           avg: avg, max: maxSpeed, vehicleID: vehicleID, route: route)
    }
}
