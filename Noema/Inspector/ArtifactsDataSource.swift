import Foundation
import SwiftUI

/// Lightweight helper that surfaces cached Python artifacts for debugging.
struct ArtifactsDataSource {
    struct Entry: Identifiable {
        struct Table: Identifiable {
            let id: Int
            let preview: String
        }

        struct Figure: Identifiable {
            let id: String
            let url: URL
        }

        struct Attachment: Identifiable {
            let id: String
            let data: Data

            var byteCount: Int { data.count }
        }

        let id: String
        let createdAt: Date
        let tables: [Table]
        let figures: [Figure]
        let attachments: [Attachment]

        var formattedDate: String {
            Self.dateFormatter.string(from: createdAt)
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return formatter
        }()
    }

    private let root: URL
    private let fileManager: FileManager

    init(cache: PythonResultCache = .shared, fileManager: FileManager = .default) {
        self.root = cache.rootURL
        self.fileManager = fileManager
    }

    func loadEntries() -> [Entry] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [Entry] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for directory in directories where directory.hasDirectoryPath {
            let metaURL = directory.appendingPathComponent("meta.json")
            guard let metaData = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(PyRunCacheMeta.self, from: metaData) else {
                continue
            }

            let entryID = directory.lastPathComponent
            let tablesURL = directory.appendingPathComponent("tables.json")
            let tables = loadTables(from: tablesURL)
            let figures = loadFigures(in: directory, names: meta.imageFiles)
            let attachments = loadAttachments(from: meta.artifacts)

            entries.append(Entry(
                id: entryID,
                createdAt: meta.createdAt,
                tables: tables,
                figures: figures,
                attachments: attachments
            ))
        }

        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadTables(from url: URL) -> [Entry.Table] {
        guard let data = try? Data(contentsOf: url),
              let encoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return encoded.enumerated().map { index, base64 in
            if let tableData = Data(base64Encoded: base64),
               let text = String(data: tableData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return Entry.Table(id: index, preview: text)
            } else {
                return Entry.Table(id: index, preview: "<binary table #\(index + 1)>")
            }
        }
    }

    private func loadFigures(in directory: URL, names: [String]) -> [Entry.Figure] {
        guard !names.isEmpty else { return [] }
        let imagesDir = directory.appendingPathComponent("images", isDirectory: true)
        return names.compactMap { name in
            let url = imagesDir.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return Entry.Figure(id: name, url: url)
        }
    }

    private func loadAttachments(from artifacts: [String: String]) -> [Entry.Attachment] {
        artifacts.compactMap { key, value in
            guard let data = Data(base64Encoded: value) else { return nil }
            return Entry.Attachment(id: key, data: data)
        }
        .sorted { $0.id < $1.id }
    }
}
