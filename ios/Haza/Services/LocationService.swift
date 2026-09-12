import Foundation
import CoreLocation
import CoreMotion
import UIKit
import Observation
import HazaCore

/// Location, drive detection and position sharing — battery first.
///
/// Two modes:
///  - **Parked**: no GPS at all. Only significant-change updates (cell-tower based, ~500 m) and
///    CLVisits, plus Core Motion's automotive state. Costs about what the phone already spends.
///  - **Driving**: full-rate navigation GPS with a background activity session; Core Motion
///    stays on to notice the stop. Entered when Core Motion says "automotive" (or a coarse fix
///    shows road speed), confirmed by GPS > 6 m/s; left after 4 minutes stationary.
///
/// Sharing: broadcast on Realtime `loc:<uid>` every 3 s while moving (skipped if we moved < 5 m),
/// every 60 s parked; the last-known row in `live_locations` carries battery level too.
/// Below 15 % battery the cadence drops to 30 s and the recorder keeps only every 5th point.
///
/// Driving stats (Wheelz / Enroad / Life360 parity), computed on device from the speed filter and
/// the accelerometer: hard brakes (< −3.5 m/s²), rapid accelerations (> 3.5 m/s²), peak G, best 0–60.
/// Crash heuristic (beta): a > 4 g impact followed by a stop → "Are you OK?" → SOS to friends.
@Observable @MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    enum Mode: String { case parked, driving }

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    private(set) var speedFilter = SpeedFilter()
    private(set) var isDriving = false
    private(set) var mode: Mode = .parked
    private(set) var currentDrive: DriveRecorder?
    private(set) var lastDriveSummary: DriveSummary?          // shown as a "drive complete" moment
    private(set) var possibleCrash: Date?                     // non-nil while "Are you OK?" is pending
    var primaryVehicleID: UUID?
    /// Ghost mode: no broadcast and no live_locations row until this date (server hides the row too).
    var ghostUntil: Date? {
        didSet { if !(ghostUntil.map { $0 > .now } ?? false) { lastShare = .distantPast; if let l = location { shareIfDue(l) } } }
    }
    var shareEnabled: Bool { !(ghostUntil.map { $0 > .now } ?? false) }

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var lastShare = Date.distantPast
    private var lastShared: CLLocation?
    private var lastHomeSample = Date.distantPast
    private var stillSince: Date?
    private var lastAutomotive = Date.distantPast
    private var probeUntil: Date?                             // GPS on briefly to confirm a suspected drive
    private var started = false
    private var lowBattery: Bool { UIDevice.current.batteryLevel >= 0 && UIDevice.current.batteryLevel < 0.15 }

    override private init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: Lifecycle

    /// Idempotent: profile refreshes call this again; a drive in progress must not lose its GPS session.
    func start() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        guard !started else { return }
        started = true
        enterParked()
        startMotion()
    }

    /// Called from the Briefing "Location: Always" row — after When-In-Use is granted.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    private func enterParked() {
        mode = .parked
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.activityType = .other
        if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() }
        manager.startMonitoringVisits()
        backgroundSession?.invalidate(); backgroundSession = nil
        stopMotionSensors()
    }

    private func enterDriving() {
        mode = .driving
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 3
        manager.startUpdatingLocation()
        if authorization == .authorizedAlways { backgroundSession = CLBackgroundActivitySession() }
        startMotionSensors()
    }

    /// A short high-accuracy probe (≤ 40 s) to confirm or dismiss a suspected drive without committing.
    private func probe() {
        guard mode == .parked, probeUntil == nil else { return }
        probeUntil = Date().addingTimeInterval(40)
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.startUpdatingLocation()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(42))
            if self.mode == .parked, self.probeUntil != nil { self.probeUntil = nil; self.manager.stopUpdatingLocation() }
        }
    }

    // MARK: Core Motion

    private func startMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let a = activity else { return }
            let automotive = a.automotive && a.confidence != .low
            let still = a.stationary && a.confidence == .high
            Task { @MainActor [weak self] in
                guard let self else { return }
                if automotive { self.lastAutomotive = .now; self.stillSince = nil; if !self.isDriving { self.probe() } }
                else if still { self.noteStill() }
            }
        }
    }

    private func startMotionSensors() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let dm else { return }
            let a = dm.userAcceleration
            let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            Task { @MainActor [weak self] in self?.currentDrive?.noteG(g); if g > 4 { self?.suspectCrash() } }
        }
    }

    private func stopMotionSensors() {
        if motionManager.isDeviceMotionActive { motionManager.stopDeviceMotionUpdates() }
    }

    // MARK: Drive state

    private func beginDriveIfNeeded(at loc: CLLocation?) {
        guard !isDriving else { return }
        isDriving = true
        stillSince = nil
        probeUntil = nil
        currentDrive = DriveRecorder(vehicleID: primaryVehicleID)
        enterDriving()
        DriveActivityController.shared.start(title: "Drive")
        Haptics.play(.start)
        Task { await RealtimeService.shared.joinMyChannel() }
        if let loc {
            let p = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            Task { try? await SupabaseService.shared.driveEvent("started", at: p) }
        }
        DiscoverEngine.shared.note(.driveStarted)
    }

    private func noteStill() {
        guard isDriving else { return }
        if stillSince == nil { stillSince = .now }
        if let s = stillSince, Date.now.timeIntervalSince(s) > 240 { endDrive() }
    }

    func endDrive() {
        guard isDriving, let recorder = currentDrive else { return }
        isDriving = false
        currentDrive = nil
        enterParked()
        DriveActivityController.shared.end()
        let last = location
        Task {
            let summary = await recorder.finishAndUpload()
            if let summary { self.lastDriveSummary = summary; Haptics.play(.success); DiscoverEngine.shared.note(.driveEnded) }
            if let last {
                try? await SupabaseService.shared.driveEvent("ended", at: GeoPoint(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude))
            }
        }
    }

    // MARK: Crash heuristic (beta)

    private func suspectCrash() {
        guard isDriving, possibleCrash == nil else { return }
        possibleCrash = .now
        Haptics.play(.warning)
        NotificationsService.postLocal(title: "Are you OK?", body: "Haza felt a hard impact. Open the app in the next 45 s or your friends get an SOS with your location.", category: "CRASH")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            guard let since = self.possibleCrash, Date.now.timeIntervalSince(since) >= 44 else { return }
            self.possibleCrash = nil
            if let loc = self.location {
                _ = try? await SupabaseService.shared.sendSOS(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, note: "Possible crash (automatic)")
            }
        }
    }

    /// The user tapped "I'm OK" (or opened the app).
    func dismissCrash() { possibleCrash = nil }

    /// The "drive complete" card was closed.
    func clearSummary() { lastDriveSummary = nil }

    /// Manual stop from the drive card (a long light, a drive-through).
    func stopDriveNow() { endDrive() }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { self.enterParked() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.consume(loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Arrivals/departures at places the user saved (Find My / Life360 style alerts) — cheap, no GPS.
        Task { @MainActor in
            let p = GeoPoint(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
            if visit.departureDate == .distantFuture { await PlacesService.shared.noteArrival(at: p) }
            else { await PlacesService.shared.noteDeparture(at: p) }
        }
    }

    private func consume(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 150 else { return }
        location = loc
        if loc.speed >= 0 {
            speedFilter.update(measuredSpeed: loc.speed, accuracy: loc.speedAccuracy >= 0 ? loc.speedAccuracy : 3, at: loc.timestamp.timeIntervalSince1970)
        }
        // Road speed with a decent fix = a drive, whatever Core Motion thinks (it lags by ~30 s).
        if !isDriving, loc.speed > 6, loc.horizontalAccuracy < 50 { beginDriveIfNeeded(at: loc) }
        if isDriving {
            currentDrive?.add(loc, filteredSpeed: speedFilter.speed, accel: speedFilter.acceleration)
            if loc.speed >= 0, loc.speed < 0.5 { noteStill() } else { stillSince = nil }
        }
        updateSnapshots(loc)
        shareIfDue(loc)
        sampleHomeIfNight(loc)
        Task { await PlacesService.shared.check(GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)) }
    }

    private func updateSnapshots(_ loc: CLLocation) {
        var d = SharedStore.drive
        d.speedMPH = Int(speedFilter.speedMPH.rounded())
        d.predictedMPH = Int(speedFilter.predictedMPH(after: 3).rounded())
        d.updatedAt = .now
        SharedStore.drive = d
        if isDriving {
            DriveActivityController.shared.update(speed: d.speedMPH, predicted: d.predictedMPH, distanceMiles: Units.miles(fromMeters: currentDrive?.distance ?? 0), elapsed: Int(currentDrive?.elapsed ?? 0))
            WatchBridge.shared.sendSpeed(d.speedMPH)
        }
    }

    private func shareIfDue(_ loc: CLLocation) {
        guard shareEnabled else { return }
        var interval: TimeInterval = isDriving ? 3 : 60
        if lowBattery { interval = isDriving ? 30 : 300 }
        guard Date.now.timeIntervalSince(lastShare) >= interval else { return }
        if let prev = lastShared, loc.distance(from: prev) < 5, isDriving { return }   // sitting at a light: nothing new to say
        lastShare = .now; lastShared = loc
        let p = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        let speed = speedFilter.speed
        let heading = loc.course >= 0 ? loc.course : nil
        let driving = isDriving
        let vehicle = primaryVehicleID
        let battery = UIDevice.current.batteryLevel >= 0 ? Int(UIDevice.current.batteryLevel * 100) : nil
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        Task {
            await RealtimeService.shared.broadcastPosition(p, speed: speed, heading: heading, driving: driving)
            try? await SupabaseService.shared.upsertLiveLocation(p, speed: speed, heading: heading, accuracy: loc.horizontalAccuracy, driving: driving, vehicleID: vehicle, battery: battery, charging: charging)
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

/// What a finished drive looked like — the "drive complete" card.
struct DriveSummary: Equatable {
    var id: UUID?
    var distanceM: Double
    var durationS: Int
    var avgMps: Double?
    var maxMps: Double
    var hardBrakes: Int
    var rapidAccels: Int
    var maxG: Double
    var zeroToSixty: Double?
}

/// Accumulates one drive and uploads it when it ends.
@MainActor
final class DriveRecorder {
    let startedAt = Date()
    let vehicleID: UUID?
    private(set) var points: [GeoPoint] = []
    private(set) var distance: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var hardBrakes = 0
    private(set) var rapidAccels = 0
    private(set) var maxG: Double = 0
    private(set) var zeroToSixty: Double?
    private var speedSum = 0.0, speedCount = 0
    private var last: CLLocation?
    private var lastEvent = Date.distantPast
    private var launchStart: TimeInterval?         // for 0–60: time the car was last (nearly) stopped
    private var sampleCounter = 0

    init(vehicleID: UUID?) { self.vehicleID = vehicleID }
    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    func add(_ loc: CLLocation, filteredSpeed: Double, accel: Double) {
        if let last, loc.timestamp.timeIntervalSince(last.timestamp) > 0.5 {
            distance += loc.distance(from: last)
        }
        last = loc
        // Low battery: keep the route, thin the points.
        sampleCounter += 1
        let lowBattery = UIDevice.current.batteryLevel >= 0 && UIDevice.current.batteryLevel < 0.15
        if !lowBattery || sampleCounter % 5 == 0 {
            points.append(GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
        }
        maxSpeed = max(maxSpeed, filteredSpeed)
        speedSum += filteredSpeed; speedCount += 1

        // Events (one per 4 s at most so a single braking episode counts once).
        let now = Date()
        if now.timeIntervalSince(lastEvent) > 4 {
            if accel < -3.5 { hardBrakes += 1; lastEvent = now }
            else if accel > 3.5 { rapidAccels += 1; lastEvent = now }
        }
        // 0–60 mph (26.82 m/s): from < 1 m/s to ≥ 26.82 m/s without dropping below 1 m/s.
        let t = loc.timestamp.timeIntervalSince1970
        if filteredSpeed < 1 { launchStart = t }
        else if let s = launchStart, filteredSpeed >= 26.82 {
            let dt = t - s
            if dt > 2, dt < 30, zeroToSixty.map({ dt < $0 }) ?? true { zeroToSixty = dt }
            launchStart = nil
        }
    }

    func noteG(_ g: Double) { if g > maxG { maxG = g } }

    func finishAndUpload() async -> DriveSummary? {
        let endedAt = Date()
        guard distance > 200, elapsed > 60 else { return nil }   // ignore parking-lot shuffles
        let route = Geo.simplify(points, tolerance: 12)
        let avg = speedCount > 0 ? speedSum / Double(speedCount) : nil
        let id = try? await SupabaseService.shared.insertDrive(startedAt: startedAt, endedAt: endedAt, distanceM: distance, durationS: Int(elapsed),
                                                              avg: avg, max: maxSpeed, vehicleID: vehicleID, route: route,
                                                              hardBrakes: hardBrakes, rapidAccels: rapidAccels, maxG: maxG, zeroToSixty: zeroToSixty)
        return DriveSummary(id: id, distanceM: distance, durationS: Int(elapsed), avgMps: avg, maxMps: maxSpeed,
                            hardBrakes: hardBrakes, rapidAccels: rapidAccels, maxG: maxG, zeroToSixty: zeroToSixty)
    }
}
