import Foundation

public enum AutoFlowProfile: String, CaseIterable, Codable, Sendable {
    case off
    case balanced
    case aggressive
}

public struct AutoFlowToggles: Codable, Equatable, Sendable {
    public var quickEDAOnMount: Bool
    public var cleanOnHighNulls: Bool
    public var plotsOnMissing: Bool

    public init(quickEDAOnMount: Bool = true, cleanOnHighNulls: Bool = true, plotsOnMissing: Bool = true) {
        self.quickEDAOnMount = quickEDAOnMount
        self.cleanOnHighNulls = cleanOnHighNulls
        self.plotsOnMissing = plotsOnMissing
    }
}

public struct AutoFlowPreferences: Sendable, Equatable {
    public var profile: AutoFlowProfile
    public var toggles: AutoFlowToggles
    public var killSwitch: Bool
    public var pausedUntil: Date?

    public init(profile: AutoFlowProfile,
                toggles: AutoFlowToggles,
                killSwitch: Bool,
                pausedUntil: Date?) {
        self.profile = profile
        self.toggles = toggles
        self.killSwitch = killSwitch
        self.pausedUntil = pausedUntil
    }
}

public struct AutoFlowStatus: Sendable, Equatable {
    public enum Phase: Equatable, Sendable {
        case idle
        case evaluating
        case running(description: String)
        case paused(reason: String)
        case blocked
    }

    public var phase: Phase
    public var lastActionAt: Date?

    public init(phase: Phase = .idle, lastActionAt: Date? = nil) {
        self.phase = phase
        self.lastActionAt = lastActionAt
    }
}

public struct AutoFlowAction: Sendable, Equatable {
    public struct Playbook: Sendable, Equatable {
        public let identifier: String
        public let dataset: URL?
        public let parameters: [String: String]
        public let description: String

        public init(identifier: String, dataset: URL?, parameters: [String: String], description: String) {
            self.identifier = identifier
            self.dataset = dataset
            self.parameters = parameters
            self.description = description
        }
    }

    public let playbook: Playbook
    public let cacheKey: String

    public init(playbook: Playbook, cacheKey: String) {
        self.playbook = playbook
        self.cacheKey = cacheKey
    }
}

public enum AutoFlowGuardrailState: Sendable, Equatable {
    case ready
    case rateLimited(until: Date)
    case circuitOpen(until: Date)
    case manuallyPaused(until: Date)
    case disabled
}

public actor AutoFlowState {
    private enum Constants {
        static let rateLimit: TimeInterval = 45
        static let cacheWindow: TimeInterval = 60 * 60 * 24
        static let circuitWindow: TimeInterval = 60 * 3
        static let circuitThreshold = 2
        static let circuitCooldown: TimeInterval = 60 * 10
    }

    private var profile: AutoFlowProfile
    private var toggles: AutoFlowToggles
    private var killSwitch: Bool
    private var pausedUntil: Date?
    private var lastActionAt: Date?
    private var errorTimestamps: [Date] = []
    private var circuitOpenUntil: Date?
    private var cachedActions: [String: Date] = [:]

    public init(profile: AutoFlowProfile = .off,
                toggles: AutoFlowToggles = AutoFlowToggles(),
                killSwitch: Bool = false,
                pausedUntil: Date? = nil) {
        self.profile = profile
        self.toggles = toggles
        self.killSwitch = killSwitch
        self.pausedUntil = pausedUntil
    }

    public func updateProfile(_ profile: AutoFlowProfile) {
        self.profile = profile
    }

    public func updateToggles(_ toggles: AutoFlowToggles) {
        self.toggles = toggles
    }

    public func setKillSwitch(_ enabled: Bool) {
        self.killSwitch = enabled
    }

    public func pause(until date: Date) {
        pausedUntil = date
    }

    public func clearPause() {
        pausedUntil = nil
    }

    public func registerActionSuccess(_ action: AutoFlowAction, at date: Date) {
        lastActionAt = date
        cachedActions[action.cacheKey] = date
        purgeExpiredCache(reference: date)
    }

    public func registerActionFailure(at date: Date) {
        lastActionAt = date
        errorTimestamps.append(date)
        purgeErrorHistory(reference: date)
        if errorTimestamps.count >= Constants.circuitThreshold {
            circuitOpenUntil = date.addingTimeInterval(Constants.circuitCooldown)
            errorTimestamps.removeAll(keepingCapacity: true)
        }
    }

    public func resetCircuit() {
        circuitOpenUntil = nil
        errorTimestamps.removeAll(keepingCapacity: true)
    }

    public func guardrailState(now: Date = Date()) -> AutoFlowGuardrailState {
        if killSwitch || profile == .off {
            return .disabled
        }
        if let pausedUntil, pausedUntil > now {
            return .manuallyPaused(until: pausedUntil)
        }
        if let circuitOpenUntil, circuitOpenUntil > now {
            return .circuitOpen(until: circuitOpenUntil)
        }
        if let lastActionAt, now.timeIntervalSince(lastActionAt) < Constants.rateLimit {
            let until = lastActionAt.addingTimeInterval(Constants.rateLimit)
            return .rateLimited(until: until)
        }
        return .ready
    }

    public func preferences(now: Date = Date()) -> AutoFlowPreferences {
        let pause = (pausedUntil ?? .distantPast) > now ? pausedUntil : nil
        return AutoFlowPreferences(profile: profile,
                                   toggles: toggles,
                                   killSwitch: killSwitch,
                                   pausedUntil: pause)
    }

    public func shouldSkipDueToCache(_ action: AutoFlowAction, now: Date = Date()) -> Bool {
        purgeExpiredCache(reference: now)
        if let cachedAt = cachedActions[action.cacheKey], now.timeIntervalSince(cachedAt) < Constants.cacheWindow {
            return true
        }
        return false
    }

    public func status(now: Date = Date()) -> AutoFlowStatus {
        AutoFlowStatus(phase: .idle, lastActionAt: lastActionAt)
    }

    private func purgeExpiredCache(reference date: Date) {
        cachedActions = cachedActions.filter { date.timeIntervalSince($0.value) < Constants.cacheWindow }
    }

    private func purgeErrorHistory(reference date: Date) {
        errorTimestamps = errorTimestamps.filter { date.timeIntervalSince($0) < Constants.circuitWindow }
    }
}
