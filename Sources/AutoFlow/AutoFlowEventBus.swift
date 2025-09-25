import Foundation
import NoemaCore

public enum AutoFlowEvent: Sendable {
    case datasetMounted(AutoFlowDatasetEvent)
    case runFinished(AutoFlowRunEvent)
    case appBecameActive
    case errorOccurred(AppError)
}

public struct AutoFlowDatasetEvent: Sendable {
    public let url: URL
    public let sizeMB: Double

    public init(url: URL, sizeMB: Double) {
        self.url = url
        self.sizeMB = sizeMB
    }
}

public struct AutoFlowRunEvent: Sendable {
    public struct Stats: Sendable {
        public let dataset: URL?
        public let artifacts: [String]
        public let nullPercentage: Double
        public let madeImages: Bool

        public init(dataset: URL?, artifacts: [String], nullPercentage: Double, madeImages: Bool) {
            self.dataset = dataset
            self.artifacts = artifacts
            self.nullPercentage = nullPercentage
            self.madeImages = madeImages
        }
    }

    public let stats: Stats

    public init(stats: Stats) {
        self.stats = stats
    }
}

public actor AutoFlowEventBus {
    public static let shared = AutoFlowEventBus()

    private var continuations: [UUID: AsyncStream<AutoFlowEvent>.Continuation] = [:]

    public init() {}

    public func publish(_ event: AutoFlowEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func subscribe() -> AsyncStream<AutoFlowEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [id] _ in
                Task { await self.removeContinuation(id) }
            }
            storeContinuation(continuation, id: id)
        }
    }

    private func storeContinuation(_ continuation: AsyncStream<AutoFlowEvent>.Continuation, id: UUID) {
        continuations[id] = continuation
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
