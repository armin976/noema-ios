import Foundation
import NoemaCore

public enum AppEvent: Sendable {
    case datasetMounted(url: URL, sizeBytes: Int64)
    case runFinished(nullPct: Double, madeImages: Bool, dataset: URL?)
    case appBecameActive
    case errorOccurred(code: String, message: String)
}

public actor AutoFlowOrchestrator {
    public static let shared = AutoFlowOrchestrator()

    private let bus: AutoFlowEventBus
    private let engine: AutoFlowEngine
    private let spaceStore: SpaceStore

    public init(bus: AutoFlowEventBus = .shared,
                engine: AutoFlowEngine = AutoFlowEngine.shared,
                spaceStore: SpaceStore = .shared) {
        self.bus = bus
        self.engine = engine
        self.spaceStore = spaceStore
        Task { await self.bootstrapFromActiveSpace() }
    }

    public func post(_ event: AppEvent) async {
        let translated = await translate(event)
        await bus.publish(translated)
    }

    public func stop() async {
        await engine.stop()
    }

    private func translate(_ event: AppEvent) async -> AutoFlowEvent {
        switch event {
        case let .datasetMounted(url, sizeBytes):
            let sizeMB = Double(sizeBytes) / 1_048_576.0
            let dataset = AutoFlowDatasetEvent(url: url, sizeMB: sizeMB)
            return .datasetMounted(dataset)
        case let .runFinished(nullPct, madeImages, dataset):
            let stats = AutoFlowRunEvent.Stats(dataset: dataset,
                                               artifacts: madeImages ? ["images"] : [],
                                               nullPercentage: nullPct,
                                               madeImages: madeImages)
            return .runFinished(AutoFlowRunEvent(stats: stats))
        case .appBecameActive:
            return .appBecameActive
        case let .errorOccurred(code, message):
            let error = AppError(code: AppErrorCode(rawValue: code) ?? .unknown, message: message)
            return .errorOccurred(error)
        }
    }

    private func bootstrapFromActiveSpace() async {
        guard let space = await spaceStore.activeSpace() else { return }
        await updateEngine(for: space)
    }

    private func updateEngine(for space: Space) async {
        let profile = space.settings.autoflowProfile.asEngineProfile
        await engine.updateProfile(profile)
    }
}

extension SpaceSettings.AutoFlowProfileSetting {
    var asEngineProfile: AutoFlowProfile {
        switch self {
        case .off: return .off
        case .balanced: return .balanced
        case .aggressive: return .aggressive
        }
    }
}
