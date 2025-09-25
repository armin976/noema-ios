import Foundation

public enum FactType: String, Codable, Sendable {
    case goal
    case datasetList
    case schema
    case summary
    case issue
    case metric
    case done
    case error
}

public struct Fact: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var key: String
    public var type: FactType
    public var value: Data
    public var createdAt = Date()
    public var ttlSeconds: Int?

    public init(id: UUID = UUID(), key: String, type: FactType, value: Data, createdAt: Date = Date(), ttlSeconds: Int? = nil) {
        self.id = id
        self.key = key
        self.type = type
        self.value = value
        self.createdAt = createdAt
        self.ttlSeconds = ttlSeconds
    }
}

public enum ArtifactType: String, Codable, Sendable {
    case tableJSON
    case imagePNG
    case markdown
    case json
    case csv
}

public struct ArtifactRef: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var type: ArtifactType
    public var path: String
    public var meta: [String: String]

    public init(id: UUID = UUID(), name: String, type: ArtifactType, path: String, meta: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.meta = meta
    }
}

public enum BlackboardEvent: Codable, Equatable {
    case factUpserted(String)
    case artifactAdded(String)
    case warning(String)
    case error(String)
}

public actor Blackboard {
    private var factsStore: [String: Fact] = [:]
    private var artifactsStore: [String: ArtifactRef] = [:]
    private var eventContinuations: [UUID: AsyncStream<BlackboardEvent>.Continuation] = [:]

    public init() {}

    public func upsertFact(_ fact: Fact) async throws {
        factsStore[fact.key] = fact
        broadcast(.factUpserted(fact.key))
    }

    public func facts(where predicate: (Fact) -> Bool) async -> [Fact] {
        return factsStore.values.filter(predicate)
    }

    public func addArtifact(_ artifact: ArtifactRef) async {
        artifactsStore[artifact.name] = artifact
        broadcast(.artifactAdded(artifact.name))
    }

    public func artifacts(where predicate: (ArtifactRef) -> Bool) async -> [ArtifactRef] {
        artifactsStore.values.filter(predicate)
    }

    public func events() async -> AsyncStream<BlackboardEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.addContinuation(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func addContinuation(_ continuation: AsyncStream<BlackboardEvent>.Continuation, id: UUID) async {
        eventContinuations[id] = continuation
    }

    private func removeContinuation(id: UUID) async {
        eventContinuations.removeValue(forKey: id)
    }

    public func emitWarning(_ message: String) {
        broadcast(.warning(message))
    }

    public func emitError(_ message: String) {
        broadcast(.error(message))
    }

    private func broadcast(_ event: BlackboardEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
}
