import Combine
import XCTest
@testable import Apropos

/// Actual progress runtime/session ownership with local storage and player
/// effects. No AVPlayer, audio session, Firebase or network is constructed.
@MainActor
final class PodcastProgressRecoveryTests: XCTestCase {
    @MainActor private final class Memory {
        var records: [String: Data] = [:]
        var factories = 0, reads = 0, writes = 0
        var onFactory: (@MainActor () -> Void)?
        var onRead: (@MainActor () -> Void)?
        var onWrite: (@MainActor () -> Void)?
        var failsRead = false, failsWrite = false
        private enum Failure: Error { case injected }
        func runtime(_ recovery: ReaderTransitionRecovery?, disabled: Bool = false) -> PodcastProgressRuntime {
            PodcastProgressRuntime(disabled: disabled, storageFactory: { [self] in
                factories += 1; onFactory?()
                return .init(read: { [self] namespace in
                    reads += 1; onRead?()
                    if failsRead { throw Failure.injected }
                    return records[namespace.storageKey]
                }, write: { [self] namespace, data in
                    writes += 1; onWrite?()
                    if failsWrite { throw Failure.injected }
                    records[namespace.storageKey] = data
                })
            }, recovery: recovery)
        }
    }

    @MainActor private final class Fixture {
        let directory: URL, recovery: ReaderTransitionRecovery
        let memory = Memory()
        var effects: [String] = []
        var invalidations = 0
        var onEffect: (@MainActor () -> Void)?
        var onInvalidation: (@MainActor () -> Void)?
        lazy var runtime = memory.runtime(recovery)
        lazy var player: PodcastPlaybackSessionCoordinator = {
            let value = PodcastPlaybackSessionCoordinator(store: runtime.model, effects: .init(
                cancelCallbacks: { [unowned self] in effect("cancel") },
                stopPlayback: { [unowned self] in effect("stop") },
                clearPresentation: { [unowned self] in effect("presentation") },
                clearNowPlaying: { [unowned self] in effect("nowPlaying") },
                deactivateAudio: { [unowned self] in effect("deactivate") }))
            runtime.model.onContextInvalidated = { [unowned self, weak value] in
                invalidations += 1; onInvalidation?(); value?.contextInvalidated()
            }
            return value
        }()
        init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        }
        func effect(_ name: String) { effects.append(name); onEffect?() }
        func prepare(_ uid: String? = "reader-A") async throws {
            try await recovery.bootstrap()
            _ = player
            runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: uid)
        }
        func begin(_ episode: String = "episode") throws -> PodcastPlaybackSessionCoordinator.Ticket {
            try XCTUnwrap(player.beginSession(episodeID: episode, articleID: "article")).ticket
        }
        func seal() async throws { _ = try await recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 1)) }
        /// An injected synchronous hook exercises the exact admission edge;
        /// this seam does not claim that a durable marker was written.
        func closeAtHook(notify: Bool = true) {
            recovery.admission.setAllowed(false)
            if notify { recovery.changes.send() }
        }
        func decoded(_ uid: String?) throws -> PodcastProgressRecord {
            let namespace = try XCTUnwrap(PodcastProgressContext.confirmed(userID: uid).namespace)
            return try PodcastProgressRecordCodec.decode(XCTUnwrap(memory.records[namespace.storageKey]), namespace: namespace)
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    func testOriginalPlaybackCannotSaveOrCompleteAfterActualRecoverySeal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        try await recovery.bootstrap()
        var records: [String: Data] = [:], writes = 0
        // The unchanged assertions reproduced two post-seal writes before
        // connecting the existing runtime to this same recovery instance.
        let runtime = PodcastProgressRuntime(disabled: false, storageFactory: {
            .init(read: { records[$0.storageKey] }, write: { namespace, data in
                writes += 1; records[namespace.storageKey] = data
            })
        }, recovery: recovery)
        let player = PodcastPlaybackSessionCoordinator(store: runtime.model, effects: .init(
            cancelCallbacks: {}, stopPlayback: {}, clearPresentation: {}, clearNowPlaying: {}, deactivateAudio: {}))
        runtime.model.onContextInvalidated = { [weak player] in player?.contextInvalidated() }
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "reader-A")
        let original = try XCTUnwrap(player.beginSession(episodeID: "episode", articleID: "article"))
        XCTAssertTrue(player.save(original.ticket, seconds: 42, duration: 600))
        let baseline = writes
        _ = try await recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 1))

        let saved = player.save(original.ticket, seconds: 90, duration: 600)
        let completed = player.complete(original.ticket)
        XCTAssertEqual(writes - baseline, 0, "Neither a late progress save nor completion may enter storage after recovery seal")
        XCTAssertFalse(saved)
        XCTAssertFalse(completed)
        XCTAssertFalse(player.isCurrent(original.ticket))
    }

    func testColdClosedRuntimeDoesNoIOAndMissingMarkerAllowsExplicitGuest() async throws {
        let f = Fixture(); defer { f.cleanup() }
        _ = f.player
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        f.runtime.model.changeContext(to: .guest); f.runtime.model.retryStorage()
        XCTAssertFalse(f.runtime.model.hasPlaybackAccess)
        XCTAssertNil(f.player.beginSession(episodeID: "episode", articleID: nil))
        XCTAssertEqual(f.memory.factories, 0)
        XCTAssertEqual(f.memory.reads, 0)
        XCTAssertTrue(f.effects.isEmpty)
        try await f.prepare(nil)
        let guest = try f.begin()
        XCTAssertTrue(f.player.save(guest, seconds: 42, duration: 600))
        XCTAssertEqual(f.memory.factories, 1)
        XCTAssertEqual(try f.decoded(nil).entries.first?.positionSeconds, 42)
    }

    func testColdSealedRecoveryCannotOpenAnotherOwnerOrGuestAndDisabledHostIsInert() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap(); try await f.seal()
        let recovery = ReaderTransitionRecovery(store: .init(rootDirectory: f.directory))
        try await recovery.bootstrap()
        let memory = Memory(), cold = memory.runtime(recovery)
        cold.prepareIfNeeded(); cold.changeAccountContext(userID: "reader-B"); cold.changeAccountContext(userID: nil)
        XCTAssertFalse(cold.model.hasPlaybackAccess)
        XCTAssertNil(cold.model.beginSession(episodeID: "episode", articleID: nil))
        XCTAssertEqual(memory.factories, 0)
        XCTAssertEqual(memory.reads, 0)
        let disabled = f.memory.runtime(nil, disabled: true)
        disabled.prepareIfNeeded(); disabled.changeAccountContext(userID: "reader-A")
        XCTAssertEqual(f.memory.factories, 0)
    }

    func testPureAdmissionRejectsDirectStoreAndPlayerCallsBeforeObserverDelivery() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let directRuntime = f.memory.runtime(f.recovery)
        directRuntime.prepareIfNeeded(); directRuntime.changeAccountContext(userID: "reader-A")
        let direct = try XCTUnwrap(directRuntime.model.beginSession(episodeID: "direct", articleID: nil))
        XCTAssertEqual(directRuntime.model.save(direct.ticket, seconds: 42, duration: 600), .written)
        let original = try f.begin()
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        let baseline = f.memory.writes
        XCTAssertTrue(directRuntime.model.isCurrent(direct.ticket))
        f.closeAtHook(notify: false)
        XCTAssertFalse(f.runtime.model.hasPlaybackAccess)
        XCTAssertFalse(f.player.isCurrent(original))
        XCTAssertFalse(f.player.save(original, seconds: 90, duration: 600))
        XCTAssertFalse(f.player.complete(original))
        XCTAssertFalse(directRuntime.model.isCurrent(direct.ticket))
        XCTAssertEqual(directRuntime.model.save(direct.ticket, seconds: 90, duration: 600), .stale)
        XCTAssertEqual(directRuntime.model.complete(direct.ticket), .stale)
        XCTAssertNil(f.runtime.model.beginSession(episodeID: "replacement", articleID: nil))
        f.runtime.model.retryStorage()
        XCTAssertEqual(f.memory.writes, baseline)
    }

    func testRecoveryRetiresOwnershipBeforeEveryActualPlayerTeardownEffect() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        f.onInvalidation = { [unowned f] in
            XCTAssertFalse(f.runtime.model.hasPlaybackAccess)
            XCTAssertFalse(f.player.isCurrent(original))
            XCTAssertNil(f.runtime.model.snapshot.position(for: "episode"))
            f.runtime.changeAccountContext(userID: "reader-B")
            f.runtime.changeAccountContext(userID: "reader-A")
            XCTAssertEqual(f.runtime.model.context, .unresolved)
        }
        f.onEffect = { [unowned f] in
            XCTAssertFalse(f.player.save(original, seconds: 90, duration: 600))
            XCTAssertFalse(f.player.complete(original))
            XCTAssertNil(f.player.beginSession(episodeID: "replacement", articleID: nil))
        }
        try await f.seal()
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "nowPlaying", "deactivate"])
        XCTAssertEqual(f.memory.writes, 1)
        XCTAssertEqual(try f.decoded("reader-A").entries.first?.positionSeconds, 42)
    }

    func testClosureInsideFactoryRejectsReturnedStorageAndAnyCanonicalAdoption() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap(); _ = f.player
        f.memory.onFactory = { [unowned f] in
            f.closeAtHook()
            f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        }
        f.runtime.prepareIfNeeded()
        XCTAssertEqual(f.memory.factories, 1)
        XCTAssertEqual(f.memory.reads, 0)
        XCTAssertFalse(f.runtime.model.hasPlaybackAccess)
        XCTAssertEqual(f.invalidations, 1)
    }

    func testClosureDuringOriginalReadPreventsLoadedSnapshotAndNewSession() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap(); _ = f.player
        f.memory.onRead = { [unowned f] in f.closeAtHook() }
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        XCTAssertEqual(f.memory.reads, 1)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        XCTAssertNil(f.runtime.model.snapshot.lastPlayedEpisodeID)
        XCTAssertFalse(f.runtime.model.hasPlaybackAccess)
        XCTAssertNil(f.player.beginSession(episodeID: "episode", articleID: nil))
        XCTAssertTrue(f.effects.isEmpty)
    }

    func testAlreadyEnteredWritePreservesOriginalBytesButCannotAcknowledgeOrComplete() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        f.memory.onWrite = { [unowned f] in f.closeAtHook() }
        XCTAssertFalse(f.player.save(original, seconds: 90, duration: 600))
        XCTAssertEqual(f.memory.writes, 2)
        XCTAssertEqual(try f.decoded("reader-A").entries.first?.positionSeconds, 90)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        XCTAssertNil(f.runtime.model.snapshot.position(for: "episode"))
        XCTAssertFalse(f.player.complete(original))
        XCTAssertEqual(f.memory.writes, 2)
    }

    func testFailedEnteredWriteAfterClosureCannotPublishOldFailure() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        f.memory.onWrite = { [unowned f] in f.closeAtHook() }
        f.memory.failsWrite = true
        XCTAssertFalse(f.player.save(original, seconds: 90, duration: 600))
        XCTAssertEqual(try f.decoded("reader-A").entries.first?.positionSeconds, 42)
        XCTAssertNil(f.runtime.model.snapshot.issueMessage)
        XCTAssertFalse(f.runtime.model.snapshot.canRetry)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
    }

    func testClosureDuringSavePublicationKeepsPhysicalBytesWithoutOldACK() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        let observation = f.runtime.model.objectWillChange.sink { [unowned f] in f.closeAtHook() }
        XCTAssertFalse(f.player.save(original, seconds: 42, duration: 600))
        XCTAssertEqual(try f.decoded("reader-A").entries.first?.positionSeconds, 42)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        XCTAssertNil(f.player.currentTicket)
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "nowPlaying", "deactivate"])
        withExtendedLifetime(observation) {}
    }

    func testClosingPublicationCannotReplaceOriginalPlayerInvalidationHook() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        var replacementCalls = 0
        let observation = f.runtime.model.objectWillChange.sink { [unowned f] in
            f.runtime.model.onContextInvalidated = { replacementCalls += 1 }
            f.runtime.model.changeContext(to: .guest)
            XCTAssertFalse(f.player.isCurrent(original))
        }
        let baseline = f.invalidations
        try await f.seal()
        XCTAssertEqual(f.invalidations, baseline + 1)
        XCTAssertEqual(replacementCalls, 0)
        XCTAssertNil(f.player.currentTicket)
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "nowPlaying", "deactivate"])
        withExtendedLifetime(observation) {}
    }

    func testLaterMissingRecoveryReadCannotReviveOriginalPlaybackOrRuntime() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        try await f.recovery.bootstrap() // Admission closes during the physical read.
        XCTAssertTrue(f.recovery.admission.isAllowed)
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        f.runtime.changeAccountContext(userID: "reader-B"); f.runtime.changeAccountContext(userID: nil)
        f.runtime.model.changeContext(to: .confirmed(userID: "reader-A"))
        XCTAssertFalse(f.runtime.model.hasPlaybackAccess)
        XCTAssertFalse(f.player.save(original, seconds: 90, duration: 600))
        XCTAssertNil(f.player.beginSession(episodeID: "episode", articleID: nil))
        XCTAssertEqual(f.memory.writes, 1)
    }

    func testAccountRoundTripAndSealPreserveOtherOwnerAndGuestProgress() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let a = try f.begin()
        XCTAssertTrue(f.player.save(a, seconds: 42, duration: 600))
        f.runtime.changeAccountContext(userID: "reader-B")
        let b = try f.begin()
        XCTAssertTrue(f.player.save(b, seconds: 84, duration: 600))
        f.runtime.changeAccountContext(userID: nil)
        let guest = try f.begin()
        XCTAssertTrue(f.player.save(guest, seconds: 126, duration: 600))
        f.runtime.changeAccountContext(userID: "reader-A")
        let fresh = try XCTUnwrap(f.player.beginSession(episodeID: "episode", articleID: "article"))
        XCTAssertEqual(fresh.resumePosition, 42)
        XCTAssertFalse(f.player.save(a, seconds: 90, duration: 600))
        try await f.seal()
        XCTAssertFalse(f.player.complete(b)); XCTAssertFalse(f.player.complete(guest))
        XCTAssertEqual(try f.decoded("reader-A").entries.first?.positionSeconds, 42)
        XCTAssertEqual(try f.decoded("reader-B").entries.first?.positionSeconds, 84)
        XCTAssertEqual(try f.decoded(nil).entries.first?.positionSeconds, 126)
        XCTAssertEqual(f.memory.writes, 3)
    }

    func testRecoveryClosurePreventsFailedStorageRetryWithoutErasingStoredValue() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        f.memory.failsWrite = true
        _ = f.player.save(original, seconds: 90, duration: 600)
        XCTAssertTrue(f.runtime.model.snapshot.canRetry)
        try await f.seal()
        f.memory.failsWrite = false
        f.runtime.model.retryStorage()
        XCTAssertEqual(f.memory.writes, 2)
        XCTAssertEqual(try f.decoded("reader-A").entries.first?.positionSeconds, 42)
        XCTAssertFalse(f.runtime.model.snapshot.canRetry)
    }

    func testNormalSynchronousWriteRetainsPlaybackOwnershipAndCompletionSemantics() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let original = try f.begin()
        f.memory.onWrite = { [unowned f] in
            XCTAssertTrue(f.runtime.model.hasPlaybackAccess)
            XCTAssertTrue(f.player.isCurrent(original), "Storage admission must not itself revoke accepted playback")
        }
        XCTAssertTrue(f.player.save(original, seconds: 42, duration: 600))
        XCTAssertTrue(f.player.complete(original))
        XCTAssertTrue(f.player.isCurrent(original))
        XCTAssertNil(f.runtime.model.snapshot.position(for: "episode"))
        XCTAssertEqual(f.memory.writes, 2)
    }
}
