import XCTest
@testable import Apropos

@MainActor
final class PodcastPlaybackSessionCoordinatorTests: XCTestCase {
    func testUnresolvedContextCannotAdoptAnItemOrStartEffects() {
        let f = PlaybackCoordinatorFixture(context: .unresolved)
        XCTAssertNil(f.coordinator.beginSession(episodeID: "episode", articleID: nil))
        XCTAssertNil(f.coordinator.currentTicket)
        XCTAssertTrue(f.effects.isEmpty)
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testActualStoreContextHookStopsPlayerBeforeReadingTheNewOwner() throws {
        let f = PlaybackCoordinatorFixture(context: .confirmed(userID: "reader-A"))
        let old = try f.begin("same-episode")
        f.coordinator.save(old, seconds: 42, duration: 600)
        f.events = []
        f.store.changeContext(to: .confirmed(userID: "reader-B"))
        XCTAssertEqual(Array(f.events.prefix(5)), PlaybackCoordinatorFixture.teardownOrder)
        XCTAssertEqual(f.events.last, "read")
        XCTAssertFalse(f.coordinator.isCurrent(old))
        XCTAssertNil(f.coordinator.currentTicket)
        XCTAssertNil(f.store.snapshot.position(for: "same-episode"))
    }

    func testAtoGuestToAWithSameEpisodeNeverRevivesOldCallbackAuthority() throws {
        let f = PlaybackCoordinatorFixture(context: .confirmed(userID: "reader-A"))
        let old = try f.begin("same-episode")
        let delayed = f.callback(old, name: "remote-play")
        f.store.changeContext(to: .guest)
        _ = try f.begin("same-episode")
        f.store.changeContext(to: .confirmed(userID: "reader-A"))
        let current = try f.begin("same-episode")
        delayed()
        XCTAssertTrue(f.callbackEffects.isEmpty)
        XCTAssertFalse(f.coordinator.isCurrent(old))
        XCTAssertTrue(f.coordinator.isCurrent(current))
    }

    func testIdenticalCanonicalContextKeepsCurrentPlaybackAndDoesNotTearDown() throws {
        let f = PlaybackCoordinatorFixture(context: .confirmed(userID: "reader-A"))
        let ticket = try f.begin("episode")
        let context = f.coordinator.contextTicket
        f.store.changeContext(to: .confirmed(userID: "reader-A"))
        XCTAssertTrue(f.coordinator.isCurrent(ticket))
        XCTAssertEqual(f.coordinator.contextTicket, context)
        XCTAssertTrue(f.effects.isEmpty)
    }

    func testCloseInvalidatesBeforeEveryTeardownEffectAndIsIdempotent() throws {
        let f = PlaybackCoordinatorFixture()
        let ticket = try f.begin("episode")
        f.onEffect = {
            XCTAssertFalse(f.coordinator.isCurrent(ticket))
            XCTAssertFalse(f.coordinator.save(ticket, seconds: 90, duration: 600))
            XCTAssertFalse(f.coordinator.perform(ifCurrent: ticket) { XCTFail("Old effect must be denied") })
        }
        f.coordinator.close()
        f.coordinator.close()
        XCTAssertEqual(f.effects, PlaybackCoordinatorFixture.teardownOrder)
        XCTAssertTrue(f.writes.isEmpty, "Teardown must neither save under a new owner nor start a cache write")
    }

    func testQueuedSystemCallbacksCannotMutateClosedOrNewEpisode() throws {
        let f = PlaybackCoordinatorFixture()
        let old = try f.begin("old")
        let callbacks = ["kvo", "periodic", "end", "seek", "artwork", "route", "interruption", "remote", "deferred-cache"].map {
            f.callback(old, name: $0)
        }
        f.coordinator.close()
        let next = try f.begin("new")
        callbacks.forEach { $0() }
        XCTAssertTrue(f.callbackEffects.isEmpty)
        XCTAssertFalse(f.coordinator.save(old, seconds: 99, duration: 600))
        XCTAssertFalse(f.coordinator.complete(old))
        XCTAssertTrue(f.coordinator.perform(ifCurrent: next) { f.callbackEffects.append("current") })
        XCTAssertEqual(f.callbackEffects, ["current"])
    }

    func testReentrantAdoptionDuringActualTeardownIsDeniedUntilCleanupFinishes() throws {
        let f = PlaybackCoordinatorFixture()
        _ = try f.begin("old")
        f.onEffect = {
            XCTAssertNil(f.coordinator.beginSession(episodeID: "nested", articleID: nil))
            f.store.changeContext(to: .confirmed(userID: "reader-B"))
        }
        f.coordinator.close()
        XCTAssertEqual(f.effects, PlaybackCoordinatorFixture.teardownOrder)
        XCTAssertNil(f.coordinator.currentTicket)
        f.onEffect = nil
        XCTAssertNotNil(f.coordinator.beginSession(episodeID: "new", articleID: nil))
    }

    func testStartCapturedBeforeContextChangeCannotAdoptIntoTheNewOwner() throws {
        let f = PlaybackCoordinatorFixture()
        let origin = f.coordinator.contextTicket
        f.store.changeContext(to: .confirmed(userID: "reader-B"))
        XCTAssertNil(f.coordinator.beginSession(episodeID: "stale-start", articleID: nil, expectedContext: origin))
        XCTAssertNil(f.coordinator.currentTicket)
    }

    func testPendingSeekPreventsProgressSaveAndOldCompletionCannotClearNewSeek() throws {
        let f = PlaybackCoordinatorFixture()
        let ticket = try f.begin("episode")
        f.coordinator.save(ticket, seconds: 42, duration: 600)
        let old = try XCTUnwrap(f.coordinator.beginManualSeek(ticket))
        XCTAssertFalse(f.coordinator.save(ticket, seconds: 300, duration: 600))
        let current = try XCTUnwrap(f.coordinator.beginManualSeek(ticket))
        XCTAssertFalse(f.coordinator.finishManualSeek(old, observedPosition: 300))
        XCTAssertFalse(f.coordinator.canPublishProgress(ticket))
        XCTAssertTrue(f.coordinator.finishManualSeek(current, observedPosition: 120))
        XCTAssertTrue(f.coordinator.save(ticket, seconds: 120, duration: 600))
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 120)
    }

