// ModelScannerTests.swift
//
//  ModelScannerTests.swift
//  Noema
//
//  Created by Armin Stamate on 20/07/2025.
//


import XCTest
@testable import Noema

final class ModelScannerTests: XCTestCase {
    func testGGUFLayerCount() throws {
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture.gguf")
        try data.write(to: url)
        XCTAssertEqual(ModelScanner.layerCount(for: url, format: .gguf), 2)
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<Self>.size)
    }
}