import XCTest
import CryptoKit
@testable import Noema

final class InspectorTests: XCTestCase {
    func testDatasetHashingProducesStableDigest() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let datasetsDir = tempRoot.appendingPathComponent("Datasets", isDirectory: true)
        try fm.createDirectory(at: datasetsDir, withIntermediateDirectories: true)
        let fileURL = datasetsDir.appendingPathComponent("sample.csv")
        let contents = "a,b\n1,2\n3,4\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = DatasetIndexStore(documentsURL: tempRoot)
        let listed = await store.listMounted()
        XCTAssertEqual(listed.count, 1)
        guard let info = listed.first else { return }
        let hash = try await store.computeHash(for: info.url)
        XCTAssertEqual(hash, expectedSHA256(for: contents))
    }

    func testCacheIndexOrdersNewestFirst() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let pythonRoot = tempRoot.appendingPathComponent("python", isDirectory: true)
        try fm.createDirectory(at: pythonRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let olderKey = pythonRoot.appendingPathComponent("older")
        try fm.createDirectory(at: olderKey, withIntermediateDirectories: true)
        let olderImages = olderKey.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: olderImages, withIntermediateDirectories: true)
        let olderImage = olderImages.appendingPathComponent("figure.png")
        try Data(count: 10).write(to: olderImage)
        let olderMeta = """
{"createdAt":"\(formatter.string(from: Date(timeIntervalSince1970: 10)))","artifacts":{},"imageFiles":["figure.png","note.txt"]}
"""
        try olderMeta.data(using: .utf8)?.write(to: olderKey.appendingPathComponent("meta.json"))

        let newerKey = pythonRoot.appendingPathComponent("newer")
        try fm.createDirectory(at: newerKey, withIntermediateDirectories: true)
        let newerImages = newerKey.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: newerImages, withIntermediateDirectories: true)
        let newerImage = newerImages.appendingPathComponent("plot.png")
        try Data(count: 12).write(to: newerImage)
        let newerMeta = """
{"createdAt":"\(formatter.string(from: Date(timeIntervalSince1970: 20)))","artifacts":{},"imageFiles":["plot.png","README.md"]}
"""
        try newerMeta.data(using: .utf8)?.write(to: newerKey.appendingPathComponent("meta.json"))

        let index = CacheIndex(cachesURL: tempRoot)
        let items = await index.listFigures()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map { $0.name }, ["plot.png", "figure.png"])
        XCTAssertEqual(Set(items.map { $0.key }), ["older", "newer"])
    }

    private func expectedSHA256(for string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
