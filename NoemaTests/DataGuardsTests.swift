import XCTest
@testable import AutoFlow

final class DataGuardsTests: XCTestCase {
    func testGuardReportTriggersCleanEvent() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let csv = "col1,col2\n1,\n,2\n,\n,5\n6,7\n"
        let datasetURL = tempDir.appendingPathComponent("sample.csv")
        try csv.write(to: datasetURL, atomically: true, encoding: .utf8)

        let bus = AutoFlowEventBus()
        let engine = DataGuardEngine(eventBus: bus, fileManager: fm)

        let eventTask = Task { () -> AutoFlowRunEvent? in
            let stream = await bus.subscribe()
            for await event in stream {
                if case let .runFinished(run) = event { return run }
            }
            return nil
        }

        let metrics = try await engine.run(on: datasetURL, madeImages: false)
        XCTAssertGreaterThan(metrics.nullPercentage, 0.3)
        let reportURL = datasetURL.deletingLastPathComponent().appendingPathComponent("GuardReport.md")
        XCTAssertTrue(fm.fileExists(atPath: reportURL.path))

        let runEvent = await eventTask.value
        guard let stats = runEvent?.stats else {
            XCTFail("Missing AutoFlow stats")
            return
        }
        XCTAssertEqual(stats.dataset, datasetURL)
        XCTAssertEqual(stats.nullPercentage, metrics.nullPercentage, accuracy: 0.0001)
    }
}
