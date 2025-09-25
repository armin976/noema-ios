import XCTest
@preconcurrency @testable import NoemaCore

final class ReproExportTests: XCTestCase {
    func testExportBuildsArchiveWithManifest() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let notebookURL = tempDir.appendingPathComponent("notebook.md")
        try "# Title\nprint('hello')".data(using: .utf8)?.write(to: notebookURL)
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        try "{\"cells\":1}".data(using: .utf8)?.write(to: metadataURL)

        let cacheRoot = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let cacheKey = "abc123"
        let cacheDir = cacheRoot.appendingPathComponent(cacheKey, isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try "stdout".data(using: .utf8)?.write(to: cacheDir.appendingPathComponent("stdout.txt"))
        try "stderr".data(using: .utf8)?.write(to: cacheDir.appendingPathComponent("stderr.txt"))
        try Data("[]".utf8).write(to: cacheDir.appendingPathComponent("tables.json"))
        try Data("{}".utf8).write(to: cacheDir.appendingPathComponent("meta.json"))
        let imagesDir = cacheDir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: imagesDir.appendingPathComponent("image-00.png"))

        let datasetURL = tempDir.appendingPathComponent("dataset.csv")
        try "col\n1".data(using: .utf8)?.write(to: datasetURL)

        let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let provider = TestNotebookProvider(
            notebookURL: notebookURL,
            metadataURL: metadataURL,
            cacheKeys: [cacheKey],
            mounts: [DatasetMount(name: "Sample", url: datasetURL)],
            tools: [ExportManifest.ToolInfo(name: "python.execute", version: "1.0.0")],
            appVersionValue: "1.2.3"
        )

        let exporter = ReproExporter(cacheRoot: cacheRoot, notebookProvider: provider)
        let archiveURL = try await exporter.exportCurrentNotebook(to: documents)

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        let entries = try readEntries(from: archiveURL)
        XCTAssertNotNil(entries["notebook/notebook.md"])
        XCTAssertNotNil(entries["notebook/metadata.json"])
        XCTAssertNotNil(entries["artifacts/\(cacheKey)/stdout.txt"])
        XCTAssertNotNil(entries["artifacts/\(cacheKey)/images/image-00.png"])
        XCTAssertNotNil(entries["MANIFEST.json"])
        XCTAssertNil(entries.keys.first(where: { $0.contains("dataset.csv") }))

        let manifestData = try XCTUnwrap(entries["MANIFEST.json"])
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
        XCTAssertEqual(manifest.notebookFile, "notebook/notebook.md")
        XCTAssertEqual(manifest.notebookMetaFile, "notebook/metadata.json")
        XCTAssertEqual(manifest.caches.count, 1)
        XCTAssertEqual(manifest.caches.first?.key, cacheKey)
        XCTAssertTrue(manifest.datasets.contains(where: { $0.path == datasetURL.path }))
        XCTAssertEqual(manifest.app.appVersion, "1.2.3")
        XCTAssertEqual(manifest.tools.first?.version, "1.0.0")
        XCTAssertTrue(manifest.warnings.isEmpty)

        // Hash validation
        let stdoutHash = try sha256(for: cacheDir.appendingPathComponent("stdout.txt"))
        XCTAssertEqual(manifest.caches.first?.sha256["stdout.txt"], stdoutHash)
    }

    func testMissingCacheProducesWarning() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let notebookURL = tempDir.appendingPathComponent("notebook.md")
        try Data("# Test".utf8).write(to: notebookURL)
        let cacheRoot = tempDir.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let provider = TestNotebookProvider(
            notebookURL: notebookURL,
            metadataURL: nil,
            cacheKeys: ["missing"],
            mounts: [],
            tools: [],
            appVersionValue: "1.0"
        )
        let documents = tempDir.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let exporter = ReproExporter(cacheRoot: cacheRoot, notebookProvider: provider)
        let archiveURL = try await exporter.exportCurrentNotebook(to: documents)
        let entries = try readEntries(from: archiveURL)
        let manifestData = try XCTUnwrap(entries["MANIFEST.json"])
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
        XCTAssertEqual(manifest.warnings.count, 1)
        XCTAssertTrue(manifest.caches.isEmpty)
    }

    private func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256Hasher()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024)
            if let chunk, !chunk.isEmpty {
                hasher.update(data: chunk)
            } else {
                break
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct TestNotebookProvider: NotebookProvider {
    let notebookURL: URL
    let metadataURL: URL?
    let cacheKeys: [String]
    let mounts: [DatasetMount]
    let tools: [ExportManifest.ToolInfo]
    let appVersionValue: String

    func notebookFileURL() async throws -> URL { notebookURL }
    func notebookMetadataURL() async throws -> URL? { metadataURL }
    func referencedCacheKeys() async -> [String] { cacheKeys }
    func datasetMounts() async -> [DatasetMount] { mounts }
    func toolVersions() async -> [ExportManifest.ToolInfo] { tools }
    func appVersion() -> String { appVersionValue }
}

private extension ReproExportTests {
    func readEntries(from url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        var offset = 0
        var files: [String: Data] = [:]
        while offset + 4 <= data.count {
            let signature = readUInt32LE(data, offset)
            if signature == 0x04034B50 {
                let nameLength = Int(readUInt16LE(data, offset + 26))
                let extraLength = Int(readUInt16LE(data, offset + 28))
                let compressedSize = Int(readUInt32LE(data, offset + 18))
                let nameStart = offset + 30
                let nameEnd = nameStart + nameLength
                let nameData = data[nameStart..<nameEnd]
                let fileName = String(data: nameData, encoding: .utf8) ?? ""
                let dataStart = nameEnd + extraLength
                let dataEnd = dataStart + compressedSize
                let fileData = data[dataStart..<dataEnd]
                files[fileName] = Data(fileData)
                offset = dataEnd
            } else if signature == 0x02014B50 || signature == 0x06054B50 {
                break
            } else {
                offset += 1
            }
        }
        return files
    }

    func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
