import XCTest
@testable import Noema

final class NotebookStoreTests: XCTestCase {
    func testApplyPythonResultCreatesCells() {
        let store = NotebookStore()
        XCTAssertTrue(store.notebook.cells.isEmpty)
        let payload = PythonExecuteResult(stdout: "hello", stderr: "", tables: [Data("{}".utf8).base64EncodedString()], images: [])
        store.apply(pythonResult: payload)
        XCTAssertEqual(store.notebook.cells.count, 2)
        XCTAssertEqual(store.notebook.cells.first?.text?.contains("hello"), true)
        XCTAssertNotNil(store.notebook.cells.last?.payload)
    }
}
