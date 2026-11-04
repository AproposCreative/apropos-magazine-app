import XCTest
@testable import Apropos

@MainActor
final class PodcastPlaybackProgressStoreTests: XCTestCase {
    func testPlayButtonTitleDefaultsToLyt() {
        let f = PodcastProgressMemory()
        XCTAssertEqual(f.store.snapshot.playButtonTitle(for: "episode-1"), "Lyt")
        XCTAssertEqual(f.store.snapshot.articlePlayButtonTitle(for: "episode-1"), "Lyt til artiklen")
    }

    func testSaveAndResumeProgress() throws {
        let f = PodcastProgressMemory()
        let session = try f.begin("episode-1")
        XCTAssertEqual(f.store.save(session.ticket, seconds: 42, duration: 600), .written)
        XCTAssertTrue(f.store.snapshot.hasResumableProgress(for: "episode-1"))
        XCTAssertEqual(f.store.snapshot.playButtonTitle(for: "episode-1"), "Fortsæt")
        XCTAssertEqual(f.store.snapshot.articlePlayButtonTitle(for: "episode-1"), "Fortsæt lytning")
        XCTAssertEqual(f.store.snapshot.position(for: "episode-1"), 42)
        XCTAssertEqual(try f.begin("episode-1").resumePosition, 42)
    }

    func testNearCompletionClearsProgress() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode-2")
        f.store.save(s.ticket, seconds: 42, duration: 600)
        f.store.save(s.ticket, seconds: 590, duration: 600)
        XCTAssertNil(f.store.snapshot.position(for: "episode-2"))
        XCTAssertFalse(f.store.snapshot.hasResumableProgress(for: "episode-2"))
        XCTAssertTrue(f.store.isCurrent(s.ticket))
    }

    func testMarkLastPlayedStoresArticleIdInSameRecordAsPosition() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode-3", article: "article-3")
        f.store.save(s.ticket, seconds: 42, duration: 600)
        XCTAssertEqual(f.store.snapshot.lastPlayedEpisodeID, "episode-3")
        XCTAssertEqual(f.store.snapshot.lastPlayedArticleID, "article-3")
        XCTAssertEqual(f.writes.count, 1)
        let stored = try PodcastProgressRecordCodec.decode(XCTUnwrap(f.records[.guest]), namespace: .guest)
        XCTAssertEqual(stored.lastEpisodeID, "episode-3")
        XCTAssertEqual(stored.entries.first?.articleID, "article-3")
    }

    func testUnknownDurationDoesNotEraseSavedResumePositionOrIdentifiers() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode-loading", article: "article-loading")
        f.store.save(s.ticket, seconds: 120, duration: 600)
        let durations: [TimeInterval?] = [nil, 0, -.infinity, .infinity, .nan]
        for duration in durations {
            for seconds in [0.0, 120.0] {
                f.store.save(s.ticket, seconds: seconds, duration: duration)
                XCTAssertEqual(f.store.snapshot.position(for: "episode-loading"), 120)
                XCTAssertEqual(f.store.snapshot.lastPlayedEpisodeID, "episode-loading")
                XCTAssertEqual(f.store.snapshot.lastPlayedArticleID, "article-loading")
            }
        }
        XCTAssertEqual(f.writes.count, 1)
    }

    func testNonFinitePositionDoesNotEraseSavedResume() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("episode-invalid-time")
        f.store.save(s.ticket, seconds: 120, duration: 600)
        for seconds in [TimeInterval.nan, .infinity, -.infinity, 1e300] {
            f.store.save(s.ticket, seconds: seconds, duration: 600)
            XCTAssertEqual(f.store.snapshot.position(for: "episode-invalid-time"), 120)
        }
        XCTAssertEqual(f.writes.count, 1)
    }

    func testShortEpisodeIsNotCompletedAtItsStart() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("short")
        f.store.save(s.ticket, seconds: 5, duration: 10)
        XCTAssertEqual(f.store.snapshot.position(for: "short"), 5)
        f.store.save(s.ticket, seconds: 10, duration: 10)
        XCTAssertNil(f.store.snapshot.position(for: "short"))
    }

    func testNewEpisodeWithoutArticleDoesNotKeepPreviousArticleIdentifier() throws {
        let f = PodcastProgressMemory()
        f.store.save(try f.begin("previous", article: "previous-article").ticket, seconds: 42, duration: 600)
        f.store.save(try f.begin("new").ticket, seconds: 42, duration: 600)
        XCTAssertEqual(f.store.snapshot.lastPlayedEpisodeID, "new")
        XCTAssertNil(f.store.snapshot.lastPlayedArticleID)
    }

    func testConfirmedShortEpisodeEndClearsLaggingTickAndBlocksLateWrites() throws {
        let f = PodcastProgressMemory()
        let s = try f.begin("finished-short", article: "article")
        f.store.save(s.ticket, seconds: 9, duration: 10)
        f.store.complete(s.ticket)
        XCTAssertTrue(f.store.isCurrent(s.ticket))
        for _ in 0..<3 { XCTAssertEqual(f.store.save(s.ticket, seconds: 9, duration: 10), .stale) }
        XCTAssertNil(f.store.snapshot.position(for: "finished-short"))
        XCTAssertNil(f.store.snapshot.lastPlayedEpisodeID)
        XCTAssertNil(f.store.snapshot.lastPlayedArticleID)
        // Only a new explicit replay/manual-seek session can lift the barrier.
        let replay = try f.begin("finished-short", article: "article")
        XCTAssertNil(replay.resumePosition)
        f.store.save(replay.ticket, seconds: 5, duration: 10)
        XCTAssertEqual(f.store.snapshot.position(for: "finished-short"), 5)
    }

    func testCompletingOldEpisodeDoesNotClearNewEpisodesIdentifiers() throws {
        let f = PodcastProgressMemory()
        let old = try f.begin("old")
        f.store.save(old.ticket, seconds: 9, duration: 10)
        let current = try f.begin("new", article: "new-article")
        f.store.save(current.ticket, seconds: 42, duration: 600)
        XCTAssertEqual(f.store.complete(old.ticket), .stale)
        XCTAssertEqual(f.store.snapshot.position(for: "old"), 9)
        XCTAssertEqual(f.store.snapshot.lastPlayedEpisodeID, "new")
        XCTAssertEqual(f.store.snapshot.lastPlayedArticleID, "new-article")
    }
}

