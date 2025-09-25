import Foundation

public struct FigureItem: Identifiable, Equatable {
    public let id: UUID
    public let key: String
    public let name: String
    public let url: URL
    public let createdAt: Date

    public init(id: UUID = UUID(), key: String, name: String, url: URL, createdAt: Date) {
        self.id = id
        self.key = key
        self.name = name
        self.url = url
        self.createdAt = createdAt
    }
}

public actor CacheIndex {
    private let fileManager: FileManager
    private let root: URL
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default, cachesURL: URL? = nil) {
        self.fileManager = fileManager
        if let cachesURL {
            self.root = cachesURL.appendingPathComponent("python", isDirectory: true)
        } else {
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.root = cacheDir.appendingPathComponent("python", isDirectory: true)
        }
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func listFigures(limit: Int = 200) async -> [FigureItem] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let entries = try? fileManager.contentsOfDirectory(at: root,
                                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                                 options: options) else { return [] }
        var items: [FigureItem] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let metaURL = entry.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(PyRunCacheMeta.self, from: data) else { continue }
            let imagesDir = entry.appendingPathComponent("images", isDirectory: true)
            for name in meta.imageFiles where name.lowercased().hasSuffix(".png") {
                let fileURL = imagesDir.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                items.append(FigureItem(key: entry.lastPathComponent,
                                        name: name,
                                        url: fileURL,
                                        createdAt: meta.createdAt))
            }
        }
        items.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.name < rhs.name
            }
            return lhs.createdAt > rhs.createdAt
        }
        if items.count > limit { items = Array(items.prefix(limit)) }
        return items
    }
}

private struct PyRunCacheMeta: Codable {
    let createdAt: Date
    let artifacts: [String: String]
    let imageFiles: [String]
}
