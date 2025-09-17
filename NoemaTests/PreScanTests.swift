// PreScanTests.swift
import XCTest
@testable import Noema

final class PreScanTests: XCTestCase {
    func testLoadInstalledScansLayers() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let storeURL = docs.appendingPathComponent("scan_test.json")

        // create simple gguf file with 2 layers
        var data = Data()
        data.append(contentsOf: "GGUF".utf8)
        data.append(UInt32(3).littleEndianData)
        data.append(UInt64(0).littleEndianData)
        data.append(UInt64(1).littleEndianData)
        let key = "hparams.n_layer".data(using: .utf8)!
        data.append(UInt64(key.count).littleEndianData)
        data.append(key)
        data.append(UInt32(4).littleEndianData)
        data.append(UInt32(2).littleEndianData)
        let modelURL = docs.appendingPathComponent("fixture.gguf")
        try data.write(to: modelURL)

        let installed = [InstalledModel(modelID: "foo/bar", quantLabel: "Q4", url: modelURL, format: .gguf, sizeBytes: 0, lastUsed: nil, installDate: Date(), checksum: nil, isFavourite: false, totalLayers: 0, isMultimodal: false, isToolCapable: false)]
        let json = try JSONEncoder().encode(installed)
        try json.write(to: storeURL)

        let store = InstalledModelsStore(filename: "scan_test.json")
        let models = LocalModel.loadInstalled(store: store)
        XCTAssertEqual(models.first?.totalLayers, 2)
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<Self>.size)
    }
}
