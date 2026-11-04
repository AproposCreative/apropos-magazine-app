import XCTest
@testable import Apropos

final class CacheDirectorySizeWorkerTests: XCTestCase {
    func testActualDirectoryWorkerReadsOnlyOwnedTemporaryFixture() async throws {
        let manager = FileManager()
        let directory = manager.temporaryDirectory.appendingPathComponent("apropos-cache-size-test-" + UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("a"))
        try Data([1, 2, 3, 4, 5]).write(to: directory.appendingPathComponent("b"))
        let size = await CacheDirectorySizeWorker().size(at: directory)
        XCTAssertEqual(size, 8)
    }
    func testMissingOwnedTemporaryPathPreservesZeroSizeFallback() async {
        let path = FileManager().temporaryDirectory.appendingPathComponent("apropos-absent-cache-size-" + UUID().uuidString)
        let size = await CacheDirectorySizeWorker().size(at: path)
        XCTAssertEqual(size, 0)
    }
}
