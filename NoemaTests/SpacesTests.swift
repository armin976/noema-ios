import XCTest
@testable import AutoFlow

final class SpacesTests: XCTestCase {
    func testCreateSwitchRenamePersistsActiveSpace() async throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let suite = "spaces-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to create user defaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: temp)
        }

        let store = SpaceStore(fileManager: fm, documentsURL: temp, userDefaults: defaults)
        try await Task.sleep(nanoseconds: 20_000_000)
        if (await store.loadAll()).isEmpty {
            _ = try await store.create(name: "Default Space")
        }

        let space = try await store.create(name: "Project A")
        try await store.switchTo(space.id)
        var active = await store.activeSpace()
        XCTAssertEqual(active?.name, "Project A")

        try await store.rename(id: space.id, name: "Project Alpha")
        active = await store.activeSpace()
        XCTAssertEqual(active?.name, "Project Alpha")

        let storeReloaded = SpaceStore(fileManager: fm, documentsURL: temp, userDefaults: defaults)
        try await Task.sleep(nanoseconds: 20_000_000)
        let reloadedActive = await storeReloaded.activeSpace()
        XCTAssertEqual(reloadedActive?.name, "Project Alpha")
    }
}