/// Every test owns this fresh in-memory adapter; there are no defaults suites,
/// production singletons, Firebase, timers or platform players in the fixture.
@MainActor
final class PodcastProgressMemory {
    enum Failure: Error { case privateStorageFailure }
    var records: [PodcastProgressNamespace: Data] = [:]
    var reads: [PodcastProgressNamespace] = []
    var writes: [(PodcastProgressNamespace, Data)] = []
    var failReads = false
    var failWrites = false
    var onRead: ((PodcastProgressNamespace) -> Void)?
    var onWrite: ((PodcastProgressNamespace, Data) -> Void)?
    lazy var store = PodcastPlaybackProgressStore(storage: .init(read: { [weak self] namespace in
        guard let self else { throw Failure.privateStorageFailure }
        self.reads.append(namespace)
        self.onRead?(namespace)
        if self.failReads { throw Failure.privateStorageFailure }
        return self.records[namespace]
    }, write: { [weak self] namespace, data in
        guard let self else { throw Failure.privateStorageFailure }
        self.writes.append((namespace, data))
        self.onWrite?(namespace, data)
        if self.failWrites { throw Failure.privateStorageFailure }
        self.records[namespace] = data
    }))

    init(context: PodcastProgressContext = .guest) { store.changeContext(to: context) }

    func begin(_ episode: String, article: String? = nil) throws -> PodcastPlaybackProgressStore.Session {
        try XCTUnwrap(store.beginSession(episodeID: episode, articleID: article))
    }

    func seed(_ namespace: PodcastProgressNamespace, episode: String = "episode", seconds: Double = 42) throws {
        records[namespace] = try PodcastProgressRecordCodec.encode(.init(entries: [
            .init(episodeID: episode, articleID: "article", positionSeconds: seconds, durationSeconds: 600)
        ], lastEpisodeID: episode), namespace: namespace)
    }
}
