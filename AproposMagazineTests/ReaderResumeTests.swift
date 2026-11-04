import Combine
import Foundation
import XCTest
import SwiftUI
@testable import Apropos

@MainActor
final class ReaderResumeTests: XCTestCase {
    private let ownerA = "account_" + String(repeating: "a", count: 64)
    private let ownerB = "account_" + String(repeating: "b", count: 64)
    private let anchor = ReaderResumeAnchor(index: 6, fingerprint: "1234abcd")
    private func source(_ id: String = "article", revision: String? = "v1", html: String = "<p>Exact source</p>") -> ReaderResumeIdentity {
        ReaderResumeIdentity(articleID: id, sourceRevision: revision, html: html)!
    }

    func testSourceIdentityRejectsInvalidAndBindsExactBytesAndRevision() {
        XCTAssertNil(ReaderResumeIdentity(articleID: " ", sourceRevision: nil, html: "body"))
        XCTAssertNil(ReaderResumeIdentity(articleID: "a", sourceRevision: nil, html: ""))
        XCTAssertNotEqual(source(), source(revision: "v2"))
        XCTAssertNotEqual(source(), source(html: "<p>Exact source </p>"))
        XCTAssertEqual(source().sourceDigest.count, 64)
    }

    func testStoreSeparatesOwnersAndDoesNotGuessChangedRevisionOrSource() async throws {
        let memory = ResumeMemory(), item = source()
        let store = ReaderResumeStore(storage: memory.storage)
        try await store.save(owner: ownerA, source: item, anchor: anchor)
        let a = try await store.load(owner: ownerA, source: item)
        let b = try await store.load(owner: ownerB, source: item)
        let guest = try await store.load(owner: "guest", source: item)
        let changed = try await store.load(owner: ownerA, source: source(revision: "v2"))
        let edited = try await store.load(owner: ownerA, source: source(html: "changed"))
        XCTAssertEqual(a, anchor); XCTAssertNil(b); XCTAssertNil(guest); XCTAssertNil(changed); XCTAssertNil(edited)
    }

    func testStoreHasBoundedRetentionAndPreservesUnrelatedOwnersOnRemoval() async throws {
        let memory = ResumeMemory(), store: ReaderResumeStore
        store = ReaderResumeStore(storage: memory.storage)
        for index in 0...ReaderResumeRecord.maximumEntries {
            try await store.save(owner: ownerA, source: source("article-\(index)"), anchor: anchor)
        }
        let evicted = try await store.load(owner: ownerA, source: source("article-0"))
        let kept = try await store.load(owner: ownerA, source: source("article-120"))
        XCTAssertNil(evicted); XCTAssertEqual(kept, anchor)
        try await store.save(owner: ownerB, source: source("article-120"), anchor: anchor)
        try await store.save(owner: ownerA, source: source("article-120"), anchor: nil)
        let b = try await store.load(owner: ownerB, source: source("article-120"))
        XCTAssertEqual(b, anchor)
    }

    func testMalformedRecordsFailClosedWithoutOverwriting() async {
        let invalid: [Data] = [Data(), Data(repeating: 65, count: ReaderResumeRecord.maximumBytes + 1),
            Data("{\"schemaVersion\":2,\"entries\":[]}".utf8), Data("not json".utf8)]
        for data in invalid {
            let memory = ResumeMemory(data: data), store: ReaderResumeStore
            store = ReaderResumeStore(storage: memory.storage)
            do { try await store.save(owner: ownerA, source: source(), anchor: anchor); XCTFail("Corrupt record was replaced") }
            catch { }
            XCTAssertEqual(memory.writes, 0)
        }
    }

    func testCodecRejectsDuplicateOwnersInvalidAnchorsAndForeignOwner() throws {
        let entry = ReaderResumeRecord.Entry(owner: ownerA, source: source(), anchor: anchor)
        XCTAssertThrowsError(try ReaderResumeRecord.encode(.init(entries: [entry, entry])))
        XCTAssertThrowsError(try ReaderResumeRecord.encode(.init(entries: [.init(owner: "uid", source: source(), anchor: anchor)])))
        XCTAssertFalse(ReaderResumeAnchor(index: 1_200, fingerprint: "1234abcd").isValid)
        XCTAssertFalse(ReaderResumeAnchor(index: -1, fingerprint: "1234abcd").isValid)
        XCTAssertFalse(ReaderResumeAnchor(index: 1, fingerprint: "BAD").isValid)
    }

    func testLostStorageWriteDoesNotClaimAcknowledgement() async {
        let memory = ResumeMemory(); memory.dropWrites = true
        let store = ReaderResumeStore(storage: memory.storage)
        do { try await store.save(owner: ownerA, source: source(), anchor: anchor); XCTFail("Lost write accepted") }
        catch { }
        XCTAssertEqual(memory.writes, 1)
    }

