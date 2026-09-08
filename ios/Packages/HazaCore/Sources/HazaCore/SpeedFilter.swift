// Speed smoothing + short-horizon prediction ("62 now · 64 in 3 s").
// A constant-acceleration Kalman filter on [speed, acceleration]; GPS ground speed is the measurement.
import Foundation

public struct SpeedFilter: Sendable {
    public private(set) var speed: Double = 0          // m/s
    public private(set) var acceleration: Double = 0   // m/s²
    private var p00 = 10.0, p01 = 0.0, p10 = 0.0, p11 = 10.0
    private var lastTime: TimeInterval?
    public var processNoise: Double = 0.6              // how quickly acceleration is allowed to change
    public var stationaryThreshold: Double = 0.5       // m/s below which we snap to 0

    public init() {}

    /// Feed one GPS sample. `accuracy` is the reported speed accuracy in m/s (bigger = trust less).
    public mutating func update(measuredSpeed z: Double, accuracy: Double, at time: TimeInterval) {
        let z = max(0, z)
        if let t0 = lastTime {
            let dt = max(0.05, min(10, time - t0))
            // predict
            speed += acceleration * dt
            let q = processNoise * dt
            let n00 = p00 + dt * (p10 + p01) + dt * dt * p11 + q * dt
            let n01 = p01 + dt * p11
            let n10 = p10 + dt * p11
            let n11 = p11 + q
            p00 = n00; p01 = n01; p10 = n10; p11 = n11
        }
        lastTime = time
        // correct
        let r = max(0.25, accuracy * accuracy)
        let s = p00 + r
        let k0 = p00 / s, k1 = p10 / s
        let y = z - speed
        speed += k0 * y
        acceleration += k1 * y
        let q00 = (1 - k0) * p00, q01 = (1 - k0) * p01
        let q10 = p10 - k1 * p00, q11 = p11 - k1 * p01
        p00 = q00; p01 = q01; p10 = q10; p11 = q11
        if speed < stationaryThreshold { speed = 0; acceleration = 0 }
    }

    /// Speed expected `seconds` from the last sample, clamped to ≥ 0 and to a plausible envelope.
    public func predicted(after seconds: Double) -> Double {
        let raw = speed + acceleration * seconds
        return max(0, min(raw, speed * 1.5 + 5))
    }

    public var speedMPH: Double { speed * 2.2369362921 }
    public func predictedMPH(after seconds: Double) -> Double { predicted(after: seconds) * 2.2369362921 }
}

public enum Units {
    public static func mph(fromMetersPerSecond v: Double) -> Double { v * 2.2369362921 }
    public static func kmh(fromMetersPerSecond v: Double) -> Double { v * 3.6 }
    public static func miles(fromMeters m: Double) -> Double { m / 1609.344 }
    public static func formatSpeed(_ mps: Double, metric: Bool) -> String {
        let v = metric ? kmh(fromMetersPerSecond: mps) : mph(fromMetersPerSecond: mps)
        return String(Int(v.rounded()))
    }
}
