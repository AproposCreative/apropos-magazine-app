import Combine
import XCTest
@testable import Apropos

@MainActor
final class PodcastProgressOwnershipTests: XCTestCase {
    func testConstructionAndUnknownAuthenticationAreInert() {
        let f = PodcastProgressMemory(context: .unresolved)
        var hooks = 0
        f.store.onContextInvalidated = { hooks += 1 }
        f.store.retryStorage()
        f.store.changeContext(to: .unresolved)
        XCTAssertNil(f.store.beginSession(episodeID: "episode", articleID: nil))
        XCTAssertEqual(f.store.snapshot.state, .unresolved)
        XCTAssertTrue(f.reads.isEmpty)
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertEqual(hooks, 0)
    }

    func testAccountsAndGuestHaveIndependentPositionsAndAtomicLastMarkers() throws {
        let a = PodcastProgressContext.confirmed(userID: "reader-A")
        let b = PodcastProgressContext.confirmed(userID: "reader-B")
        let f = PodcastProgressMemory(context: a)
        f.store.save(try f.begin("episode", article: "article-A").ticket, seconds: 42, duration: 600)
        f.store.changeContext(to: b)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertNil(f.store.snapshot.lastPlayedEpisodeID)
        XCTAssertEqual(f.store.snapshot.playButtonTitle(for: "episode"), "Lyt")
        f.store.save(try f.begin("episode", article: "article-B").ticket, seconds: 84, duration: 600)
        f.store.changeContext(to: .guest)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        f.store.save(try f.begin("episode").ticket, seconds: 21, duration: 600)
        f.store.changeContext(to: a)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
        XCTAssertEqual(f.store.snapshot.lastPlayedArticleID, "article-A")
        f.store.changeContext(to: b)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 84)
        XCTAssertEqual(f.store.snapshot.lastPlayedArticleID, "article-B")
        f.store.changeContext(to: .guest)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 21)
        XCTAssertNil(f.store.snapshot.lastPlayedArticleID)
        XCTAssertEqual(f.records.count, 3)
        for (namespace, data) in f.records {
            XCTAssertFalse(namespace.storageKey.contains("reader-"))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("reader-"))
        }
    }

    func testReturningToSameAccountNeverRevivesAnOlderTicket() throws {
        let a = PodcastProgressContext.confirmed(userID: "A")
        let f = PodcastProgressMemory(context: a)
        let old = try f.begin("episode")
        f.store.save(old.ticket, seconds: 42, duration: 600)
        f.store.changeContext(to: .guest)
        f.store.changeContext(to: a)
        let current = try f.begin("episode")
        let count = f.writes.count
        XCTAssertFalse(f.store.isCurrent(old.ticket))
        XCTAssertEqual(f.store.save(old.ticket, seconds: 1, duration: 10), .stale)
        XCTAssertEqual(f.store.complete(old.ticket), .stale)
        f.store.endSession(old.ticket)
        XCTAssertTrue(f.store.isCurrent(current.ticket))
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
        XCTAssertEqual(f.writes.count, count)
    }

    func testTicketsCannotBeUsedByAnotherStoreOrAfterEnd() throws {
        let a = PodcastProgressMemory()
        let b = PodcastProgressMemory()
        let ticket = try a.begin("episode").ticket
        _ = try b.begin("episode")
        XCTAssertEqual(b.store.save(ticket, seconds: 42, duration: 600), .stale)
        a.store.endSession(ticket)
        XCTAssertFalse(a.store.isCurrent(ticket))
        XCTAssertEqual(a.store.complete(ticket), .stale)
        XCTAssertTrue(a.writes.isEmpty)
        XCTAssertTrue(b.writes.isEmpty)
    }

    func testSameCanonicalContextDoesNotInterruptPlaybackOrReloadStorage() throws {
        let context = PodcastProgressContext.confirmed(userID: "A")
        let f = PodcastProgressMemory(context: context)
        let s = try f.begin("episode")
        let generation = f.store.snapshot.generation
        var hooks = 0
        f.store.onContextInvalidated = { hooks += 1 }
        f.store.changeContext(to: context)
        XCTAssertTrue(f.store.isCurrent(s.ticket))
        XCTAssertEqual(f.store.snapshot.generation, generation)
        XCTAssertEqual(f.reads.count, 1)
        XCTAssertEqual(hooks, 0)
    }

    func testContextHookSeesEmptySnapshotAndInvalidTicketsBeforeNewRead() throws {
        let f = PodcastProgressMemory()
        let old = try f.begin("episode")
        f.store.save(old.ticket, seconds: 42, duration: 600)
        var events: [String] = []
        f.store.onContextInvalidated = {
            events.append("stop")
            XCTAssertNil(f.store.snapshot.position(for: "episode"))
            XCTAssertFalse(f.store.isCurrent(old.ticket))
            XCTAssertEqual(f.store.save(old.ticket, seconds: 60, duration: 600), .stale)
            XCTAssertNil(f.store.beginSession(episodeID: "episode", articleID: nil))
        }
        f.onRead = { _ in events.append("read") }
        f.store.changeContext(to: .confirmed(userID: "B"))
        XCTAssertEqual(events, ["stop", "read"])
        XCTAssertNil(f.store.snapshot.lastPlayedEpisodeID)
    }

    func testReentrantHookCannotRestoreTheSupersededAccount() throws {
        let f = PodcastProgressMemory()
        let b = PodcastProgressContext.confirmed(userID: "B")
        f.store.onContextInvalidated = {
            f.store.onContextInvalidated = nil
            f.store.changeContext(to: .unresolved)
        }
        f.store.changeContext(to: b)
        XCTAssertEqual(f.store.context, .unresolved)
        XCTAssertEqual(f.store.snapshot.state, .unresolved)
        XCTAssertEqual(f.reads, [.guest])
        XCTAssertNil(f.store.snapshot.lastPlayedEpisodeID)
    }

    func testReentrantReadLoadsOnlyLatestAccountAfterOriginalEffectFinishes() throws {
        let f = PodcastProgressMemory(context: .unresolved)
        let a = PodcastProgressContext.confirmed(userID: "A")
        let b = PodcastProgressContext.confirmed(userID: "B")
        try f.seed(XCTUnwrap(a.namespace), seconds: 42)
        try f.seed(XCTUnwrap(b.namespace), seconds: 84)
        f.onRead = { _ in
            f.onRead = nil
            f.store.changeContext(to: b)
        }
        f.store.changeContext(to: a)
        XCTAssertEqual(f.store.context, b)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 84)
        XCTAssertEqual(f.store.snapshot.state, .ready)
        XCTAssertEqual(f.reads, [try XCTUnwrap(a.namespace), try XCTUnwrap(b.namespace)])
    }

    func testReentrantWriteCannotPublishOrPersistOldPlaybackIntoNewAccount() throws {
        let a = PodcastProgressContext.confirmed(userID: "A")
        let b = PodcastProgressContext.confirmed(userID: "B")
        let f = PodcastProgressMemory(context: a)
        let old = try f.begin("episode")
        f.onWrite = { _, _ in
            f.onWrite = nil
            f.store.changeContext(to: b)
        }
        XCTAssertEqual(f.store.save(old.ticket, seconds: 42, duration: 600), .stale)
        XCTAssertEqual(f.store.context, b)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertNil(f.records[try XCTUnwrap(b.namespace)])
        XCTAssertNotNil(f.records[try XCTUnwrap(a.namespace)])
    }

    func testReadFailureClosesWritesUntilSuccessfulExplicitRetry() throws {
        let f = PodcastProgressMemory(context: .unresolved)
        f.failReads = true
        f.store.changeContext(to: .guest)
        XCTAssertEqual(f.store.snapshot.state, .readFailed)
        XCTAssertTrue(f.store.snapshot.canRetry)
        XCTAssertNotNil(f.store.snapshot.issueMessage)
        let s = try f.begin("episode")
        XCTAssertNil(s.resumePosition)
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .unavailable)
        XCTAssertTrue(f.writes.isEmpty)
        f.failReads = false
        f.store.retryStorage()
        XCTAssertEqual(f.store.snapshot.state, .ready)
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .written)
    }

    func testCorruptAndUnsupportedRecordsAreNotOverwrittenOrAdoptedFromAnotherOwner() throws {
        let a = PodcastProgressContext.confirmed(userID: "A")
        let b = PodcastProgressContext.confirmed(userID: "B")
        let f = PodcastProgressMemory(context: a)
        f.store.save(try f.begin("episode").ticket, seconds: 42, duration: 600)
        let copied = try XCTUnwrap(f.records[try XCTUnwrap(a.namespace)])
        f.records[try XCTUnwrap(b.namespace)] = copied
        f.store.changeContext(to: b)
        XCTAssertEqual(f.store.snapshot.state, .invalidRecord)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertEqual(f.store.save(try f.begin("episode").ticket, seconds: 84, duration: 600), .unavailable)
        XCTAssertEqual(f.records[try XCTUnwrap(b.namespace)], copied)
        let unsupported = Data("{\"schemaVersion\":2,\"namespace\":\"guest\",\"entries\":[]}".utf8)
        f.records[.guest] = unsupported
        f.store.changeContext(to: .guest)
        XCTAssertEqual(f.store.snapshot.state, .unsupportedVersion)
        XCTAssertEqual(f.store.save(try f.begin("episode").ticket, seconds: 84, duration: 600), .unavailable)
        XCTAssertEqual(f.records[.guest], unsupported)
    }

    func testWriteFailureKeepsVisibleUnconfirmedPositionAndRetriesSameOwnerOnly() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode", article: "article")
        f.failWrites = true
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .unavailable)
        XCTAssertEqual(f.store.snapshot.state, .writeFailed)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
        XCTAssertEqual(f.store.snapshot.lastPlayedArticleID, "article")
        XCTAssertTrue(f.store.snapshot.canRetry)
        XCTAssertFalse(try XCTUnwrap(f.store.snapshot.issueMessage).contains("privateStorageFailure"))
        XCTAssertNil(f.records[.guest])
        f.failWrites = false
        f.store.retryStorage()
        XCTAssertEqual(f.store.snapshot.state, .ready)
        XCTAssertNil(f.store.snapshot.issueMessage)
        let record = try PodcastProgressRecordCodec.decode(XCTUnwrap(f.records[.guest]), namespace: .guest)
        XCTAssertEqual(record.entries.first?.positionSeconds, 42)
    }

    func testFailedCompletionStillBlocksLateWritesAndRetryCannotResurrectProgress() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode")
        f.store.save(s.ticket, seconds: 42, duration: 600)
        f.failWrites = true
        XCTAssertEqual(f.store.complete(s.ticket), .unavailable)
        XCTAssertTrue(f.store.isCurrent(s.ticket))
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .stale)
        XCTAssertEqual(f.store.complete(s.ticket), .stale)
        f.failWrites = false
        f.store.retryStorage()
        let cold = PodcastPlaybackProgressStore(storage: .init(read: { f.records[$0] }, write: { _, _ in XCTFail() }))
        cold.changeContext(to: .guest)
        XCTAssertNil(cold.snapshot.position(for: "episode"))
        XCTAssertEqual(cold.snapshot.state, .ready)
    }

    func testCompletionDuringReadFailureIsAppliedAfterRetryWithoutLateSave() throws {
        let f = PodcastProgressMemory(context: .unresolved)
        try f.seed(.guest)
        f.failReads = true
        f.store.changeContext(to: .guest)
        let s = try f.begin("episode")
        XCTAssertEqual(f.store.complete(s.ticket), .unavailable)
        f.failReads = false
        f.store.retryStorage()
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertTrue(f.store.isCurrent(s.ticket))
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .stale)
        XCTAssertTrue(try PodcastProgressRecordCodec.decode(XCTUnwrap(f.records[.guest]), namespace: .guest).entries.isEmpty)
    }

    func testReplayingSameEpisodeRejectsOlderSessionCallbacks() throws {
        let f = PodcastProgressMemory()
        let old = try f.begin("episode")
        f.store.save(old.ticket, seconds: 42, duration: 600)
        let current = try f.begin("episode")
        f.store.save(current.ticket, seconds: 84, duration: 600)
        XCTAssertEqual(f.store.complete(old.ticket), .stale)
        XCTAssertEqual(f.store.save(old.ticket, seconds: 500, duration: 600), .stale)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 84)
    }

    func testRetentionIsBoundedAndLastPointerAlwaysReferencesTheLatestRetainedEntry() throws {
        let f = PodcastProgressMemory()
        for i in 0..<105 {
            f.store.save(try f.begin("episode-\(i)", article: "article-\(i)").ticket, seconds: 42, duration: 600)
        }
        let record = try PodcastProgressRecordCodec.decode(XCTUnwrap(f.records[.guest]), namespace: .guest)
        XCTAssertEqual(record.entries.count, 100)
        XCTAssertNil(f.store.snapshot.position(for: "episode-4"))
        XCTAssertEqual(f.store.snapshot.position(for: "episode-5"), 42)
        XCTAssertEqual(f.store.snapshot.lastPlayedEpisodeID, "episode-104")
        XCTAssertTrue(f.writes.allSatisfy { $0.1.count <= PodcastProgressRecordCodec.maximumRecordBytes })
    }

    func testReentrantPublicationCannotOverwriteNewerAccountSnapshot() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode")
        f.store.save(s.ticket, seconds: 42, duration: 600)
        let b = PodcastProgressContext.confirmed(userID: "B")
        var calls = 0
        let observer = f.store.objectWillChange.sink {
            calls += 1
            f.store.changeContext(to: b)
        }
        XCTAssertEqual(f.store.save(s.ticket, seconds: 84, duration: 600), .stale)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(f.store.context, b)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertEqual(f.store.snapshot.state, .ready)
        withExtendedLifetime(observer) {}
    }

    func testReentrantNestedWriteIsRejectedBeforeItCanBeOverwrittenByOuterAdapter() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode")
        f.onWrite = { _, _ in
            XCTAssertEqual(f.store.save(s.ticket, seconds: 84, duration: 600), .unavailable)
            XCTAssertNil(f.store.beginSession(episodeID: "other", articleID: nil))
        }
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .written)
        XCTAssertEqual(f.writes.count, 1)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
    }

    func testReentrantCompletionMaintainsBarrierEvenIfOuterWriteCommitsAfterIt() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode")
        f.onWrite = { _, _ in
            f.onWrite = nil
            XCTAssertEqual(f.store.complete(s.ticket), .unavailable)
        }
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .stale)
        XCTAssertTrue(f.store.isCurrent(s.ticket))
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertEqual(f.store.snapshot.state, .writeFailed)
        f.store.retryStorage()
        XCTAssertTrue(try PodcastProgressRecordCodec.decode(XCTUnwrap(f.records[.guest]), namespace: .guest).entries.isEmpty)
    }

    func testInvalidSessionIDsCannotReplaceAnExistingPlaybackTicket() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode")
        for invalid in ["", " ", " bad", "bad\n", String(repeating: "ø", count: 257)] {
            XCTAssertNil(f.store.beginSession(episodeID: invalid, articleID: nil))
            XCTAssertNil(f.store.beginSession(episodeID: "episode", articleID: invalid))
            XCTAssertTrue(f.store.isCurrent(s.ticket))
        }
    }

    func testReentrantEndInvalidatesPlaybackWithoutHidingAnInFlightWriteFailure() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode")
        f.failWrites = true
        f.onWrite = { _, _ in f.store.endSession(s.ticket) }
        XCTAssertEqual(f.store.save(s.ticket, seconds: 42, duration: 600), .unavailable)
        XCTAssertFalse(f.store.isCurrent(s.ticket))
        XCTAssertEqual(f.store.snapshot.state, .writeFailed)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
        f.failWrites = false
        f.onWrite = nil
        f.store.retryStorage()
        XCTAssertEqual(f.store.snapshot.state, .ready)
        XCTAssertNotNil(f.records[.guest])
    }

    func testPersistentReadFailureHasBoundedConservativeCompletionRecovery() throws {
        let f = PodcastProgressMemory(context: .unresolved)
        try f.seed(.guest)
        let original = f.records[.guest]
        f.failReads = true
        f.store.changeContext(to: .guest)
        for i in 0...100 { f.store.complete(try f.begin("unreadable-\(i)").ticket) }
        XCTAssertEqual(f.store.snapshot.state, .recoveryLimited)
        XCTAssertFalse(f.store.snapshot.canRetry)
        XCTAssertNotNil(f.store.snapshot.issueMessage)
        f.failReads = false
        f.store.retryStorage()
        XCTAssertEqual(f.reads.count, 1)
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertEqual(f.records[.guest], original)
        XCTAssertNil(f.store.snapshot.lastPlayedEpisodeID)
    }

    func testSuccessfulCompletionsDoNotExhaustFailedReadRecoveryBudget() throws {
        let f = PodcastProgressMemory()
        for i in 0..<150 { f.store.complete(try f.begin("completed-\(i)").ticket) }
        XCTAssertEqual(f.store.snapshot.state, .ready)
        XCTAssertNil(f.store.snapshot.issueMessage)
        XCTAssertEqual(f.writes.count, 150)
    }
}
