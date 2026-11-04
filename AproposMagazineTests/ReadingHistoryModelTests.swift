import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReadingHistoryModelTests: XCTestCase {
    func testConstructionAndUnknownAuthAreInertIncludingInvalidConfirmedIdentity() {
        let f = HistoryCoreFixture(context: .unresolved)
        f.model.retryStorage()
        f.model.storageIdentityChanged()
        f.model.changeContext(to: .confirmed(userID: ""))
        XCTAssertNil(f.model.beginArticle(articleID: "article"))
        XCTAssertNil(f.model.externalTicket())
        XCTAssertEqual(f.model.snapshot.state, .unresolved)
        XCTAssertTrue(f.reads.isEmpty)
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertTrue(f.wakes.isEmpty)
    }

    func testAccountsAndGuestNeverAdoptEachOthersReadIDsOrProgress() throws {
        let a = ReadingHistoryContext.confirmed(userID: "private-A")
        let b = ReadingHistoryContext.confirmed(userID: "private-B")
        let f = HistoryCoreFixture(context: a)
        let first = try f.begin("article")
        f.model.markRead(first)
        f.model.saveProgress(0.4, ticket: first)
        f.fireLast()
        f.model.changeContext(to: b)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertTrue(f.model.snapshot.progress.isEmpty)
        f.model.markRead(try f.begin("B-only"))
        f.model.changeContext(to: .guest)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        f.model.markRead(try f.begin("guest-only"))
        f.model.changeContext(to: a)
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["article"])
        XCTAssertEqual(f.model.snapshot.progress["article"], 0.4)
        for (namespace, data) in f.records {
            XCTAssertFalse(namespace.storageKey.contains("private-"))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-"))
        }
    }

    func testMarkReadCommitsOneAtomicRecordIncludingAlreadyAcceptedProgress() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        XCTAssertEqual(f.model.saveProgress(0.5, ticket: ticket), .scheduled)
        XCTAssertEqual(f.model.markRead(ticket), .written)
        XCTAssertEqual(f.writes.count, 1)
        XCTAssertTrue(f.wakes[0].cancelled)
        let stored = try f.decoded(.guest)
        XCTAssertEqual(stored.entries, [.init(articleID: "article", read: true, progress: 0.5)])
        f.wakes[0].action()
        XCTAssertEqual(f.writes.count, 1)
    }

    func testDebounceUsesFourHundredMillisecondsAndOldCancelledWakeCannotWriteLatestRecord() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        f.model.saveProgress(0.2, ticket: ticket)
        f.model.saveProgress(0.8, ticket: ticket)
        XCTAssertEqual(f.wakes.map(\.seconds), [0.4, 0.4])
        XCTAssertTrue(f.wakes[0].cancelled)
        f.wakes[0].action()
        XCTAssertTrue(f.writes.isEmpty)
        f.wakes[1].action()
        XCTAssertEqual(f.writes.count, 1)
        XCTAssertEqual(try f.decoded(.guest).entries.first?.progress, 0.8)
        f.wakes[1].action()
        XCTAssertEqual(f.writes.count, 1)
    }

    func testEndArticleRejectsNewCallbacksButPreservesAlreadyAcceptedOwnedWrite() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        f.model.saveProgress(0.5, ticket: ticket)
        f.model.endArticle(ticket)
        XCTAssertFalse(f.model.isCurrent(ticket))
        XCTAssertEqual(f.model.markRead(ticket), .stale)
        XCTAssertEqual(f.model.saveProgress(0.9, ticket: ticket), .stale)
        f.fireLast()
        XCTAssertEqual(try f.decoded(.guest).entries.first?.progress, 0.5)
    }

    func testSameArticleReentryAndAnotherModelCannotReuseOldTicket() throws {
        let f = HistoryCoreFixture()
        let foreign = HistoryCoreFixture()
        let old = try f.begin("article")
        let current = try f.begin("article")
        XCTAssertEqual(old.articleID, "article")
        XCTAssertEqual(f.model.markRead(old), .stale)
        XCTAssertEqual(foreign.model.markRead(current), .stale)
        f.model.endArticle(old)
        XCTAssertTrue(f.model.isCurrent(current))
        XCTAssertEqual(f.model.markRead(current), .written)
    }

    func testAccountRoundTripRejectsOldArticleExternalAndTimerTicketsEvenWithSameUID() throws {
        let a = ReadingHistoryContext.confirmed(userID: "A")
        let f = HistoryCoreFixture(context: a)
        let article = try f.begin("article")
        let external = try XCTUnwrap(f.model.externalTicket())
        f.model.saveProgress(0.5, ticket: article)
        f.model.changeContext(to: .guest)
        f.model.changeContext(to: a)
        XCTAssertEqual(f.model.markRead(article), .stale)
        XCTAssertEqual(f.model.reloadExternal(ticket: external), .stale)
        f.model.reportQuotaViolation(ticket: external)
        f.wakes[0].action()
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertEqual(f.model.snapshot.state, .ready)
    }

    func testStorageIdentityChangeRotatesAllTicketsAndClearsBeforeRereadingSameAppOwner() throws {
        let f = HistoryCoreFixture()
        let article = try f.begin("article")
        f.model.markRead(article)
        f.model.saveProgress(0.5, ticket: article)
        let external = try XCTUnwrap(f.model.externalTicket())
        let generation = f.model.snapshot.generation
        f.onRead = { _ in
            XCTAssertFalse(f.model.isCurrent(article))
            XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
            XCTAssertTrue(f.model.snapshot.progress.isEmpty)
        }
        f.model.storageIdentityChanged()
        XCTAssertNotEqual(f.model.snapshot.generation, generation)
        XCTAssertEqual(f.model.reloadExternal(ticket: external), .stale)
        XCTAssertTrue(f.wakes[0].cancelled)
        f.wakes[0].action()
        XCTAssertEqual(f.writes.count, 1)
    }

    func testQuotaRetainsPendingMemoryAndRequiresExplicitRetryWithoutReload() throws {
        let f = HistoryCoreFixture()
        let article = try f.begin("article")
        f.model.saveProgress(0.6, ticket: article)
        let external = try XCTUnwrap(f.model.externalTicket())
        f.model.reportQuotaViolation(ticket: external)
        XCTAssertEqual(f.model.snapshot.state, .writeFailed)
        XCTAssertTrue(f.model.snapshot.canRetry)
        XCTAssertEqual(f.model.snapshot.progress["article"], 0.6)
        f.wakes[0].action()
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertEqual(f.model.saveProgress(0.8, ticket: article), .unavailable)
        XCTAssertEqual(f.wakes.count, 1)
        XCTAssertEqual(f.model.reloadExternal(ticket: external), .deferred)
        XCTAssertEqual(f.reads.count, 1)
        f.model.retryStorage()
        XCTAssertEqual(try f.decoded(.guest).entries.first?.progress, 0.8)
        XCTAssertEqual(f.model.snapshot.state, .ready)
    }

    func testLateQuotaFromPriorOwnerCannotBlockNewOwner() throws {
        let f = HistoryCoreFixture()
        let old = try XCTUnwrap(f.model.externalTicket())
        f.model.changeContext(to: .confirmed(userID: "B"))
        f.model.reportQuotaViolation(ticket: old)
        XCTAssertEqual(f.model.snapshot.state, .ready)
        XCTAssertEqual(f.model.markRead(try f.begin("B")), .written)
    }

    func testExternalReloadCannotErasePendingOrFailedLocalEdits() throws {
        let f = HistoryCoreFixture()
        let article = try f.begin("article")
        f.model.saveProgress(0.8, ticket: article)
        let external = try XCTUnwrap(f.model.externalTicket())
        try f.seed(.guest, article: "remote", progress: 0.1)
        XCTAssertEqual(f.model.reloadExternal(ticket: external), .deferred)
        XCTAssertEqual(f.model.snapshot.progress["article"], 0.8)
        f.failWrites = true
        f.fireLast()
        XCTAssertEqual(f.model.snapshot.state, .writeFailed)
        XCTAssertEqual(f.model.reloadExternal(ticket: external), .deferred)
        XCTAssertEqual(f.model.snapshot.progress["article"], 0.8)
        XCTAssertEqual(f.reads.count, 1)
        f.failWrites = false
        f.model.retryStorage()
        XCTAssertEqual(f.model.snapshot.progress["article"], 0.8)
        XCTAssertEqual(f.model.snapshot.state, .ready)
    }

    func testCleanExternalReplacementAndMissingRecordReplaceVisibleState() throws {
        let f = HistoryCoreFixture()
        let external = try XCTUnwrap(f.model.externalTicket())
        try f.seed(.guest, article: "remote", progress: 0.3)
        f.model.reloadExternal(ticket: external)
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["remote"])
        XCTAssertEqual(f.model.snapshot.progress["remote"], 0.3)
        f.records.removeValue(forKey: .guest)
        f.model.reloadExternal(ticket: external)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertTrue(f.model.snapshot.progress.isEmpty)
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testReadFailureAndForeignOrUnsupportedRecordsCloseWritesUntilRetry() throws {
        let f = HistoryCoreFixture(context: .unresolved)
        f.failReads = true
        f.model.changeContext(to: .guest)
        XCTAssertEqual(f.model.snapshot.state, .readFailed)
        let ticket = try f.begin("article")
        XCTAssertEqual(f.model.markRead(ticket), .unavailable)
        XCTAssertEqual(f.model.saveProgress(0.5, ticket: ticket), .unavailable)
        XCTAssertTrue(f.writes.isEmpty)
        f.failReads = false
        f.records[.guest] = Data("{\"schemaVersion\":2,\"namespace\":\"guest\",\"entries\":[]}".utf8)
        f.model.retryStorage()
        XCTAssertEqual(f.model.snapshot.state, .unsupportedVersion)
        f.records[.guest] = Data("{\"schemaVersion\":1,\"namespace\":\"account_other\",\"entries\":[]}".utf8)
        f.model.retryStorage()
        XCTAssertEqual(f.model.snapshot.state, .invalidRecord)
        f.records[.guest] = nil
        f.model.retryStorage()
        XCTAssertEqual(f.model.markRead(ticket), .written)
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["article"])
    }

    func testWriteFailureKeepsMemoryAndErrorWhileNewEditsWaitForExplicitRetry() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        f.failWrites = true
        XCTAssertEqual(f.model.markRead(ticket), .unavailable)
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["article"])
        XCTAssertEqual(f.model.snapshot.state, .writeFailed)
        XCTAssertNotNil(f.model.snapshot.issueMessage)
        XCTAssertEqual(f.model.saveProgress(0.9, ticket: ticket), .unavailable)
        XCTAssertTrue(f.wakes.isEmpty)
        XCTAssertEqual(f.writes.count, 1)
        f.failWrites = false
        f.model.retryStorage()
        XCTAssertEqual(try f.decoded(.guest).entries.first, .init(articleID: "article", read: true, progress: 0.9))
        XCTAssertNil(f.model.snapshot.issueMessage)
    }

    func testSynchronousSchedulerCompletionDoesNotInstallOrReplayAStaleCancelHandle() throws {
        let f = HistoryCoreFixture()
        f.onSchedule = { $0.action() }
        XCTAssertEqual(f.model.saveProgress(0.5, ticket: try f.begin("article")), .scheduled)
        XCTAssertEqual(f.writes.count, 1)
        XCTAssertEqual(f.model.snapshot.state, .ready)
        XCTAssertTrue(f.wakes[0].cancelled)
        f.wakes[0].action()
        XCTAssertEqual(f.writes.count, 1)
    }

    func testSchedulerReentryCannotRegisterAnOldOwnerWriteAfterContextChanged() throws {
        let f = HistoryCoreFixture()
        f.onSchedule = { _ in f.model.changeContext(to: .confirmed(userID: "B")) }
        f.model.saveProgress(0.5, ticket: try f.begin("article"))
        XCTAssertTrue(f.wakes[0].cancelled)
        f.wakes[0].action()
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertTrue(f.model.snapshot.progress.isEmpty)
    }

    func testReentrantCancellationCannotMakeFlushOverwriteANewerAcceptedPayload() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        f.model.saveProgress(0.2, ticket: ticket)
        f.onCancel = {
            f.onCancel = nil
            f.model.saveProgress(0.9, ticket: ticket)
        }
        f.model.flushPending()
        XCTAssertTrue(f.writes.isEmpty)
        f.fireLast()
        XCTAssertEqual(try f.decoded(.guest).entries.first?.progress, 0.9)
    }

    func testReentrantStorageContextChangeCannotPublishOldOwnerDataIntoNewOwner() throws {
        let f = HistoryCoreFixture()
        f.onWrite = { _, _ in
            f.onWrite = nil
            f.model.changeContext(to: .confirmed(userID: "B"))
        }
        XCTAssertEqual(f.model.markRead(try f.begin("article")), .stale)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertEqual(f.model.snapshot.state, .ready)
        XCTAssertEqual(f.records.count, 1)
        XCTAssertNotNil(f.records[.guest])
    }

    func testReentrantObjectPublicationCannotOverwriteNewerContext() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        let b = ReadingHistoryContext.confirmed(userID: "B")
        var called = false
        let subscription = f.model.objectWillChange.sink {
            if !called { called = true;f.model.changeContext(to: b) }
        }
        XCTAssertEqual(f.model.markRead(ticket), .stale)
        XCTAssertEqual(f.model.context, b)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testChangesPublishCommittedStateAndCanInvalidateOlderOwnerReentrantly() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        var seen: [ReadingHistorySnapshot] = []
        let subscription = f.model.changes.sink { snapshot in
            XCTAssertEqual(f.model.snapshot, snapshot)
            seen.append(snapshot)
            if snapshot.readArticleIDs == ["article"] { f.model.changeContext(to: .confirmed(userID: "B")) }
        }
        XCTAssertEqual(f.model.markRead(ticket), .stale)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertTrue(seen.contains { $0.readArticleIDs == ["article"] })
        XCTAssertEqual(seen.last, f.model.snapshot)
        withExtendedLifetime(subscription) {}
    }

    func testRetentionFitsBothTwoHundredEntriesAndActualEscapedJSONByteBudget() throws {
        let f = HistoryCoreFixture()
        let ids = (0..<205).map { index in String(format: "%04d", index) + String(repeating: "\"\\", count: 254) }
        for id in ids { f.model.markRead(try f.begin(id)) }
        let last = try f.begin(XCTUnwrap(ids.last))
        XCTAssertEqual(f.model.saveProgress(0.9, ticket: last), .scheduled)
        f.fireLast()
        let record = try f.decoded(.guest)
        XCTAssertLessThanOrEqual(record.entries.count, 200)
        XCTAssertLessThan(record.entries.count, 200) // Escaping, not count, is the limiting bound.
        XCTAssertEqual(record.entries.map(\.articleID), Array(ids.suffix(record.entries.count)))
        XCTAssertEqual(record.entries.last?.progress, 0.9)
        XCTAssertTrue(f.writes.allSatisfy { $0.1.count <= 131_072 })
        let data = try ReadingHistoryRecordCodec.encode(record, namespace: .guest)
        XCTAssertEqual(try ReadingHistoryRecordCodec.decode(data, namespace: .guest), record)
        XCTAssertNil(f.model.snapshot.issueMessage)
    }

    func testInvalidProgressAndIDsNeverMutateAnOwnedSessionOrScheduleStorage() throws {
        let f = HistoryCoreFixture()
        let ticket = try f.begin("article")
        for value in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            XCTAssertEqual(f.model.saveProgress(value, ticket: ticket), .unchanged)
        }
        for id in ["", " article", "article\n", String(repeating: "ø", count: 257)] {
            XCTAssertNil(f.model.beginArticle(articleID: id))
        }
        XCTAssertTrue(f.model.isCurrent(ticket))
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertTrue(f.wakes.isEmpty)
    }

    func testQuotaReentrantInsideWriteCannotBeHiddenBySuccessfulProcessReadback() throws {
        let f = HistoryCoreFixture()
        let external = try XCTUnwrap(f.model.externalTicket())
        f.onWrite = { _, _ in
            f.onWrite = nil
            f.model.reportQuotaViolation(ticket: external)
        }
        XCTAssertEqual(f.model.markRead(try f.begin("article")), .stale)
        XCTAssertEqual(f.model.snapshot.state, .writeFailed)
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["article"])
        f.model.retryStorage()
        XCTAssertEqual(f.model.snapshot.state, .ready)
        XCTAssertEqual(f.writes.count, 2)
    }
}

