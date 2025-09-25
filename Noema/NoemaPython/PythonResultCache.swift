import Foundation
import CryptoKit
import NoemaCore

struct PyRunCacheEntry {
    let key: PyRunKey
    let path: URL
    let meta: PyRunCacheMeta

    var stdout: URL { path.appendingPathComponent("stdout.txt") }
    var stderr: URL { path.appendingPathComponent("stderr.txt") }
    var tables: URL { path.appendingPathComponent("tables.json") }
    var imagesDir: URL { path.appendingPathComponent("images", isDirectory: true) }
    var metaURL: URL { path.appendingPathComponent("meta.json") }

    func loadResult(fileManager: FileManager = .default) throws -> PythonResult {
        do {
            let stdoutString = try String(contentsOf: stdout, encoding: .utf8)
            let stderrString = try String(contentsOf: stderr, encoding: .utf8)

            var tablePayloads: [Data] = []
            if fileManager.fileExists(atPath: tables.path) {
                let tableData = try Data(contentsOf: tables)
                let encoded = try JSONDecoder().decode([String].self, from: tableData)
                tablePayloads = encoded.compactMap { Data(base64Encoded: $0) }
            }

            var imagePayloads: [Data] = []
            if !meta.imageFiles.isEmpty {
                imagePayloads = meta.imageFiles.compactMap { name in
                    let url = imagesDir.appendingPathComponent(name)
                    return try? Data(contentsOf: url)
                }
            }

            var artifacts: [String: Data] = [:]
            for (name, base64) in meta.artifacts {
                if let data = Data(base64Encoded: base64) {
                    artifacts[name] = data
                }
            }
            return PythonResult(stdout: stdoutString,
                                 stderr: stderrString,
                                 tables: tablePayloads,
                                 images: imagePayloads,
                                 artifacts: artifacts)
        } catch {
            throw AppError(code: .cacheCorrupt, message: "Failed to load cached result for \(key.identifier): \(error.localizedDescription)")
        }
    }
}

struct PyRunCacheMeta: Codable {
    let createdAt: Date
    let artifacts: [String: String]
    let imageFiles: [String]
}

protocol ResultCache {
    func lookup(_ key: PyRunKey) -> PyRunCacheEntry?
    func write(_ key: PyRunKey, from result: PythonResult) throws
    func clear() throws
}

final class PythonResultCache: ResultCache {
    static let shared = PythonResultCache()

    private let root: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(root: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let root {
            self.root = root
        } else {
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.root = cacheDir.appendingPathComponent("python", isDirectory: true)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func lookup(_ key: PyRunKey) -> PyRunCacheEntry? {
        let entryURL = directory(for: key)
        guard fileManager.fileExists(atPath: entryURL.path) else { return nil }
        let metaURL = entryURL.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? decoder.decode(PyRunCacheMeta.self, from: data) else {
            return nil
        }
        return PyRunCacheEntry(key: key, path: entryURL, meta: meta)
    }

    func loadCachedResult(for key: PyRunKey) throws -> PythonResult {
        guard let entry = lookup(key) else {
            throw AppError(code: .cacheMiss, message: "No cached result for \(key.identifier)")
        }
        return try entry.loadResult(fileManager: fileManager)
    }

    func write(_ key: PyRunKey, from result: PythonResult) throws {
        let entryURL = directory(for: key)
        if fileManager.fileExists(atPath: entryURL.path) {
            try fileManager.removeItem(at: entryURL)
        }
        try fileManager.createDirectory(at: entryURL, withIntermediateDirectories: true)

        let stdoutURL = entryURL.appendingPathComponent("stdout.txt")
        guard let stdoutData = result.stdout.data(using: .utf8) else {
            throw AppError(code: .cacheCorrupt, message: "Unable to encode stdout as UTF-8")
        }
        try stdoutData.write(to: stdoutURL, options: .atomic)

        let stderrURL = entryURL.appendingPathComponent("stderr.txt")
        guard let stderrData = result.stderr.data(using: .utf8) else {
            throw AppError(code: .cacheCorrupt, message: "Unable to encode stderr as UTF-8")
        }
        try stderrData.write(to: stderrURL, options: .atomic)

        let tableURL = entryURL.appendingPathComponent("tables.json")
        if !result.tables.isEmpty {
            let encodedTables = result.tables.map { $0.base64EncodedString() }
            let tableData = try JSONSerialization.data(withJSONObject: encodedTables, options: [.prettyPrinted])
            try tableData.write(to: tableURL, options: .atomic)
        } else {
            try Data("[]".utf8).write(to: tableURL, options: .atomic)
        }

        var imageFiles: [String] = []
        if !result.images.isEmpty {
            let imagesDir = entryURL.appendingPathComponent("images", isDirectory: true)
            try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for (index, image) in result.images.enumerated() {
                let name = String(format: "image-%02d.png", index)
                let url = imagesDir.appendingPathComponent(name)
                try image.write(to: url, options: .atomic)
                imageFiles.append(name)
            }
        }

        var artifacts: [String: String] = [:]
        for (name, data) in result.artifacts {
            artifacts[name] = data.base64EncodedString()
        }

        let meta = PyRunCacheMeta(createdAt: Date(), artifacts: artifacts, imageFiles: imageFiles)
        let metaData = try encoder.encode(meta)
        let metaURL = entryURL.appendingPathComponent("meta.json")
        try metaData.write(to: metaURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    var rootURL: URL { root }

    private func directory(for key: PyRunKey) -> URL {
        rootURL.appendingPathComponent(key.identifier, isDirectory: true)
    }
}
