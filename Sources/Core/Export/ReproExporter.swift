import Foundation

public protocol NotebookProvider: Sendable {
    func notebookFileURL() async throws -> URL
    func notebookMetadataURL() async throws -> URL?
    func referencedCacheKeys() async -> [String]
    func datasetMounts() async -> [DatasetMount]
    func toolVersions() async -> [ExportManifest.ToolInfo]
    func appVersion() -> String
}

public struct DatasetMount: Sendable, Equatable {
    public var name: String
    public var url: URL
    public var sha256: String?
    public var size: Int64?

    public init(name: String, url: URL, sha256: String? = nil, size: Int64? = nil) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.size = size
    }
}

public actor ReproExporter {
    private let cacheRoot: URL
    private let notebookProvider: NotebookProvider
    private let fileManager: FileManager
    private let dateFormatter: ISO8601DateFormatter
    private let timestampFormatter: DateFormatter

    public init(cacheRoot: URL, notebookProvider: NotebookProvider, fileManager: FileManager = .default) {
        self.cacheRoot = cacheRoot
        self.notebookProvider = notebookProvider
        self.fileManager = fileManager
        self.dateFormatter = ISO8601DateFormatter()
        self.timestampFormatter = DateFormatter()
        self.timestampFormatter.dateFormat = "yyyyMMdd-HHmmss"
        self.timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
    }

    @discardableResult
    public func exportCurrentNotebook(to documentsDirectory: URL) async throws -> URL {
        let timestamp = timestampFormatter.string(from: Date())
        let archiveName = "noema-repro-\(timestamp).zip"
        let archiveURL = documentsDirectory.appendingPathComponent(archiveName)
        let stagingURL = fileManager.temporaryDirectory.appendingPathComponent("noema-repro-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        var warnings: [String] = []
        var filesForZip: [(String, URL)] = []

        // Notebook
        let notebookDestDir = stagingURL.appendingPathComponent("notebook", isDirectory: true)
        try fileManager.createDirectory(at: notebookDestDir, withIntermediateDirectories: true)
        let notebookSource = try await notebookProvider.notebookFileURL()
        let notebookDest = notebookDestDir.appendingPathComponent("notebook.md")
        try copyItemReplacingDestination(from: notebookSource, to: notebookDest)
        filesForZip.append(("notebook/notebook.md", notebookDest))

        var manifestNotebookMeta: String?
        if let metadataURL = try await notebookProvider.notebookMetadataURL() {
            let dest = notebookDestDir.appendingPathComponent("metadata.json")
            try copyItemReplacingDestination(from: metadataURL, to: dest)
            filesForZip.append(("notebook/metadata.json", dest))
            manifestNotebookMeta = "notebook/metadata.json"
        }

        // Caches
        let cacheKeys = Set(await notebookProvider.referencedCacheKeys())
        var cacheRefs: [ExportManifest.CacheRef] = []
        for key in cacheKeys {
            let cacheSourceDir = cacheRoot.appendingPathComponent(key, isDirectory: true)
            guard fileManager.fileExists(atPath: cacheSourceDir.path) else {
                warnings.append("Cache key \(key) missing at \(cacheSourceDir.path)")
                continue
            }
            let cacheDestDir = stagingURL.appendingPathComponent("artifacts", isDirectory: true).appendingPathComponent(key, isDirectory: true)
            try fileManager.createDirectory(at: cacheDestDir, withIntermediateDirectories: true)

            var fileList: [String] = []
            var hashes: [String: String] = [:]

            let expectedFiles = ["stdout.txt", "stderr.txt", "tables.json", "meta.json"]
            for name in expectedFiles {
                let source = cacheSourceDir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: source.path) {
                    let dest = cacheDestDir.appendingPathComponent(name)
                    try copyItemReplacingDestination(from: source, to: dest)
                    let relative = "artifacts/\(key)/\(name)"
                    filesForZip.append((relative, dest))
                    fileList.append(name)
                    hashes[name] = try sha256(for: dest)
                } else {
                    warnings.append("Missing \(name) for cache \(key)")
                }
            }

            let imagesSource = cacheSourceDir.appendingPathComponent("images", isDirectory: true)
            if fileManager.fileExists(atPath: imagesSource.path) {
                let imagesDest = cacheDestDir.appendingPathComponent("images", isDirectory: true)
                try fileManager.createDirectory(at: imagesDest, withIntermediateDirectories: true)
                if let enumerator = fileManager.enumerator(at: imagesSource, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let url as URL in enumerator {
                        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false else { continue }
                        let dest = imagesDest.appendingPathComponent(url.lastPathComponent)
                        try copyItemReplacingDestination(from: url, to: dest)
                        let relative = "artifacts/\(key)/images/\(url.lastPathComponent)"
                        filesForZip.append((relative, dest))
                        fileList.append("images/\(url.lastPathComponent)")
                        hashes["images/\(url.lastPathComponent)"] = try sha256(for: dest)
                    }
                }
            }

            cacheRefs.append(ExportManifest.CacheRef(key: key, files: fileList.sorted(), sha256: hashes))
        }
        cacheRefs.sort { $0.key < $1.key }

        // Datasets
        let mounts = await notebookProvider.datasetMounts()
        var datasetRefs: [ExportManifest.DatasetRef] = []
        for mount in mounts {
            let path = mount.url.path
            var sha = mount.sha256
            var size = mount.size
            if sha == nil || size == nil {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: path)
                    if size == nil, let fileSize = attributes[.size] as? NSNumber {
                        size = fileSize.int64Value
                    }
                    if sha == nil {
                        sha = try sha256(for: mount.url)
                    }
                } catch {
                    warnings.append("Dataset introspection failed for \(mount.name): \(error.localizedDescription)")
                }
            }
            datasetRefs.append(ExportManifest.DatasetRef(name: mount.name, path: path, sha256: sha, size: size))
        }

        // Manifest
        let createdAt = dateFormatter.string(from: Date())
        let appInfo = ExportManifest.AppInfo(appVersion: notebookProvider.appVersion(),
                                             osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        let tools = await notebookProvider.toolVersions()
        let manifest = ExportManifest(createdAt: createdAt,
                                      app: appInfo,
                                      tools: tools,
                                      notebookFile: "notebook/notebook.md",
                                      notebookMetaFile: manifestNotebookMeta,
                                      datasets: datasetRefs,
                                      caches: cacheRefs,
                                      warnings: warnings)
        let manifestURL = stagingURL.appendingPathComponent("MANIFEST.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL)
        filesForZip.append(("MANIFEST.json", manifestURL))

        try ZipWriter.writeZip(at: archiveURL, files: filesForZip)
        try? fileManager.removeItem(at: stagingURL)
        return archiveURL
    }

    private func copyItemReplacingDestination(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256Hasher()
        while true {
            let data = try handle.read(upToCount: 64 * 1024)
            if let data, !data.isEmpty {
                hasher.update(data: data)
            } else {
                break
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