@MainActor
final class HistoryCoreFixture {
    enum Failure: Error { case privateFailure }
    final class Wake {
        let seconds: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
        init(seconds: TimeInterval, action: @escaping @MainActor () -> Void) { self.seconds = seconds;self.action = action }
    }
    var records: [ReadingHistoryNamespace: Data] = [:]
    var reads: [ReadingHistoryNamespace] = []
    var writes: [(ReadingHistoryNamespace, Data)] = []
    var wakes: [Wake] = []
    var failReads = false
    var failWrites = false
    var onRead: ((ReadingHistoryNamespace) -> Void)?
    var onWrite: ((ReadingHistoryNamespace, Data) -> Void)?
    var onSchedule: ((Wake) -> Void)?
    var onCancel: (() -> Void)?
    lazy var model = ReadingHistoryModel(storage: .init(read: { [weak self] namespace in
        guard let self else { throw Failure.privateFailure }
        self.reads.append(namespace)
        self.onRead?(namespace)
        if self.failReads { throw Failure.privateFailure }
        return self.records[namespace]
    }, write: { [weak self] namespace, data in
        guard let self else { throw Failure.privateFailure }
        self.writes.append((namespace, data))
        self.onWrite?(namespace, data)
        if self.failWrites { throw Failure.privateFailure }
        self.records[namespace] = data
    }), schedule: { [weak self] seconds, action in
        guard let self else { return {} }
        let wake = Wake(seconds: seconds, action: action)
        self.wakes.append(wake)
        self.onSchedule?(wake)
        return { [weak self] in wake.cancelled = true;self?.onCancel?() }
    })
    init(context: ReadingHistoryContext = .guest) { model.changeContext(to: context) }
    func begin(_ id: String) throws -> ReadingHistoryModel.ArticleTicket { try XCTUnwrap(model.beginArticle(articleID: id)) }
    func fireLast() { wakes.last?.action() }
    func seed(_ namespace: ReadingHistoryNamespace, article: String, progress: Double) throws {
        records[namespace] = try ReadingHistoryRecordCodec.encode(.init(entries: [
            .init(articleID: article, read: true, progress: progress)
        ]), namespace: namespace)
    }
    func decoded(_ namespace: ReadingHistoryNamespace) throws -> ReadingHistoryRecord {
        try ReadingHistoryRecordCodec.decode(XCTUnwrap(records[namespace]), namespace: namespace)
    }
}
