import XCTest
@testable import Apropos

final class PodcastProgressRuntimeTests: XCTestCase {
    @MainActor
    func testDisabledRuntimeNeverConstructsStorageOrPlayerEffects() {
        var factories = 0
        let runtime = PodcastProgressRuntime(disabled: true, storageFactory: {
            factories += 1
            return .init(read: { _ in XCTFail("Disabled runtime read");return nil },
                         write: { _, _ in XCTFail("Disabled runtime write") })
        })
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "account-a")
        runtime.changeAccountContext(userID: nil)
        runtime.suspendForAccountChange()
        XCTAssertEqual(factories, 0)
        XCTAssertNil(runtime.model.beginSession(episodeID: "episode", articleID: nil))
    }

    @MainActor
    func testPreparationIsInertUntilCanonicalAuthAndFactoryRunsOnce() {
        var factories = 0, reads = 0, writes = 0
        let runtime = PodcastProgressRuntime(disabled: false, storageFactory: {
            factories += 1
            return .init(read: { _ in reads += 1;return nil }, write: { _, _ in writes += 1 })
        })
        runtime.changeAccountContext(userID: "account-a")
        XCTAssertEqual(factories, 0)
        runtime.prepareIfNeeded()
        runtime.prepareIfNeeded()
        XCTAssertEqual(factories, 1)
        XCTAssertEqual(reads, 0)
        XCTAssertNil(runtime.model.beginSession(episodeID: "episode", articleID: nil))
        runtime.changeAccountContext(userID: "account-a")
        runtime.changeAccountContext(userID: "account-a")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testSuspendInvalidatesBeforeTeardownAndRestoredSameAccountCannotUseOldSession() throws {
        var records: [String: Data] = [:]
        let runtime = PodcastProgressRuntime(disabled: false, storageFactory: {
            .init(read: { records[$0.storageKey] }, write: { records[$0.storageKey] = $1 })
        })
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "account-a")
        let session = try XCTUnwrap(runtime.model.beginSession(episodeID: "episode", articleID: "article"))
        runtime.model.save(session.ticket, seconds: 42, duration: 600)
        var hookCalls = 0
        runtime.model.onContextInvalidated = { [weak model = runtime.model] in
            guard let model else { XCTFail("Expected existing model");return }
            hookCalls += 1
            XCTAssertFalse(model.isCurrent(session.ticket))
            XCTAssertNil(model.snapshot.position(for: "episode"))
            model.save(session.ticket, seconds: 90, duration: 600)
        }
        runtime.suspendForAccountChange()
        XCTAssertEqual(hookCalls, 1)
        XCTAssertNil(runtime.model.beginSession(episodeID: "episode", articleID: nil))
        runtime.changeAccountContext(userID: "account-a")
        XCTAssertEqual(runtime.model.snapshot.position(for: "episode"), 42)
        XCTAssertFalse(runtime.model.isCurrent(session.ticket))
        runtime.model.save(session.ticket, seconds: 120, duration: 600)
        XCTAssertEqual(runtime.model.snapshot.position(for: "episode"), 42)
    }

    @MainActor
    func testReentrantPrepareCannotConstructSecondStorage() {
        var runtime: PodcastProgressRuntime!
        var factories = 0
        runtime = PodcastProgressRuntime(disabled: false, storageFactory: {
            factories += 1
            runtime.prepareIfNeeded()
            runtime.changeAccountContext(userID: nil)
            return .init(read: { _ in XCTFail("Factory cannot publish auth while preparing");return nil }, write: { _, _ in })
        })
        runtime.prepareIfNeeded()
        XCTAssertEqual(factories, 1)
        XCTAssertNil(runtime.model.beginSession(episodeID: "episode", articleID: nil))
    }
}
