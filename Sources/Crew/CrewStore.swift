import Foundation

public struct CrewRunEvent: Codable, Sendable {
    public let timestamp: Date
    public let task: ProposedTask
    public let messages: [String]
    public let outcome: TaskRuntime.Outcome

    public init(timestamp: Date = Date(), task: ProposedTask, messages: [String], outcome: TaskRuntime.Outcome) {
        self.timestamp = timestamp
        self.task = task
        self.messages = messages
        self.outcome = outcome
    }
}

public actor CrewStore {
    public nonisolated let runID: UUID
    private let rootURL: URL
    private let eventsURL: URL
    private let artifactsURL: URL
    private let fileManager: FileManager

    public init(runID: UUID = UUID(), baseURL: URL? = nil, fileManager: FileManager = .default) {
        self.runID = runID
        self.fileManager = fileManager
        let base = baseURL ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let root = base.appendingPathComponent("CrewRuns").appendingPathComponent(runID.uuidString, isDirectory: true)
        self.rootURL = root
        self.eventsURL = root.appendingPathComponent("events.jsonl")
        self.artifactsURL = root.appendingPathComponent("artifacts", isDirectory: true)
        try? fileManager.createDirectory(at: self.artifactsURL, withIntermediateDirectories: true, attributes: nil)
    }

    public func persist(contract: PlanContract) async {
        let contractURL = rootURL.appendingPathComponent("contract.json")
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONEncoder().encode(contract)
            try data.write(to: contractURL)
        } catch {
            #if DEBUG
            print("[CrewStore] persist contract error: \(error)")
            #endif
        }
    }

    public func append(event: CrewRunEvent) async {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
            let line = try JSONEncoder().encode(event)
            if !fileManager.fileExists(atPath: eventsURL.path) {
                _ = fileManager.createFile(atPath: eventsURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: eventsURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(line)
            handle.write(Data("\n".utf8))
        } catch {
            #if DEBUG
            print("[CrewStore] append error: \(error)")
            #endif
        }
    }

    public func registerArtifact(_ artifact: ArtifactRef, data: Data) async throws -> URL {
        try fileManager.createDirectory(at: artifactsURL, withIntermediateDirectories: true, attributes: nil)
        let destination = artifactsURL.appendingPathComponent(artifact.name)
        try data.write(to: destination)
        return destination
    }
}
