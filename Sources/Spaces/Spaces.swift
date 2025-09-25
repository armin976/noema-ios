import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
import NoemaCore

public struct URLBookmark: Codable, Equatable, Hashable, Sendable {
    public var identifier: UUID
    public var url: URL

    public init(identifier: UUID = UUID(), url: URL) {
        self.identifier = identifier
        self.url = url
    }
}

public struct SpaceSettings: Codable, Equatable, Sendable {
    public enum AutoFlowProfileSetting: String, CaseIterable, Codable, Sendable {
        case off = "Off"
        case balanced = "Balanced"
        case aggressive = "Aggressive"

        public init(rawValue: String) {
            switch rawValue.lowercased() {
            case "off": self = .off
            case "aggressive": self = .aggressive
            default: self = .balanced
            }
        }

        public var displayName: String { rawValue }
    }

    public var autoflowProfile: AutoFlowProfileSetting
    public var guardNullPct: Double

    public init(autoflowProfile: AutoFlowProfileSetting = .balanced, guardNullPct: Double = 0.3) {
        self.autoflowProfile = autoflowProfile
        self.guardNullPct = guardNullPct
    }
}

public struct Space: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var bookmarks: [URLBookmark]
    public var settings: SpaceSettings

    public init(id: UUID = UUID(),
                name: String,
                createdAt: Date = Date(),
                bookmarks: [URLBookmark] = [],
                settings: SpaceSettings = SpaceSettings()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.bookmarks = bookmarks
        self.settings = settings
    }
}

#if canImport(SwiftUI)
@MainActor
private final class ActiveSpaceDefaults: ObservableObject {
    @AppStorage("activeSpaceId") var activeSpaceId: String

    init(store: UserDefaults) {
        _activeSpaceId = AppStorage(wrappedValue: "", "activeSpaceId", store: store)
    }
}
#else
private final class ActiveSpaceDefaults {
    private let store: UserDefaults

    init(store: UserDefaults) {
        self.store = store
    }

    var activeSpaceId: String {
        get { store.string(forKey: "activeSpaceId") ?? "" }
        set { store.set(newValue, forKey: "activeSpaceId") }
    }
}
#endif

