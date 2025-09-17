// LeapURLSanitizationTests.swift
import XCTest
@testable import Noema

final class LeapURLSanitizationTests: XCTestCase {
    func testSanitizesBundlePath() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let bundle = docs.appendingPathComponent("foo.bundle", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let file = bundle.appendingPathComponent("model.pt")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let installed = [InstalledModel(modelID: "foo", quantLabel: "", url: file, format: .slm, sizeBytes: 0, lastUsed: nil, installDate: Date(), checksum: nil, isFavourite: false, totalLayers: 0, isMultimodal: false, isToolCapable: false)]
        let storeURL = docs.appendingPathComponent("leap_test.json")
        let data = try JSONEncoder().encode(installed)
        try data.write(to: storeURL)
        let store = InstalledModelsStore(filename: "leap_test.json")
        let models = LocalModel.loadInstalled(store: store)
        XCTAssertEqual(models.first?.url, bundle)
    }

    func testHandlesFileBundlePath() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let bundle = docs.appendingPathComponent("bar.bundle")
        FileManager.default.createFile(atPath: bundle.path, contents: Data())

        let installed = [InstalledModel(modelID: "bar", quantLabel: "", url: bundle, format: .slm, sizeBytes: 0, lastUsed: nil, installDate: Date(), checksum: nil, isFavourite: false, totalLayers: 0, isMultimodal: false, isToolCapable: false)]
        let storeURL = docs.appendingPathComponent("leap_test_file.json")
        let data = try JSONEncoder().encode(installed)
        try data.write(to: storeURL)
        let store = InstalledModelsStore(filename: "leap_test_file.json")
        let models = LocalModel.loadInstalled(store: store)
        XCTAssertEqual(models.first?.url, bundle)
    }
}
