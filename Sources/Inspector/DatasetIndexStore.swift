import Foundation
import CryptoKit

public struct DatasetInfo: Codable, Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var name: String
    public var size: Int64
    public var mtime: Date
    public var sha256: String?
    public var rows: Int?
    public var cols: Int?
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                url: URL,
                name: String,
                size: Int64,
                mtime: Date,
                sha256: String? = nil,
                rows: Int? = nil,
                cols: Int? = nil,
                updatedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.mtime = mtime
        self.sha256 = sha256
        self.rows = rows
        self.cols = cols
        self.updatedAt = updatedAt
    }
}

public actor DatasetIndexStore {
    private let fileManager: FileManager
    private let root: URL
    private let datasetRoot: URL
    private let indexURL: URL
    private var cached: [String: DatasetInfo] = [:]

    public init(fileManager: FileManager = .default, documentsURL: URL? = nil) {
        self.fileManager = fileManager
        if let documentsURL {
            self.root = documentsURL.appendingPathComponent("DatasetIndex", isDirectory: true)
            self.datasetRoot = documentsURL.appendingPathComponent("Datasets", isDirectory: true)
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.root = docs.appendingPathComponent("DatasetIndex", isDirectory: true)
            self.datasetRoot = docs.appendingPathComponent("Datasets", isDirectory: true)
        }
        self.indexURL = root.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func load() async -> [DatasetInfo] {
        if cached.isEmpty {
            await loadFromDisk()
        }
        return cached.values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    @discardableResult
    public func listMounted() async -> [DatasetInfo] {
        await loadFromDisk()
        guard fileManager.fileExists(atPath: datasetRoot.path) else { return [] }

        var newMap: [String: DatasetInfo] = [:]
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        if let enumerator = fileManager.enumerator(at: datasetRoot,
                                                   includingPropertiesForKeys: resourceKeys,
                                                   options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                do {
                    let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    guard values.isRegularFile == true else { continue }
                    let size = Int64(values.fileSize ?? 0)
                    let mtime = values.contentModificationDate ?? Date()
                    let key = fileURL.path
                    let existing = cached[key]
                    var info = existing ?? DatasetInfo(url: fileURL,
                                                        name: fileURL.lastPathComponent,
                                                        size: size,
                                                        mtime: mtime)
                    if existing == nil {
                        info.url = fileURL
                        info.name = fileURL.lastPathComponent
                    }
                    if existing?.mtime != mtime || existing?.size != size {
                        info.sha256 = nil
                        info.rows = nil
                        info.cols = nil
                    }
                    info.size = size
                    info.mtime = mtime
                    info.updatedAt = Date()
                    newMap[key] = info
                } catch {
                    continue
                }
            }
        }
        cached = newMap
        await persist()
        return cached.values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    public func upsert(_ info: DatasetInfo) async {
        await loadFromDisk()
        cached[info.url.path] = info
        await persist()
    }

    public func computeHash(for url: URL) async throws -> String {
        var hasher = SHA256()
        guard let stream = InputStream(url: url) else {
            throw NSError(domain: "DatasetIndexStore", code: -10, userInfo: [NSLocalizedDescriptionKey: "Unable to open file for hashing"])
        }
        stream.open()
        defer { stream.close() }
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw stream.streamError ?? NSError(domain: NSCocoaErrorDomain, code: -11, userInfo: nil)
            }
            if read == 0 { break }
            hasher.update(buffer: UnsafeRawBufferPointer(start: buffer, count: read))
        }
        let digest = hasher.finalize()
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return hash
    }

    @discardableResult
    private func loadFromDisk() async -> [String: DatasetInfo] {
        if cached.isEmpty,
           fileManager.fileExists(atPath: indexURL.path),
           let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: DatasetInfo].self, from: data) {
            cached = decoded
        }
        return cached
    }

    private func persist() async {
        guard !cached.isEmpty else {
            try? fileManager.removeItem(at: indexURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cached) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}

public extension DatasetIndexStore {
    func relativePath(for url: URL) -> String? {
        let basePath = datasetRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return nil }
        var relative = String(path.dropFirst(basePath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }
}
