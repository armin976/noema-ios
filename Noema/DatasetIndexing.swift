import Foundation

struct DatasetIndexMetadata: Codable, Equatable, Sendable {
    enum SourceLabelMode: String, Codable, Equatable, Sendable {
        case relativePath
    }

    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let sourceLabelMode: SourceLabelMode
    let chunkCount: Int
    let createdAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sourceLabelMode: SourceLabelMode = .relativePath,
        chunkCount: Int,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.sourceLabelMode = sourceLabelMode
        self.chunkCount = chunkCount
        self.createdAt = createdAt
    }

    var isValidReadyIndex: Bool {
        schemaVersion == Self.currentSchemaVersion &&
        sourceLabelMode == .relativePath &&
        chunkCount > 0
    }
}

struct DatasetIndexReport: Codable, Equatable, Sendable {
    var processedFiles: [String]
    var skippedFiles: [String]
    var emptyFiles: [String]
    var failureReason: String?

    static var empty: DatasetIndexReport {
        DatasetIndexReport(
            processedFiles: [],
            skippedFiles: [],
            emptyFiles: [],
            failureReason: nil
        )
    }
}

enum DatasetStorage {
    static let vectorsFilename = "vectors.json"
    static let metadataFilename = "index_metadata.json"
    static let reportFilename = "index_report.json"
    static let extractedFilename = "extracted.txt"
    static let compactFilename = "extracted.compact.txt"
    static let titleFilename = "title.txt"

    static let internalFilenames: Set<String> = [
        vectorsFilename,
        metadataFilename,
        reportFilename,
        extractedFilename,
        compactFilename,
        titleFilename,
    ]

    static func isInternalRelativePath(_ relativePath: String) -> Bool {
        internalFilenames.contains(DatasetPathing.normalizeRelativePath(relativePath))
    }
}

enum DatasetIndexIO {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func vectorsURL(for datasetURL: URL) -> URL {
        datasetURL.appendingPathComponent(DatasetStorage.vectorsFilename)
    }

    static func metadataURL(for datasetURL: URL) -> URL {
        datasetURL.appendingPathComponent(DatasetStorage.metadataFilename)
    }

    static func reportURL(for datasetURL: URL) -> URL {
        datasetURL.appendingPathComponent(DatasetStorage.reportFilename)
    }

    static func extractedURL(for datasetURL: URL) -> URL {
        datasetURL.appendingPathComponent(DatasetStorage.extractedFilename)
    }

    static func compactURL(for datasetURL: URL) -> URL {
        datasetURL.appendingPathComponent(DatasetStorage.compactFilename)
    }

    static func titleURL(for datasetURL: URL) -> URL {
        datasetURL.appendingPathComponent(DatasetStorage.titleFilename)
    }

    static func loadMetadata(from datasetURL: URL) -> DatasetIndexMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: datasetURL)) else { return nil }
        return try? decoder.decode(DatasetIndexMetadata.self, from: data)
    }

    static func loadReport(from datasetURL: URL) -> DatasetIndexReport? {
        guard let data = try? Data(contentsOf: reportURL(for: datasetURL)) else { return nil }
        return try? decoder.decode(DatasetIndexReport.self, from: data)
    }

    static func hasValidIndex(at datasetURL: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vectorsURL(for: datasetURL).path),
              let metadata = loadMetadata(from: datasetURL) else {
            return false
        }
        return metadata.isValidReadyIndex
    }

    static func hasIndexArtifacts(at datasetURL: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: vectorsURL(for: datasetURL).path) ||
            fm.fileExists(atPath: metadataURL(for: datasetURL).path)
    }

    static func writeMetadata(_ metadata: DatasetIndexMetadata, to datasetURL: URL) {
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: metadataURL(for: datasetURL), options: .atomic)
    }

    static func writeReport(_ report: DatasetIndexReport, to datasetURL: URL) {
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: reportURL(for: datasetURL), options: .atomic)
    }

    static func clearReadyIndex(at datasetURL: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: vectorsURL(for: datasetURL))
        try? fm.removeItem(at: metadataURL(for: datasetURL))
    }
}

enum DatasetPathing {
    static func normalizeRelativePath(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { component in
                component != "." && component != ".."
            }
            .map(String.init)
            .joined(separator: "/")
    }

