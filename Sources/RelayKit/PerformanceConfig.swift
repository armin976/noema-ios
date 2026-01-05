import Foundation

public enum RelayPerformanceConfig {
    private static let workerKey = "relay.workerCountOverride"
    private static let logHzKey = "relay.logFlushHzOverride"

    public static func workerCount() -> Int {
        let override = UserDefaults.standard.integer(forKey: workerKey)
        let cpu = ProcessInfo.processInfo.activeProcessorCount
        let defaultWorkers = max(1, min(4, cpu - 1))
        if override > 0 { return min(8, max(1, override)) }
        return defaultWorkers
    }

    public static func logFlushHz() -> Double {
        let overrideInt = UserDefaults.standard.integer(forKey: logHzKey)
        let defaultHz: Double = 5.0
        let hz = overrideInt > 0 ? Double(overrideInt) : defaultHz
        return min(30.0, max(2.0, hz))
    }

    public static func liveFlushInterval() -> TimeInterval {
        1.0 / logFlushHz()
    }

    public static func idleFlushInterval() -> TimeInterval {
        // Slightly slower than live cadence to minimize UI work when not pinned.
        max(0.4, min(1.0, 2.5 / logFlushHz()))
    }
}

