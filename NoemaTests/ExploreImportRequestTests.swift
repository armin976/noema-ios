import XCTest
import UniformTypeIdentifiers
@testable import Noema

final class ExploreImportRequestTests: XCTestCase {
    func testGGUFFilesRequestHasNonEmptyAllowedContentTypes() {
        XCTAssertFalse(ExploreImportRequest.ggufFiles.allowedContentTypes.isEmpty)
    }

    func testGGUFFilesRequestAllowsMultipleSelection() {
        XCTAssertTrue(ExploreImportRequest.ggufFiles.allowsMultipleSelection)
    }

    func testGGUFFolderRequestIsSingleSelectFolderOnly() {
        XCTAssertEqual(ExploreImportRequest.ggufFolder.allowedContentTypes, [.folder])
        XCTAssertFalse(ExploreImportRequest.ggufFolder.allowsMultipleSelection)
    }

    func testMLXFolderRequestIsSingleSelectFolderOnly() {
        XCTAssertEqual(ExploreImportRequest.mlxFolder.allowedContentTypes, [.folder])
        XCTAssertFalse(ExploreImportRequest.mlxFolder.allowsMultipleSelection)
    }
}