    func testPauseAndInterruptionKeepUnconfirmedSeekTargetBehindSaveBarrier() throws {
        let f = PlaybackCoordinatorFixture()
        let ticket = try f.begin("episode")
        f.coordinator.save(ticket, seconds: 42, duration: 600)
        let seek = try XCTUnwrap(f.coordinator.beginManualSeek(ticket))
        f.coordinator.recordExplicitAction() // Actual pause uses this before cancelling AV's seek.
        f.coordinator.beginInterruption(ticket, wantedPlayback: false)
        XCTAssertFalse(f.coordinator.save(ticket, seconds: 500, duration: 600))
        for unknown: TimeInterval? in [nil, .nan, .infinity, -1, 1e300] {
            XCTAssertFalse(f.coordinator.finishManualSeek(seek, observedPosition: unknown))
        }
        XCTAssertFalse(f.coordinator.canPublishProgress(ticket))
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
        XCTAssertTrue(f.coordinator.finishManualSeek(seek, observedPosition: 43))
        f.coordinator.save(ticket, seconds: 43, duration: 600)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 43)
    }

    func testOldSeekCompletionCannotLandInSameEpisodeAfterAccountSwitch() throws {
        let f = PlaybackCoordinatorFixture()
        let old = try f.begin("episode")
        let seek = try XCTUnwrap(f.coordinator.beginManualSeek(old))
        f.store.changeContext(to: .confirmed(userID: "reader-B"))
        let current = try f.begin("episode")
        XCTAssertFalse(f.coordinator.finishManualSeek(seek, observedPosition: 90))
        XCTAssertTrue(f.coordinator.canPublishProgress(current))
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testConfirmedEndCanBeReopenedByExplicitScrubAndSave() throws {
        let f = PlaybackCoordinatorFixture()
        let old = try f.begin("episode")
        f.coordinator.save(old, seconds: 42, duration: 600)
        XCTAssertTrue(f.coordinator.complete(old))
        XCTAssertTrue(f.coordinator.isCurrent(old))
        let current = try f.begin("episode") // Actual manual scrub renews ownership even on the same item.
        let seek = try XCTUnwrap(f.coordinator.beginManualSeek(current))
        XCTAssertTrue(f.coordinator.finishManualSeek(seek, observedPosition: 120))
        f.coordinator.save(current, seconds: 120, duration: 600)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 120)
        XCTAssertFalse(f.coordinator.complete(old))
    }

    func testNearEndStoreCompletionAlsoRequiresNewScrubSession() throws {
        let f = PlaybackCoordinatorFixture()
        let old = try f.begin("episode")
        f.coordinator.save(old, seconds: 590, duration: 600)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        let current = try f.begin("episode")
        let seek = try XCTUnwrap(f.coordinator.beginManualSeek(current))
        XCTAssertTrue(f.coordinator.finishManualSeek(seek, observedPosition: 120))
        f.coordinator.save(current, seconds: 120, duration: 600)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 120)
    }

    func testSleepTimerSurvivesEpisodeAdvanceButNotReplacementOffCloseOrNewContext() throws {
        let f = PlaybackCoordinatorFixture()
        _ = try f.begin("episode-A")
        let acrossEpisodes = try XCTUnwrap(f.coordinator.beginSleepTimer())
        _ = try f.begin("episode-B")
        XCTAssertTrue(f.coordinator.consumeSleepTimer(acrossEpisodes))
        XCTAssertFalse(f.coordinator.consumeSleepTimer(acrossEpisodes))
        let old = try XCTUnwrap(f.coordinator.beginSleepTimer())
        let replacement = try XCTUnwrap(f.coordinator.beginSleepTimer())
        XCTAssertFalse(f.coordinator.consumeSleepTimer(old))
        f.coordinator.invalidateSleepTimer()
        XCTAssertFalse(f.coordinator.consumeSleepTimer(replacement))
        let closing = try XCTUnwrap(f.coordinator.beginSleepTimer())
        f.coordinator.close()
        _ = try f.begin("episode-B")
        XCTAssertFalse(f.coordinator.consumeSleepTimer(closing))
        let context = try XCTUnwrap(f.coordinator.beginSleepTimer())
        f.store.changeContext(to: .confirmed(userID: "reader-B"))
        _ = try f.begin("episode-B")
        XCTAssertFalse(f.coordinator.consumeSleepTimer(context))
    }

    func testInterruptionResumeRequiresMatchingBeginPriorIntentAndNoExplicitPause() throws {
        let f = PlaybackCoordinatorFixture()
        let ticket = try f.begin("episode")
        XCTAssertFalse(f.coordinator.endInterruption(ticket, shouldResume: true))
        f.coordinator.beginInterruption(ticket, wantedPlayback: false)
        XCTAssertFalse(f.coordinator.endInterruption(ticket, shouldResume: true))
        f.coordinator.beginInterruption(ticket, wantedPlayback: true)
        f.coordinator.recordExplicitAction()
        XCTAssertFalse(f.coordinator.endInterruption(ticket, shouldResume: true))
        f.coordinator.beginInterruption(ticket, wantedPlayback: true)
        XCTAssertFalse(f.coordinator.endInterruption(ticket, shouldResume: false))
        f.coordinator.beginInterruption(ticket, wantedPlayback: true)
        XCTAssertTrue(f.coordinator.endInterruption(ticket, shouldResume: true))
        XCTAssertFalse(f.coordinator.endInterruption(ticket, shouldResume: true))
    }

    func testDuplicateInterruptionBeginDoesNotEraseOriginalPlaybackIntent() throws {
        let f = PlaybackCoordinatorFixture()
        let ticket = try f.begin("episode")
        f.coordinator.beginInterruption(ticket, wantedPlayback: true)
        f.coordinator.beginInterruption(ticket, wantedPlayback: false)
        XCTAssertTrue(f.coordinator.endInterruption(ticket, shouldResume: true))
    }

    func testInterruptionFromOldItemCannotResumeReplacementEvenWithSameEpisodeID() throws {
        let f = PlaybackCoordinatorFixture()
        let old = try f.begin("episode")
        f.coordinator.beginInterruption(old, wantedPlayback: true)
        _ = try f.begin("episode")
        XCTAssertFalse(f.coordinator.endInterruption(old, shouldResume: true))
    }

    func testReentrantStorageContextChangeCannotPublishOldCallbackEffects() throws {
        let f = PlaybackCoordinatorFixture()
        let old = try f.begin("episode")
        f.onWrite = { f.store.changeContext(to: .confirmed(userID: "reader-B")) }
        XCTAssertFalse(f.coordinator.save(old, seconds: 42, duration: 600))
        XCTAssertFalse(f.coordinator.perform(ifCurrent: old) { f.callbackEffects.append("old-metadata") })
        XCTAssertEqual(f.effects, PlaybackCoordinatorFixture.teardownOrder)
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
        XCTAssertTrue(f.callbackEffects.isEmpty)
    }

    func testSavedResumeIsCheckedAgainstCurrentAssetBeforeCMTimeConstruction() {
        XCTAssertEqual(PodcastPlaybackSessionCoordinator.safeResumePosition(120, currentDuration: 600), 120)
        for duration: TimeInterval? in [nil, 0, .nan, .infinity, -1, 100, 120, 1e300] {
            XCTAssertEqual(PodcastPlaybackSessionCoordinator.safeResumePosition(120, currentDuration: duration), 0)
        }
        for saved in [TimeInterval.nan, .infinity, -1, 1e300] {
            XCTAssertEqual(PodcastPlaybackSessionCoordinator.safeResumePosition(saved, currentDuration: 600), 0)
        }
        XCTAssertEqual(PodcastPlaybackSessionCoordinator.safeResumePosition(0, currentDuration: 600), 0)
    }
}

