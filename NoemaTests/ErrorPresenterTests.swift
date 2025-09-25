import XCTest
@testable import NoemaCore

final class ErrorPresenterTests: XCTestCase {
    func testMappingsReturnFriendlyMessages() {
        let timeout = AppError(code: .pyTimeout, message: "timeout")
        XCTAssertEqual(ErrorPresenter.present(timeout), "Python timed out. Try smaller samples or increase timeout.")

        let memory = AppError(code: .pyMemory, message: "OOM")
        XCTAssertEqual(ErrorPresenter.present(memory), "Python ran out of memory. Sample with nrows=… or drop columns.")

        let cache = AppError(code: .cacheCorrupt, message: "bad cache")
        XCTAssertEqual(ErrorPresenter.present(cache), "Cached artifacts are invalid. Clear cache and rerun.")

        let path = AppError(code: .pathDenied, message: "no")
        XCTAssertEqual(ErrorPresenter.present(path), "Access to that path is not allowed.")

        let export = AppError(code: .exportFailed, message: "zip")
        XCTAssertEqual(ErrorPresenter.present(export), "Could not create export archive.")

        let crew = AppError(code: .crewBudget, message: "limit")
        XCTAssertEqual(ErrorPresenter.present(crew), "Crew stopped at budget limit.")

        let custom = AppError(code: .unknown, message: "custom")
        XCTAssertEqual(ErrorPresenter.present(custom), "custom")
    }
}