    func testReopenAndDocumentRemeasureAreReadOnly() async throws {
        let memory = ResumeMemory(), store: ReaderResumeStore
        store = ReaderResumeStore(storage: memory.storage)
        let model = ReaderResumeController(store: store), item = source(), session = UUID()
        try await store.save(owner: ownerA, source: item, anchor: anchor)
        let initialWrites = memory.writes
        model.bind(owner: ownerA, source: item, sessionID: session, documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        XCTAssertEqual(model.snapshot.offer, anchor)
        model.bind(owner: ownerA, source: item, sessionID: session, documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        XCTAssertEqual(model.snapshot.offer, anchor)
        let saved = try await store.load(owner: ownerA, source: item)
        XCTAssertEqual(saved, anchor); XCTAssertEqual(memory.writes, initialWrites)
    }

    func testOnlyExplicitResumeInvokesScrollAndRequiresCurrentOwner() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        try await store.save(owner: ownerA, source: source(), anchor: anchor)
        let model = ReaderResumeController(store: store)
        var current = true, calls = 0
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { current })
        await model.waitForPendingWork()
        XCTAssertEqual(calls, 0)
        model.resume { _, _, permitted, done in XCTAssertTrue(permitted()); calls += 1; done(true) }
        XCTAssertEqual(calls, 1)
        current = false
        XCTAssertNil(model.snapshot.offer)
        model.resume { _, _, _, _ in calls += 1 }
        XCTAssertEqual(calls, 1)
    }

