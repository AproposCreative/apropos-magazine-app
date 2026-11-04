import Combine
import XCTest
@testable import Apropos

final class ReadingHistoryRuntimeTests: XCTestCase {
    @MainActor
    private final class Memory {
        var records: [String: Data] = [:]
        var callbacks: [@MainActor (ReadingHistoryRuntime.ExternalEvent) -> Void] = []
        var scheduled: [@MainActor () -> Void] = []
        var factories = 0
        var reads = 0
        var writes = 0
        var synchronizations = 0
        var cancellations = 0
        var profileWrites: [(String, String)] = []
        var onFactory: (@MainActor () -> Void)?

        func runtime(disabled: Bool = false) -> ReadingHistoryRuntime {
            ReadingHistoryRuntime(disabled: disabled, transportFactory: { [self] in
                factories += 1
                onFactory?()
                return .init(storage: .init(read: { [self] namespace in
                    reads += 1
                    return records[namespace.storageKey]
                }, write: { [self] namespace, data in
                    writes += 1
                    records[namespace.storageKey] = data
                }), observe: { [self] callback in
                    callbacks.append(callback)
                    return { [self] in cancellations += 1 }
                }, synchronize: { [self] in synchronizations += 1 })
            }, schedule: { [self] _, action in
                scheduled.append(action)
                // Deliberately still deliver canceled work to exercise fences.
                return {}
            }, markProfileRead: { [self] articleID, uid in profileWrites.append((articleID, uid)) })
        }
    }

    @MainActor
    func testDisabledAndUnpreparedRuntimeNeverConstructPlatformEffects() {
        let memory = Memory()
        let runtime = memory.runtime(disabled: true)
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "reader-a")
        runtime.changeAccountContext(userID: nil)
        runtime.suspendForAccountChange()
        runtime.flushAcceptedEdits()
        XCTAssertEqual(memory.factories, 0)
        XCTAssertEqual(memory.synchronizations, 0)
        XCTAssertTrue(memory.callbacks.isEmpty)
        XCTAssertNil(runtime.model.beginArticle(articleID: "article"))