    static func relativePath(for fileURL: URL, under rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            let relative = String(filePath.dropFirst(rootPath.count + 1))
            let normalized = normalizeRelativePath(relative)
            if !normalized.isEmpty {
                return normalized
            }
        }

        let normalized = normalizeRelativePath(fileURL.lastPathComponent)
        return normalized.isEmpty ? "file" : normalized
    }

    static func uniqueRelativePath(_ proposedPath: String, existing: Set<String>) -> String {
        let normalized = normalizeRelativePath(proposedPath)
        let initial = normalized.isEmpty ? "file" : normalized
        let used = Set(existing.map { $0.lowercased() })
        if !used.contains(initial.lowercased()) {
            return initial
        }

        let nsPath = initial as NSString
        let directory = nsPath.deletingLastPathComponent == "." ? "" : nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(suffix))" : "\(stem) (\(suffix)).\(ext)"
            let candidate = directory.isEmpty ? candidateName : directory + "/" + candidateName
            if !used.contains(candidate.lowercased()) {
                return candidate
            }
            suffix += 1
        }
    }

    static func destinationURL(for relativePath: String, in baseURL: URL) -> URL {
        let normalized = normalizeRelativePath(relativePath)
        guard !normalized.isEmpty else { return baseURL.appendingPathComponent("file") }

        var url = baseURL
        for component in normalized.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: false)
        }
        return url
    }

    static func durableArtifactID(forDatasetRelativePath relativePath: String) -> String {
        let normalized = normalizeRelativePath(relativePath)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let escaped = normalized.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? normalized.replacingOccurrences(of: "/", with: "_")
        return "dataset:\(escaped)"
    }
}

enum DatasetTextReader {
    static let encodings: [String.Encoding] = [
        .utf8,
        .isoLatin1,
        .windowsCP1252,
        .utf16,
        .utf32,
    ]

    static func readString(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return string(from: data)
    }

    static func string(from data: Data) -> String? {
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        return nil
    }
}

enum DatasetFileSupport {
    static let supportedExtensions: Set<String> = [
        "pdf",
        "epub",
        "txt",
        "md",
        "json",
        "jsonl",
        "csv",
        "tsv",
    ]

    static func fileExtension(name: String, downloadURL: URL) -> String {
        let nameExt = URL(fileURLWithPath: name).pathExtension.lowercased()
        if !nameExt.isEmpty {
            return nameExt
        }
        return downloadURL.pathExtension.lowercased()
    }

    static func isSupported(name: String, downloadURL: URL) -> Bool {
        supportedExtensions.contains(fileExtension(name: name, downloadURL: downloadURL))
    }

    static func isSupported(_ file: DatasetFile) -> Bool {
        isSupported(name: file.name, downloadURL: file.downloadURL)
    }

    static func totalSupportedSize(files: [DatasetFile]) -> Int64 {
        files.reduce(0) { partial, file in
            partial + (isSupported(file) ? max(0, file.sizeBytes) : 0)
        }
    }
}

struct DatasetRetrievalCandidate<Payload> {
    let score: Float
    let source: String?
    let payload: Payload
}

enum DatasetRetrievalRanker {
    static func select<Payload>(
        _ candidates: [DatasetRetrievalCandidate<Payload>],
        maxChunks: Int,
        minScore: Float
    ) -> [DatasetRetrievalCandidate<Payload>] {
        guard maxChunks > 0, !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return (lhs.source ?? "") < (rhs.source ?? "")
            }
            return lhs.score > rhs.score
        }

        let filtered = sorted.filter { $0.score >= minScore }
        guard !filtered.isEmpty else {
            return sorted.isEmpty ? [] : [sorted[0]]
        }

        var selected: [DatasetRetrievalCandidate<Payload>] = []
        var usedSources = Set<String>()
        var usedIndices = Set<Int>()

        for (index, candidate) in filtered.enumerated() {
            if selected.count >= maxChunks { break }
            let key = candidate.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "<unknown>"
            if usedSources.insert(key).inserted {
                selected.append(candidate)
                usedIndices.insert(index)
            }
        }

        if selected.count < maxChunks {
            for (index, candidate) in filtered.enumerated() where !usedIndices.contains(index) {
                selected.append(candidate)
                if selected.count >= maxChunks { break }
            }
        }

        return selected
    }
}
