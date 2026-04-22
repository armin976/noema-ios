import XCTest
@testable import Noema

final class BackgroundDownloadManagerTests: XCTestCase {
    func testTaskSnapshotIncludesResumeOffsetInWrittenTotal() {
        let snapshot = BackgroundDownloadManager.makeTaskSnapshot(
            jobID: "job-1",
            artifactID: "artifact-1",
            destination: URL(fileURLWithPath: "/tmp/model.gguf"),
            resumeOffset: 4_000,
            bytesReceived: 2_000,
            taskExpected: 6_000,
            recordedExpected: 10_000,
            hasLiveTask: true
        )

        XCTAssertEqual(snapshot.jobID, "job-1")
        XCTAssertEqual(snapshot.artifactID, "artifact-1")
        XCTAssertEqual(snapshot.resumeOffset, 4_000)
        XCTAssertEqual(snapshot.bytesReceived, 2_000)
        XCTAssertEqual(snapshot.writtenTotal, 6_000)
        XCTAssertEqual(snapshot.fullExpected, 10_000)
        XCTAssertTrue(snapshot.hasLiveTask)
    }

    func testTaskSnapshotPreservesRecordedExpectedWhenResumeTaskReportsRemainingBytes() {
        let snapshot = BackgroundDownloadManager.makeTaskSnapshot(
            jobID: "job-2",
            artifactID: "artifact-2",
            destination: URL(fileURLWithPath: "/tmp/model-part.gguf"),
            resumeOffset: 4_000,
            bytesReceived: 1_000,
            taskExpected: 6_000,
            recordedExpected: 10_000,
            hasLiveTask: true
        )

        XCTAssertEqual(snapshot.writtenTotal, 5_000)
        XCTAssertEqual(snapshot.fullExpected, 10_000)
        XCTAssertEqual(snapshot.taskExpectedBytes, 6_000)
        XCTAssertEqual(snapshot.recordedExpectedBytes, 10_000)
    }

    func testNormalizeProgressUsesTaskExpectedForFreshDownloads() {
        let result = BackgroundDownloadManager.normalizeProgressTotals(
            resumeOffset: 0,
            totalBytesWritten: 256,
            taskExpected: 1024,
            recordedExpected: 2048
        )

        XCTAssertEqual(result.writtenTotal, 256)
        XCTAssertEqual(result.fullExpected, 1024)
        XCTAssertEqual(result.mode, .freshTask)
    }

    func testNormalizeProgressTreatsApproximateResumeExpectedAsFullSize() {
        let result = BackgroundDownloadManager.normalizeProgressTotals(
            resumeOffset: 4_000,
            totalBytesWritten: 2_000,
            taskExpected: 10_050,
            recordedExpected: 10_000
        )

        XCTAssertEqual(result.writtenTotal, 6_000)
        XCTAssertEqual(result.fullExpected, 10_000)
        XCTAssertEqual(result.mode, .resumeFullSize)
    }

    func testNormalizeProgressTreatsSmallerResumeExpectedAsRemainingBytes() {
        let result = BackgroundDownloadManager.normalizeProgressTotals(
            resumeOffset: 4_000,
            totalBytesWritten: 2_000,
            taskExpected: 6_000,
            recordedExpected: 10_000
        )

        XCTAssertEqual(result.writtenTotal, 6_000)
        XCTAssertEqual(result.fullExpected, 10_000)
        XCTAssertEqual(result.mode, .resumeRemainingBytes)
    }

    func testNormalizeProgressFallsBackToLargestReasonableResumeTotal() {
        let result = BackgroundDownloadManager.normalizeProgressTotals(
            resumeOffset: 4_000,
            totalBytesWritten: 2_000,
            taskExpected: 8_500,
            recordedExpected: 10_000
        )

        XCTAssertEqual(result.writtenTotal, 6_000)
        XCTAssertEqual(result.fullExpected, 12_500)
        XCTAssertEqual(result.mode, .resumeFallback)
    }

    func testNormalizeProgressUsesRecordedExpectedWhenResumeOnlyHasPersistedSize() {
        let result = BackgroundDownloadManager.normalizeProgressTotals(
            resumeOffset: 4_000,
            totalBytesWritten: 2_000,
            taskExpected: nil,
            recordedExpected: 10_000
        )

        XCTAssertEqual(result.writtenTotal, 6_000)
        XCTAssertEqual(result.fullExpected, 10_000)
        XCTAssertEqual(result.mode, .resumeRecordedOnly)
    }

    func testDownloadArtifactDecodesLegacyDestinationIntoStagingAndFinalURLs() throws {
        let legacyDestination = URL(fileURLWithPath: "/tmp/model.gguf.download")
        let payload: [String: Any] = [
            "id": "artifact-legacy",
            "role": "mainWeights",
            "remoteURL": "https://example.com/model.gguf",
            "destinationURL": legacyDestination.absoluteString,
            "expectedBytes": 10_000,
            "downloadedBytes": 4_000,
            "state": "paused",
            "retryCount": 1,
            "manualPause": true
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        let artifact = try JSONDecoder().decode(DownloadArtifact.self, from: data)

        XCTAssertEqual(artifact.stagingURL, legacyDestination)
        XCTAssertEqual(artifact.finalURL, legacyDestination.deletingPathExtension())
        XCTAssertEqual(artifact.destinationURL, legacyDestination)
        XCTAssertEqual(artifact.state, .paused)
        XCTAssertTrue(artifact.manualPause)
    }
}