        let unprepared = memory.runtime()
        unprepared.changeAccountContext(userID: "reader-a")
        unprepared.flushAcceptedEdits()
        XCTAssertEqual(memory.factories, 0)
        XCTAssertNil(unprepared.model.beginArticle(articleID: "article"))
    }

    @MainActor
    func testPrepareIsReentrantSafeAndDoesNotReadBeforeCanonicalContext() {
        let memory = Memory()
        let runtime = memory.runtime()
        memory.onFactory = { [weak runtime] in
            runtime?.prepareIfNeeded()
            runtime?.changeAccountContext(userID: nil)
        }
        runtime.prepareIfNeeded()
        runtime.prepareIfNeeded()
        XCTAssertEqual(memory.factories, 1)
        XCTAssertEqual(memory.synchronizations, 1)
        XCTAssertEqual(memory.reads, 0)
        XCTAssertTrue(memory.callbacks.isEmpty)
        runtime.changeAccountContext(userID: "reader-a")
        XCTAssertEqual(memory.reads, 1)
        XCTAssertEqual(memory.callbacks.count, 1)
        runtime.changeAccountContext(userID: "reader-a")
        XCTAssertEqual(memory.reads, 1)
        XCTAssertEqual(memory.callbacks.count, 1)
    }

    @MainActor
    func testOriginalObserverCannotReloadAnotherOwnerAndCurrentDeletionClearsHistory() throws {
        let memory = Memory()
        let runtime = memory.runtime()
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "reader-a")
        let a = try XCTUnwrap(runtime.model.beginArticle(articleID: "article-a"))
        runtime.markRead(a)
        let oldObserver = try XCTUnwrap(memory.callbacks.first)
        runtime.changeAccountContext(userID: "reader-b")
        let b = try XCTUnwrap(runtime.model.beginArticle(articleID: "article-b"))
        runtime.markRead(b)
        let bKey = try XCTUnwrap(runtime.model.context.namespace?.storageKey)
        let reads = memory.reads
        memory.records.removeValue(forKey: bKey)
        oldObserver(.changed(keys: [bKey]))
        XCTAssertEqual(memory.reads, reads)
        XCTAssertEqual(runtime.model.snapshot.readArticleIDs, ["article-b"])
        let currentObserver = try XCTUnwrap(memory.callbacks.last)
        currentObserver(.changed(keys: ["readArticleIds", "unrelated"]))
        XCTAssertEqual(memory.reads, reads)
        currentObserver(.changed(keys: [bKey]))
        XCTAssertEqual(memory.reads, reads + 1)
        XCTAssertTrue(runtime.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertGreaterThanOrEqual(memory.cancellations, 1)
    }

    @MainActor
    func testStorageIdentityChangeInvalidatesReaderTimerAndCapturedObserver() throws {
        let memory = Memory()
        let runtime = memory.runtime()
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "reader-a")
        let ticket = try XCTUnwrap(runtime.model.beginArticle(articleID: "article-a"))
        runtime.markRead(ticket)
        runtime.model.saveProgress(0.6, ticket: ticket)
        let oldObserver = try XCTUnwrap(memory.callbacks.last)
        let key = try XCTUnwrap(runtime.model.context.namespace?.storageKey)
        memory.records.removeAll() // Represents the newly selected platform store.
        oldObserver(.accountChanged)
        XCTAssertFalse(runtime.model.isCurrent(ticket))
        XCTAssertTrue(runtime.model.snapshot.readArticleIDs.isEmpty)
        let writes = memory.writes
        memory.scheduled.forEach { $0() }
        oldObserver(.changed(keys: [key]))
        oldObserver(.quotaViolation)
        XCTAssertEqual(memory.writes, writes)
        XCTAssertNil(runtime.model.snapshot.issueMessage)
        XCTAssertEqual(memory.callbacks.count, 2)
    }

    @MainActor
    func testQuotaEventKeepsMemoryUntilExplicitRetryAndDoesNotPretendCloudAcknowledgement() throws {
        let memory = Memory()
        let runtime = memory.runtime()
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: nil)
        let ticket = try XCTUnwrap(runtime.model.beginArticle(articleID: "article"))
        runtime.markRead(ticket)
        runtime.model.saveProgress(0.4, ticket: ticket)
        let callback = try XCTUnwrap(memory.callbacks.last)
        callback(.quotaViolation)
        XCTAssertNotNil(runtime.model.snapshot.issueMessage)
        XCTAssertTrue(runtime.model.snapshot.canRetry)
        XCTAssertEqual(runtime.model.snapshot.progress["article"], 0.4)
        let writes = memory.writes
        memory.scheduled.forEach { $0() }
        XCTAssertEqual(memory.writes, writes)
        runtime.model.retryStorage()
        XCTAssertEqual(memory.writes, writes + 1)
        XCTAssertNil(runtime.model.snapshot.issueMessage)
        XCTAssertTrue(memory.profileWrites.isEmpty)
    }

    @MainActor
    func testProfileEffectRequiresOriginalLiveReaderAndRechecksAfterPublication() throws {
        let memory = Memory()
        let runtime = memory.runtime()
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "reader-a")
        let first = try XCTUnwrap(runtime.model.beginArticle(articleID: "first"))
        runtime.markRead(first)
        XCTAssertEqual(memory.profileWrites.map { $0.1 }, ["reader-a"])
        runtime.suspendForAccountChange()
        runtime.changeAccountContext(userID: "reader-a")
        runtime.markRead(first)
        XCTAssertEqual(memory.profileWrites.count, 1)

        let second = try XCTUnwrap(runtime.model.beginArticle(articleID: "second"))
        let subscription = runtime.model.changes.sink { snapshot in
            if snapshot.readArticleIDs.contains("second") { runtime.changeAccountContext(userID: "reader-b") }
        }
        runtime.markRead(second)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(memory.profileWrites.count, 1)
        XCTAssertEqual(runtime.model.context, .confirmed(userID: "reader-b"))
        XCTAssertTrue(runtime.model.snapshot.readArticleIDs.isEmpty)
    }
}