public actor SpaceStore {
    public static let shared = SpaceStore()

    private let fileManager: FileManager
    private let documentsURL: URL
    private let defaults: ActiveSpaceDefaults
    private var spaces: [UUID: Space] = [:]
    private var spaceContinuations: [UUID: AsyncStream<[Space]>.Continuation] = [:]
    private var activeContinuations: [UUID: AsyncStream<Space?>.Continuation] = [:]
    private var hasLoadedFromDisk = false

    public init(fileManager: FileManager = .default,
                documentsURL: URL? = nil,
                userDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        if let documentsURL {
            self.documentsURL = documentsURL
        } else {
            self.documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        self.defaults = ActiveSpaceDefaults(store: userDefaults)
        Task { await bootstrap() }
    }

    deinit {
        for continuation in spaceContinuations.values {
            continuation.finish()
        }
        for continuation in activeContinuations.values {
            continuation.finish()
        }
    }

    public func loadAll() async -> [Space] {
        if !hasLoadedFromDisk {
            await loadFromDisk()
        }
        return orderedSpaces()
    }

    public func activeSpace() async -> Space? {
        if !hasLoadedFromDisk {
            await loadFromDisk()
        }
        guard let id = await activeSpaceIdentifier(), let uuid = UUID(uuidString: id) else {
            return orderedSpaces().first
        }
        return spaces[uuid] ?? orderedSpaces().first
    }

    public func create(name: String) async throws -> Space {
        await ensureLoaded()
        var candidate = Space(name: name)
        while spaces.keys.contains(candidate.id) {
            candidate.id = UUID()
        }
        try createDirectories(for: candidate.id)
        try persist(space: candidate)
        spaces[candidate.id] = candidate
        await persistActiveIfNeeded(for: candidate)
        notifyObservers()
        return candidate
    }

    public func rename(id: UUID, name: String) async throws {
        await ensureLoaded()
        guard var space = spaces[id] else { throw AppError(code: .unknown, message: "Space not found") }
        space.name = name
        spaces[id] = space
        try persist(space: space)
        notifyObservers()
    }

    public func updateSettings(for id: UUID, settings: SpaceSettings) async throws {
        await ensureLoaded()
        guard var space = spaces[id] else { throw AppError(code: .unknown, message: "Space not found") }
        space.settings = settings
        spaces[id] = space
        try persist(space: space)
        notifyObservers()
    }

    public func switchTo(_ id: UUID) async throws {
        await ensureLoaded()
        guard spaces[id] != nil else { throw AppError(code: .unknown, message: "Space not found") }
        await setActiveSpaceIdentifier(id.uuidString)
        notifyObservers()
    }

    public func archive(id: UUID) async throws -> URL {
        await ensureLoaded()
        guard spaces[id] != nil else { throw AppError(code: .unknown, message: "Space not found") }
        let spaceURL = directory(for: id)
        let archiveURL = spaceURL.deletingLastPathComponent().appendingPathComponent("\(id.uuidString).zip")
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        #if os(iOS) || os(macOS)
        try fileManager.zipItem(at: spaceURL, to: archiveURL)
        return archiveURL
        #else
        throw AppError(code: .exportFailed, message: "Zip not supported on this platform")
        #endif
    }

    public func spacesStream() async -> AsyncStream<[Space]> {
        await ensureLoaded()
        return AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSpaceContinuation(id) }
            }
            storeSpaceContinuation(continuation, id: id)
            continuation.yield(self.orderedSpaces())
        }
    }

    public func activeSpaceStream() async -> AsyncStream<Space?> {
        await ensureLoaded()
        return AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeActiveContinuation(id) }
            }
            storeActiveContinuation(continuation, id: id)
            Task {
                let value = await self.activeSpace()
                continuation.yield(value)
            }
        }
    }

    public func activeGuardThreshold() async -> Double {
        if let space = await activeSpace() {
            return space.settings.guardNullPct
        }
        return 0.3
    }

    public func activeProfileSetting() async -> SpaceSettings.AutoFlowProfileSetting {
        if let space = await activeSpace() {
            return space.settings.autoflowProfile
        }
        return .off
    }

    private func bootstrap() async {
        await ensureLoaded()
        if spaces.isEmpty {
            let defaultSpace = Space(name: "Default Space")
            do {
                try createDirectories(for: defaultSpace.id)
                try persist(space: defaultSpace)
                spaces[defaultSpace.id] = defaultSpace
                await setActiveSpaceIdentifier(defaultSpace.id.uuidString)
                notifyObservers()
            } catch {
                print("[SpaceStore] Failed bootstrap: \(error.localizedDescription)")
            }
        }
    }

    private func ensureLoaded() async {
        if !hasLoadedFromDisk {
            await loadFromDisk()
        }
    }

    private func loadFromDisk() async {
        hasLoadedFromDisk = true
        let root = spacesRoot()
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        var discovered: [UUID: Space] = [:]
        if let contents = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in contents where url.hasDirectoryPath {
                let jsonURL = url.appendingPathComponent("space.json")
                guard let data = try? Data(contentsOf: jsonURL) else { continue }
                do {
                    let decoded = try JSONDecoder().decode(Space.self, from: data)
                    discovered[decoded.id] = decoded
                } catch {
                    print("[SpaceStore] Failed decoding space: \(error.localizedDescription)")
                }
            }
        }
        spaces = discovered
        notifyObservers()
    }

    private func orderedSpaces() -> [Space] {
        spaces.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func createDirectories(for id: UUID) throws {
        let dir = directory(for: id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let notebookDir = dir.appendingPathComponent("notebooks", isDirectory: true)
        let artifactsDir = dir.appendingPathComponent("artifacts", isDirectory: true)
        let exportsDir = dir.appendingPathComponent("exports", isDirectory: true)
        try fileManager.createDirectory(at: notebookDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)
    }

    private func persist(space: Space) throws {
        let url = directory(for: space.id).appendingPathComponent("space.json")
        let data = try JSONEncoder().encode(space)
        try data.write(to: url, options: [.atomic])
    }

    private func spacesRoot() -> URL {
        documentsURL.appendingPathComponent("Spaces", isDirectory: true)
    }

    private func directory(for id: UUID) -> URL {
        spacesRoot().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func notifyObservers() {
        let ordered = orderedSpaces()
        for continuation in spaceContinuations.values {
            continuation.yield(ordered)
        }
        Task { await notifyActiveObservers() }
    }

    private func notifyActiveObservers() async {
        let active = await activeSpace()
        for continuation in activeContinuations.values {
            continuation.yield(active)
        }
    }

    private func storeSpaceContinuation(_ continuation: AsyncStream<[Space]>.Continuation, id: UUID) {
        spaceContinuations[id] = continuation
    }

    private func removeSpaceContinuation(_ id: UUID) {
        spaceContinuations[id] = nil
    }

    private func storeActiveContinuation(_ continuation: AsyncStream<Space?>.Continuation, id: UUID) {
        activeContinuations[id] = continuation
    }

    private func removeActiveContinuation(_ id: UUID) {
        activeContinuations[id] = nil
    }

    private func activeSpaceIdentifier() async -> String? {
        #if canImport(SwiftUI)
        await MainActor.run { defaults.activeSpaceId }
        #else
        defaults.activeSpaceId
        #endif
    }

    private func persistActiveIfNeeded(for space: Space) async {
        if let active = await activeSpaceIdentifier(), active.isEmpty {
            await setActiveSpaceIdentifier(space.id.uuidString)
        }
    }

    private func setActiveSpaceIdentifier(_ value: String) async {
        #if canImport(SwiftUI)
        await MainActor.run { defaults.activeSpaceId = value }
        #else
        defaults.activeSpaceId = value
        #endif
    }
}
