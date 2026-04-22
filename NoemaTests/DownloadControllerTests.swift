import XCTest
@testable import Noema

final class DownloadControllerTests: XCTestCase {
    func testStagingURLAppendsDownloadExtension() {
        let finalURL = URL(fileURLWithPath: "/tmp/model.gguf")

        XCTAssertEqual(
            DownloadController.stagingURL(for: finalURL),
            URL(fileURLWithPath: "/tmp/model.gguf.download")
        )
    }

    func testAutoResumeIsBlockedWhenLiveTaskExists() {
        XCTAssertTrue(
            DownloadController.shouldBlockAutoResume(
                hasInMemoryTask: false,
                hasLiveTask: true
            )
        )
        XCTAssertTrue(
            DownloadController.shouldBlockAutoResume(
                hasInMemoryTask: true,
                hasLiveTask: false
            )
        )
        XCTAssertFalse(
            DownloadController.shouldBlockAutoResume(
                hasInMemoryTask: false,
                hasLiveTask: false
            )
        )
    }

    func testManualPauseWinsWhenLiveSnapshotIsPresent() {
        XCTAssertEqual(
            DownloadController.stateAfterLiveSnapshot(
                current: .failed,
                manualPause: true
            ),
            .paused
        )
    }

    func testLiveSnapshotPromotesRecoverableStatesToDownloading() {
        XCTAssertEqual(
            DownloadController.stateAfterLiveSnapshot(
                current: .queued,
                manualPause: false
            ),
            .downloading
        )
        XCTAssertEqual(
            DownloadController.stateAfterLiveSnapshot(
                current: .preparing,
                manualPause: false
            ),
            .downloading
        )
        XCTAssertEqual(
            DownloadController.stateAfterLiveSnapshot(
                current: .failed,
                manualPause: false
            ),
            .downloading
        )
        XCTAssertEqual(
            DownloadController.stateAfterLiveSnapshot(
                current: .verifying,
                manualPause: false
            ),
            .verifying
        )
    }

    @MainActor
    func testMultipartCMLSnapshotShowsVisibleProgressAndOverlay() async throws {
        let jobs = await DownloadEngine.shared.snapshots()
        for job in jobs {
            await DownloadEngine.shared.removeJob(externalID: job.externalID)
        }

        let controller = DownloadController()
        let modelID = "noema/tests/cml-\(UUID().uuidString)"
        let externalID = "\(modelID)-CML"
        let partA = QuantInfo.DownloadPart(
            path: "bundle/model.mlmodelc/weights.bin",
            sizeBytes: 8_192,
            sha256: nil,
            downloadURL: URL(string: "https://example.com/bundle/model.mlmodelc/weights.bin")!
        )
        let partB = QuantInfo.DownloadPart(
            path: "bundle/tokenizer/vocab.json",
            sizeBytes: 4_096,
            sha256: nil,
            downloadURL: URL(string: "https://example.com/bundle/tokenizer/vocab.json")!
        )
        let quant = QuantInfo(
            label: "CML",
            format: .ane,
            sizeBytes: 12_288,
            downloadURL: partA.downloadURL,
            sha256: nil,
            configURL: nil,
            downloadParts: [partA, partB]
        )
        let detail = ModelDetails(
            id: modelID,
            summary: "Multipart CML test",
            quants: [quant],
            promptTemplate: nil
        )
        let baseDir = InstalledModelsStore.baseDir(for: .ane, modelID: modelID)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let artifacts = quant.allRelativeDownloadPaths.map { relativePath in
            let finalURL = baseDir.appendingPathComponent(relativePath)
            return DownloadArtifact(
                id: "shard:\(relativePath)",
                role: .weightShard,
                remoteURL: nil,
                stagingURL: DownloadController.stagingURL(for: finalURL),
                finalURL: finalURL,
                expectedBytes: relativePath.contains("weights") ? 8_192 : 4_096,
                downloadedBytes: 0,
                checksum: nil,
                state: .preparing,
                retryCount: 0,
                nextRetryAt: nil,
                lastErrorDescription: nil,
                manualPause: false
            )
        }

        _ = await DownloadEngine.shared.upsertJob(
            owner: .model(ModelDownloadOwner(detail: detail, quant: quant)),
            artifacts: artifacts,
            state: .preparing
        )
        await DownloadEngine.shared.updateArtifactProgress(
            externalID: externalID,
            artifactID: artifacts[0].id,
            written: 4_096,
            expected: 8_192
        )
        await Task.yield()
        await Task.yield()

        let item = try XCTUnwrap(controller.items.first(where: { $0.id == externalID }))
        XCTAssertEqual(item.status, .downloading)
        XCTAssertGreaterThan(item.progress, 0)
        XCTAssertGreaterThan(controller.overallProgress, 0)
        XCTAssertTrue(controller.showOverlay)

        await DownloadEngine.shared.removeJob(externalID: externalID)
    }
}