@MainActor
private final class PlaybackCoordinatorFixture {
    static let teardownOrder = ["cancel", "stop", "clear-presentation", "clear-now-playing", "deactivate"]
    var records: [PodcastProgressNamespace: Data] = [:]
    var writes: [PodcastProgressNamespace] = []
    var effects: [String] = []
    var events: [String] = []
    var callbackEffects: [String] = []
    var onEffect: (@MainActor () -> Void)?
    var onWrite: (@MainActor () -> Void)?

    lazy var store = PodcastPlaybackProgressStore(storage: .init(read: { [unowned self] namespace in
        self.events.append("read")
        return self.records[namespace]
    }, write: { [unowned self] namespace, data in
        self.records[namespace] = data
        self.writes.append(namespace)
        let hook = self.onWrite
        self.onWrite = nil
        hook?()
    }))
    lazy var coordinator = PodcastPlaybackSessionCoordinator(store: store, effects: .init(
        cancelCallbacks: { [unowned self] in self.effect("cancel") },
        stopPlayback: { [unowned self] in self.effect("stop") },
        clearPresentation: { [unowned self] in self.effect("clear-presentation") },
        clearNowPlaying: { [unowned self] in self.effect("clear-now-playing") },
        deactivateAudio: { [unowned self] in self.effect("deactivate") }
    ))

    init(context: PodcastProgressContext = .guest) {
        _ = coordinator
        // The actual manager installs this same synchronous hook after init.
        store.onContextInvalidated = { [weak self] in self?.coordinator.contextInvalidated() }
        store.changeContext(to: context)
        effects = []
        events = []
    }

    func begin(_ episode: String) throws -> PodcastPlaybackSessionCoordinator.Ticket {
        try XCTUnwrap(coordinator.beginSession(episodeID: episode, articleID: "article-" + episode)).ticket
    }

    func callback(_ ticket: PodcastPlaybackSessionCoordinator.Ticket, name: String) -> @MainActor () -> Void {
        { [unowned self] in self.coordinator.perform(ifCurrent: ticket) { self.callbackEffects.append(name) } }
    }

    private func effect(_ name: String) {
        effects.append(name)
        events.append(name)
        onEffect?()
    }
}
