import XCTest
@testable import Noema

final class ModelDownloadManagerTests: XCTestCase {
    actor Counter {
        private var active = 0
        private var maxObserved = 0

        func begin() {
            active += 1
            maxObserved = max(maxObserved, active)
        }

        func end() {
            active -= 1
        }

        func maximum() -> Int {
            maxObserved
        }
    }

    func testBoundedConcurrencyCapsParallelMultipartWorkAtFour() async throws {
        let counter = Counter()

        let results = try await ModelDownloadManager.runBoundedConcurrency(
            limit: ModelDownloadManager.multipartDownloadConcurrencyLimit,
            count: 8
        ) { index in
            await counter.begin()
            do {
                try await Task.sleep(for: .milliseconds(40))
                await counter.end()
                return index
            } catch {
                await counter.end()
                throw error
            }
        }

        XCTAssertEqual(results, Array(0..<8))
        let maximum = await counter.maximum()
        XCTAssertEqual(maximum, ModelDownloadManager.multipartDownloadConcurrencyLimit)
    }
}
