import XCTest
@testable import NoemaCore

final class ErrorPresenterTests: XCTestCase {
    func testMappingsReturnFriendlyMessages() {
        let timeout = AppError(code: .pyTimeout, message: "timeout")
        XCTAssertEqual(ErrorPresenter.present(timeout), "Python timed out. Try a smaller sample or raise timeout.")

        let memory = AppError(code: .pyMemory, message: "OOM")
        XCTAssertEqual(ErrorPresenter.present(memory), "Python memory limit. Sample with nrows=… or drop columns.")

        let cache = AppError(code: .cacheCorrupt, message: "bad cache")
        XCTAssertEqual(ErrorPresenter.present(cache), "Cached artifacts invalid. Clear cache and rerun.")

        let path = AppError(code: .pathDenied, message: "no")
        XCTAssertEqual(ErrorPresenter.present(path), "Path access denied.")

        let export = AppError(code: .exportFailed, message: "zip")
        XCTAssertEqual(ErrorPresenter.present(export), "Export failed.")

        let crew = AppError(code: .crewBudget, message: "limit")
        XCTAssertEqual(ErrorPresenter.present(crew), "Crew hit budget limit.")

        let custom = AppError(code: .unknown, message: "custom")
        XCTAssertEqual(ErrorPresenter.present(custom), "custom")
    }
}