    func testRealInteractionSavesAndCompletionRemovesOnlyOriginalArticle() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        let model = ReaderResumeController(store: store), id = UUID().uuidString
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: id, isCurrent: { true })
        await model.waitForPendingWork()
        model.record(anchor, completed: false, documentID: id)
        await model.waitForPendingWork()
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor)
        model.record(anchor, completed: true, documentID: id)
        await model.waitForPendingWork()
        let completed = try await store.load(owner: ownerA, source: source())
        XCTAssertNil(completed)
    }

    func testOldDocumentAndOwnerCallbacksCannotSave() async throws {
        let memory = ResumeMemory(), store = ReaderResumeStore(storage: memory.storage)
        let model = ReaderResumeController(store: store), first = UUID().uuidString, second = UUID().uuidString
        var current = true
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: first, isCurrent: { current })
        await model.waitForPendingWork()
        model.bind(owner: ownerB, source: source(), sessionID: UUID(), documentID: second, isCurrent: { current })
        await model.waitForPendingWork()
        model.record(anchor, completed: false, documentID: first)
        current = false
        model.record(anchor, completed: false, documentID: second)
        await model.waitForPendingWork()
        XCTAssertEqual(memory.writes, 0)
    }

    func testRebindingImmediatelyRevokesOldOfferBeforeDeferredPublication() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        try await store.save(owner: ownerA, source: source(), anchor: anchor)
        let model = ReaderResumeController(store: store)
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        XCTAssertEqual(model.snapshot.offer, anchor)
        model.bind(owner: ownerB, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        model.resume { _, _, _, _ in XCTFail("A's offer was lent to B") }
        XCTAssertNil(model.snapshot.offer)
        await model.waitForPendingWork()
    }

    func testReentrantAdmissionCannotReplaceNewerBinding() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        let model = ReaderResumeController(store: store)
        let b = UUID().uuidString
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString) {
            model.bind(owner: self.ownerB, source: self.source(), sessionID: UUID(), documentID: b, isCurrent: { true })
            return true
        }
        await model.waitForPendingWork()
        model.record(anchor, completed: false, documentID: b)
        await model.waitForPendingWork()
        let savedA = try await store.load(owner: ownerA, source: source())
        let savedB = try await store.load(owner: ownerB, source: source())
        XCTAssertNil(savedA); XCTAssertEqual(savedB, anchor)
    }

    func testReentrantWillChangeCannotStartOldResumeOrRepublishOldOffer() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        try await store.save(owner: ownerA, source: source(), anchor: anchor)
        let model = ReaderResumeController(store: store)
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        var armed = true
        let observation = model.objectWillChange.sink {
            if armed {
                armed = false
                model.bind(owner: self.ownerB, source: self.source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
            }
        }
        model.resume { _, _, _, _ in XCTFail("Old resume escaped reentrant switch") }
        await model.waitForPendingWork()
        XCTAssertNil(model.snapshot.offer); XCTAssertFalse(model.snapshot.isResuming)
        withExtendedLifetime(observation) { }
    }

    func testOldAndDuplicateResumeCompletionCannotFinishNewRequest() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        try await store.save(owner: ownerA, source: source(), anchor: anchor)
        let model = ReaderResumeController(store: store)
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        var first: (@MainActor (Bool) -> Void)?, second: (@MainActor (Bool) -> Void)?
        model.resume { _, _, _, complete in first = complete }
        first?(true)
        model.resume { _, _, _, complete in second = complete }
        first?(false)
        XCTAssertTrue(model.snapshot.isResuming); XCTAssertNil(model.snapshot.message)
        second?(true); XCTAssertFalse(model.snapshot.isResuming)
    }

    func testStorageFailureIsVisibleAndDisabledRuntimeDoesNoIO() async {
        let memory = ResumeMemory(data: Data("invalid".utf8)), store = ReaderResumeStore(storage: memory.storage)
        let model = ReaderResumeController(store: store)
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        XCTAssertNotNil(model.snapshot.message)
        let reads = memory.reads, disabled = ReaderResumeController(store: store, disabled: true)
        disabled.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await disabled.waitForPendingWork()
        XCTAssertEqual(memory.reads, reads)
    }

    func testActualHTMLCoordinatorRejectsNewArticleBeforeOldSessionIsReplaced() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        let resume = ReaderResumeController(store: store)
        let history = ReadingHistoryModel(storage: .init(read: { _ in nil }, write: { _, _ in }),
                                          schedule: { _, _ in {} })
        history.changeContext(to: .guest)
        let binding = ReaderHistoryBinding(model: history, markRead: { _ in })
        let session = try XCTUnwrap(binding.beginArticle(articleID: "article-A", onOpen: {}, onProgress: { _ in }))
        let renderer = HTMLTextView(html: "<p>New B source</p>", articleId: "article-B", dynamicHeight: .constant(240),
            historyBinding: binding, historySession: session, resumeController: resume, resumeOwner: "guest",
            prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
        let coordinator = renderer.makeCoordinator(), documentID = UUID().uuidString
        coordinator.acceptDocument(documentID)
        coordinator.documentBecameReady(documentID)
        await resume.waitForPendingWork()
        resume.record(anchor, completed: false, documentID: documentID)
        await resume.waitForPendingWork()
        let oldSource = ReaderResumeIdentity(articleID: "article-A", sourceRevision: nil, html: "<p>New B source</p>")!
        let stored = try await store.load(owner: "guest", source: oldSource)
        XCTAssertNil(stored)
        coordinator.invalidateDocument()
    }

    func testSuccessfulResumeRetryClearsOnlyResumeFailure() async throws {
        let store = ReaderResumeStore(storage: ResumeMemory().storage)
        try await store.save(owner: ownerA, source: source(), anchor: anchor)
        let model = ReaderResumeController(store: store)
        model.bind(owner: ownerA, source: source(), sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await model.waitForPendingWork()
        model.resume { _, _, _, completion in completion(false) }
        XCTAssertNotNil(model.snapshot.message)
        model.resume { _, _, _, completion in completion(true) }
        XCTAssertNil(model.snapshot.message)
    }

    func testResumeGeometryUsesFreshParagraphAndTopbarThenClampsBothEnds() {
        XCTAssertEqual(ReaderResumeGeometry.offset(paragraphTop: 900, viewportTop: 100, currentOffset: 500,
            contentHeight: 3_000, viewportHeight: 700, topInset: 0, bottomInset: 0), 1_300)
        XCTAssertEqual(ReaderResumeGeometry.offset(paragraphTop: 2_000, viewportTop: 100, currentOffset: 500,
            contentHeight: 3_000, viewportHeight: 700, topInset: 0, bottomInset: 0), 2_300)
        XCTAssertEqual(ReaderResumeGeometry.offset(paragraphTop: 0, viewportTop: 100, currentOffset: 0,
            contentHeight: 3_000, viewportHeight: 700, topInset: 20, bottomInset: 0), -20)
        XCTAssertNil(ReaderResumeGeometry.offset(paragraphTop: .nan, viewportTop: 0, currentOffset: 0,
            contentHeight: 3_000, viewportHeight: 700, topInset: 0, bottomInset: 0))
    }
}

/// The same synchronous storage contract as production, isolated to memory.
private final class ResumeMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var readCount = 0
    private var writeCount = 0
    var dropWrites = false
    init(data: Data? = nil) { self.data = data }
    var reads: Int { lock.withLock { readCount } }
    var writes: Int { lock.withLock { writeCount } }
    var storage: ReaderResumeStore.Storage {
        .init(read: { [self] in lock.withLock { readCount += 1; return data } },
              write: { [self] next in lock.withLock { writeCount += 1; if !dropWrites { data = next } } })
    }
}
