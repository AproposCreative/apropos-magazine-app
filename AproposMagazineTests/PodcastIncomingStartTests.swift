import XCTest
@testable import Apropos

@MainActor
final class PodcastIncomingStartTests: XCTestCase {
    func testExplicitZeroOverridesSavedResumeAndWaitsForObservedPosition() throws {
        let f = Fixture(); let owner = try f.begin()
        var state = PodcastResumeSeekState()
        state.prepareEpisode(savedPosition: 180, explicitStart: 0)
        XCTAssertEqual(state.pendingPosition, 0); XCTAssertTrue(state.hasExplicitStart)
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        XCTAssertFalse(f.coordinator.save(owner, seconds: 180, duration: 600))
        XCTAssertFalse(f.coordinator.complete(owner)); XCTAssertTrue(f.writes.isEmpty)
        let request = state.begin()
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true, observedPosition: 0), .positioned(0))
        XCTAssertTrue(f.coordinator.finishPositioning(start, observedPosition: 0))
        XCTAssertTrue(state.canPersistProgress); XCTAssertTrue(f.coordinator.canPublishProgress(owner))
    }
    func testExplicitTimestampClampsOnlyAfterFiniteDurationIsAvailable() {
        for invalid: TimeInterval? in [nil, 0, -1, .nan, .infinity, 604_801] {
            XCTAssertNil(PodcastPlaybackPolicy.boundedExplicitStart(120, duration: invalid))
        }
        XCTAssertEqual(PodcastPlaybackPolicy.boundedExplicitStart(120, duration: 90), 90)
        XCTAssertEqual(PodcastPlaybackPolicy.boundedExplicitStart(0, duration: 90), 0)
        XCTAssertEqual(PodcastPlaybackPolicy.boundedExplicitStart(1.25, duration: 90), 1.25)
        for invalid in [TimeInterval.nan, .infinity, -1, 604_801] { XCTAssertNil(PodcastPlaybackPolicy.explicitStart(invalid)) }
    }
    func testNilExplicitTimestampRetainsSavedResumeAndNoPositionMeansNoSeek() {
        var state = PodcastResumeSeekState()
        state.prepareEpisode(savedPosition: 42, explicitStart: nil)
        XCTAssertEqual(state.pendingPosition, 42); XCTAssertFalse(state.hasExplicitStart)
        state.prepareEpisode(savedPosition: nil); XCTAssertNil(state.pendingPosition); XCTAssertTrue(state.canPersistProgress)
    }
    func testSuccessfulCallbackUsesObservedPositionRatherThanRequestedTarget() throws {
        let f = Fixture(), owner = try f.begin()
        var state = PodcastResumeSeekState(); state.prepareEpisode(savedPosition: nil, explicitStart: 120)
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true })), request = state.begin()
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true, observedPosition: 119.25), .positioned(119.25))
        XCTAssertTrue(f.coordinator.finishPositioning(start, observedPosition: 119.25))
        XCTAssertTrue(f.coordinator.save(owner, seconds: 119.25, duration: 600))
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 119.25)
    }
    func testSuccessfulFlagWithoutValidObservationKeepsBarrierAndOriginalCheckpoint() throws {
        let f = Fixture(), old = try f.begin()
        XCTAssertTrue(f.coordinator.save(old, seconds: 42, duration: 600))
        let owner = try f.begin(), start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        var state = PodcastResumeSeekState(); state.prepareEpisode(savedPosition: nil, explicitStart: 120)
        let count = f.writes.count
        for invalid: TimeInterval? in [nil, .nan, .infinity, -1, 604_801] {
            let request = state.begin()
            XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true, observedPosition: invalid), .retryRequired)
            XCTAssertFalse(state.canPersistProgress); XCTAssertFalse(f.coordinator.save(owner, seconds: 120, duration: 600))
        }
        XCTAssertTrue(f.coordinator.isCurrent(start)); XCTAssertEqual(f.writes.count, count)
        XCTAssertEqual(f.store.snapshot.position(for: "episode"), 42)
    }
    func testFailedSeekRetainsTargetUntilExplicitRetryAndNeverEndorsesRequestedTime() throws {
        let f = Fixture(), owner = try f.begin()
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        var state = PodcastResumeSeekState(); state.prepareEpisode(savedPosition: nil, explicitStart: 120)
        let failed = state.begin()
        XCTAssertEqual(state.finishResume(failed, itemMatches: true, seekFinished: false, observedPosition: 120), .retryRequired)
        XCTAssertEqual(state.pendingPosition, 120); XCTAssertFalse(f.coordinator.complete(owner))
        XCTAssertNil(state.positionToResume(wantsPlayback: false, itemReady: true))
        let retry = state.begin()
        XCTAssertEqual(state.finishResume(retry, itemMatches: true, seekFinished: true, observedPosition: 120), .positioned(120))
        XCTAssertTrue(f.coordinator.finishPositioning(start, observedPosition: 120))
    }
    func testManualPauseInvalidatesPhysicalCompletionAndKeepsProgressBlocked() throws {
        let f = Fixture(), owner = try f.begin()
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        var state = PodcastResumeSeekState(); state.prepareEpisode(savedPosition: nil, explicitStart: 120)
        let request = state.begin(); f.coordinator.recordExplicitAction(); state.invalidate()
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true, observedPosition: 120), .ignored)
        XCTAssertFalse(f.coordinator.canPublishProgress(owner)); XCTAssertTrue(f.coordinator.isCurrent(start))
        XCTAssertNil(state.positionToResume(wantsPlayback: false, itemReady: true)); XCTAssertTrue(f.writes.isEmpty)
    }
    func testNewerSameEpisodeTimestampInvalidatesEveryOldSeekAndSaveTicket() throws {
        let f = Fixture(), old = try f.begin()
        let oldStart = try XCTUnwrap(f.coordinator.beginPositioning(old, routeIsCurrent: { true }))
        var state = PodcastResumeSeekState(); state.prepareEpisode(savedPosition: nil, explicitStart: 120); let oldRequest = state.begin()
        let new = try f.begin(), newStart = try XCTUnwrap(f.coordinator.beginPositioning(new, routeIsCurrent: { true }))
        state.prepareEpisode(savedPosition: nil, explicitStart: 0)
        XCTAssertEqual(state.finishResume(oldRequest, itemMatches: true, seekFinished: true, observedPosition: 120), .ignored)
        XCTAssertFalse(f.coordinator.finishPositioning(oldStart, observedPosition: 120)); XCTAssertFalse(f.coordinator.save(old, seconds: 120, duration: 600))
        XCTAssertTrue(f.coordinator.isCurrent(newStart)); XCTAssertEqual(state.pendingPosition, 0)
    }
    func testNewRouteSynchronouslyCancelsOnlyPendingRoutePositioningWithoutSaving() throws {
        let f = Fixture(), owner = try f.begin()
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        f.coordinator.cancelIncomingPositioning()
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "now-playing", "audio"])
        XCTAssertFalse(f.coordinator.finishPositioning(start, observedPosition: 120)); XCTAssertTrue(f.writes.isEmpty)
        XCTAssertNil(f.coordinator.currentTicket)
    }
    func testNewRouteDoesNotCloseAlreadyPositionedPlaybackOrOrdinarySavedResume() throws {
        let f = Fixture(), owner = try f.begin()
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        XCTAssertTrue(f.coordinator.finishPositioning(start, observedPosition: 120)); f.coordinator.cancelIncomingPositioning()
        XCTAssertTrue(f.coordinator.isCurrent(owner)); XCTAssertTrue(f.effects.isEmpty)
        _ = try XCTUnwrap(f.coordinator.beginPositioning(owner)); f.coordinator.cancelIncomingPositioning()
        XCTAssertTrue(f.coordinator.isCurrent(owner)); XCTAssertTrue(f.effects.isEmpty)
    }
    func testRevokedRouteValidatorRejectsCompletionEvenBeforeCancellationHookRuns() throws {
        let f = Fixture(), owner = try f.begin(); var current = true
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { current }))
        current = false
        XCTAssertFalse(f.coordinator.finishPositioning(start, observedPosition: 120)); XCTAssertFalse(f.coordinator.save(owner, seconds: 120, duration: 600))
        XCTAssertTrue(f.writes.isEmpty)
    }
    func testActualStoreContextHookRevokesPendingSeekAcrossAtoGuestToA() throws {
        let f = Fixture(); f.store.changeContext(to: .confirmed(userID: "A")); let owner = try f.begin()
        let start = try XCTUnwrap(f.coordinator.beginPositioning(owner, routeIsCurrent: { true }))
        f.store.changeContext(to: .guest); f.store.changeContext(to: .confirmed(userID: "A")); let replacement = try f.begin()
        XCTAssertFalse(f.coordinator.finishPositioning(start, observedPosition: 120)); XCTAssertFalse(f.coordinator.save(owner, seconds: 120, duration: 600))
        XCTAssertTrue(f.coordinator.isCurrent(replacement)); XCTAssertTrue(f.writes.isEmpty)
    }
    func testReentrantValidatorCannotOverwriteNewerPositioningOrContext() throws {
        let f = Fixture(), owner = try f.begin()
        var nested: PodcastPlaybackSessionCoordinator.StartTicket?
        let old = f.coordinator.beginPositioning(owner, routeIsCurrent: {
            nested = f.coordinator.beginPositioning(owner)
            return true
        })
        XCTAssertNil(old); XCTAssertTrue(f.coordinator.isCurrent(try XCTUnwrap(nested)))
        XCTAssertNil(f.coordinator.beginPositioning(owner, routeIsCurrent: { f.store.changeContext(to: .confirmed(userID: "B")); return true }))
        XCTAssertNil(f.coordinator.currentTicket)
    }
    func testSavedResumeFallbackStillRequiresObservedSuccessfulZeroSeek() {
        var state = PodcastResumeSeekState(); state.prepareEpisode(savedPosition: 300)
        let safe = PodcastPlaybackSessionCoordinator.safeResumePosition(300, currentDuration: 100)
        XCTAssertEqual(safe, 0); state.setResolvedPosition(safe)
        let request = state.begin()
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true, observedPosition: nil), .retryRequired)
        XCTAssertEqual(state.pendingPosition, 0); XCTAssertFalse(state.canPersistProgress)
    }
    func testSameItemReuseRequiresExactCanonicalMediaIdentityAndSourceRevision() {
        func episode(url: String = "a", revision: String? = "r1", narration: Bool = true) -> PodcastEpisode {
            var value = PodcastEpisode(id: "episode", articleId: "article", articleSlug: nil, title: "Titel", subtitle: nil,
                audioURL: URL(string: "https://audio.example.com/\(url).m4a"), productionSourceURL: nil, duration: nil,
                artworkURL: nil, hosts: [], publishedDate: nil)
            value.isAINarration = narration; value.sourceContentRevision = revision; return value
        }
        let current = episode()
        func reuse(_ requested: PodcastEpisode, id: String? = "article") -> Bool {
            PodcastPlaybackPolicy.canReuseItem(current: current, requested: requested, currentArticleID: "article", requestedArticleID: id, currentAudioURL: current.audioURL, itemHasFailed: false)
        }
        XCTAssertTrue(reuse(episode()))
        XCTAssertFalse(reuse(episode(url: "corrected")))
        XCTAssertFalse(reuse(episode(revision: "r2")))
        XCTAssertFalse(reuse(episode(revision: nil)))
        XCTAssertFalse(reuse(episode(narration: false)))
        XCTAssertFalse(reuse(episode(), id: "different-article"))
        XCTAssertFalse(PodcastPlaybackPolicy.canReuseItem(current: nil, requested: current, currentArticleID: nil, requestedArticleID: "article", currentAudioURL: current.audioURL, itemHasFailed: false))
    }
    func testInvalidExplicitPositionCannotSilentlyAdoptSavedPosition() {
        var state = PodcastResumeSeekState()
        state.prepareEpisode(savedPosition: 120, explicitStart: .nan)
        XCTAssertNil(state.pendingPosition); XCTAssertFalse(state.hasExplicitStart)
    }
    func testRejectedNoPositionAdoptionAbortsActualCurrentSessionWithoutSave() throws {
        let f = Fixture(), adopted = try f.begin()
        XCTAssertTrue(f.coordinator.canPublishProgress(adopted), "This adoption has no positioning ticket")
        XCTAssertTrue(f.coordinator.abort(adopted))
        XCTAssertNil(f.coordinator.currentTicket)
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "now-playing", "audio"])
        XCTAssertTrue(f.writes.isEmpty)
    }
    func testOldAdoptionAbortCannotCloseOrClearNewReplacement() throws {
        let f = Fixture(), rejected = try f.begin(), replacement = try f.begin()
        XCTAssertFalse(f.coordinator.abort(rejected)); XCTAssertTrue(f.effects.isEmpty)
        XCTAssertTrue(f.coordinator.isCurrent(replacement))
        XCTAssertTrue(f.coordinator.save(replacement, seconds: 42, duration: 600))
    }
    func testAbortRevokesBeforeInjectedCleanupAndDeniesReentrantAdoption() throws {
        let f = Fixture(), rejected = try f.begin()
        var attempted = false
        f.onCancel = {
            attempted = true
            XCTAssertFalse(f.coordinator.isCurrent(rejected))
            XCTAssertFalse(f.coordinator.save(rejected, seconds: 120, duration: 600))
            XCTAssertNil(f.coordinator.beginSession(episodeID: "reentrant", articleID: "article"))
            f.store.changeContext(to: .confirmed(userID: "B"))
            XCTAssertNil(f.coordinator.beginSession(episodeID: "reentrant-B", articleID: "article"))
        }
        XCTAssertTrue(f.coordinator.abort(rejected)); XCTAssertTrue(attempted)
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "now-playing", "audio"])
        XCTAssertTrue(f.writes.isEmpty); f.onCancel = nil
        let replacement = try f.begin()
        XCTAssertFalse(f.coordinator.abort(rejected)); XCTAssertTrue(f.coordinator.isCurrent(replacement))
    }
    func testRejectedRenewalAfterCompletionKeepsTombstoneAndCannotSaveOldTarget() throws {
        let f = Fixture(), completed = try f.begin()
        XCTAssertTrue(f.coordinator.complete(completed))
        let writes = f.writes.count
        let renewal = try f.begin()
        XCTAssertTrue(f.coordinator.abort(renewal)); XCTAssertEqual(f.writes.count, writes)
        XCTAssertFalse(f.coordinator.save(completed, seconds: 120, duration: 600))
        XCTAssertFalse(f.coordinator.save(renewal, seconds: 120, duration: 600))
        XCTAssertNil(f.store.snapshot.position(for: "episode"))
    }
    private func preparationAsset(_ revision: String = "a") throws -> PodcastAudioAsset {
        try XCTUnwrap(PodcastAudioAsset(episodeID: "episode", canonicalArticleID: "article", kind: .human,
            sourceRevision: "cms-sha256-v1:" + String(repeating: revision, count: 64), remoteURL: URL(string: "https://audio.example.com/same.m4a")!))
    }
    func testColdPreparationRetainsOriginalAssetAndDoesNotAdoptOrWriteBeforeConsumption() throws {
        let f = Fixture(), old = try f.begin(), asset = try preparationAsset()
        let request = try XCTUnwrap(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
        XCTAssertEqual(request.asset, asset); XCTAssertTrue(f.coordinator.isCurrent(old))
        XCTAssertTrue(f.effects.isEmpty); XCTAssertTrue(f.writes.isEmpty)
        XCTAssertTrue(f.coordinator.consumePreparation(request)); XCTAssertFalse(f.coordinator.consumePreparation(request))
        let next = try f.begin(); XCTAssertFalse(f.coordinator.isCurrent(old)); XCTAssertTrue(f.coordinator.isCurrent(next))
    }
    func testExplicitTransportActionRevokesHeldColdPreparationWithoutRestartingOldAudio() throws {
        let f = Fixture(), owner = try f.begin()
        let request = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset(), accessIsCurrent: { true }))
        f.coordinator.recordExplicitAction()
        XCTAssertFalse(f.coordinator.consumePreparation(request)); XCTAssertTrue(f.coordinator.isCurrent(owner))
        XCTAssertTrue(f.effects.isEmpty); XCTAssertTrue(f.writes.isEmpty)
    }
    func testNewPreparationSupersedesOldResultEvenForSameURLAndDifferentRevision() throws {
        let f = Fixture(); _ = try f.begin()
        let old = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset(), accessIsCurrent: { true }))
        let new = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset("b"), accessIsCurrent: { true }))
        XCTAssertFalse(f.coordinator.consumePreparation(old)); XCTAssertTrue(f.coordinator.isCurrent(new))
        XCTAssertNotEqual(old.asset, new.asset)
    }
    func testOriginalAccessEpochCannotReviveAfterRemoveAndReadd() throws {
        let f = Fixture(); _ = try f.begin(); var accessEpoch = UUID(); let original = accessEpoch
        let request = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset(), accessIsCurrent: { accessEpoch == original }))
        accessEpoch = UUID()
        XCTAssertFalse(f.coordinator.consumePreparation(request)); XCTAssertTrue(f.coordinator.discardPreparation(request))
        XCTAssertFalse(f.coordinator.consumePreparation(request)); XCTAssertTrue(f.writes.isEmpty)
    }
    func testAccountRoundTripRevokesColdPreparationBeforeAnyNewOwnerAdoption() throws {
        let f = Fixture(); f.store.changeContext(to: .confirmed(userID: "A")); _ = try f.begin()
        let request = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset(), accessIsCurrent: { true }))
        f.store.changeContext(to: .guest); f.store.changeContext(to: .confirmed(userID: "A")); let restored = try f.begin()
        XCTAssertFalse(f.coordinator.consumePreparation(request)); XCTAssertTrue(f.coordinator.isCurrent(restored)); XCTAssertTrue(f.writes.isEmpty)
    }
    func testNewIncomingRouteCancelsOnlyHeldRoutePreparationAndPreservesPlayingOwner() throws {
        let f = Fixture(), owner = try f.begin(); var routeIsCurrent = true
        let request = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset(), routeIsCurrent: { routeIsCurrent }, accessIsCurrent: { true }))
        routeIsCurrent = false
        XCTAssertFalse(f.coordinator.isCurrent(request)); XCTAssertTrue(f.coordinator.cancelIncomingPositioning())
        XCTAssertFalse(f.coordinator.consumePreparation(request)); XCTAssertTrue(f.coordinator.isCurrent(owner)); XCTAssertTrue(f.effects.isEmpty)
    }
    func testIncomingCancellationDoesNotCancelOrdinaryUserPreparationAndOldDiscardCannotClearReplacement() throws {
        let f = Fixture(); _ = try f.begin()
        let old = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset(), accessIsCurrent: { true }))
        XCTAssertFalse(f.coordinator.cancelIncomingPositioning()); XCTAssertTrue(f.coordinator.isCurrent(old))
        let new = try XCTUnwrap(f.coordinator.beginPreparation(asset: preparationAsset("b"), accessIsCurrent: { true }))
        XCTAssertFalse(f.coordinator.discardPreparation(old)); XCTAssertTrue(f.coordinator.isCurrent(new))
    }
    func testReentrantPreparationAccessValidationCannotOverwriteNewerRequest() throws {
        let f = Fixture(); _ = try f.begin(); let asset = try preparationAsset()
        var nested: PodcastPlaybackSessionCoordinator.PreparationTicket?
        let old = f.coordinator.beginPreparation(asset: asset, accessIsCurrent: {
            nested = f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }); return true
        })
        XCTAssertNil(old); XCTAssertTrue(f.coordinator.isCurrent(try XCTUnwrap(nested)))
    }
    func testClosePresentationEffectCannotCreateColdPreparationThatSurvivesTeardown() throws {
        let f = Fixture(); _ = try f.begin(); let asset = try preparationAsset()
        var attempted = false
        f.onPresentation = {
            attempted = true
            XCTAssertNil(f.coordinator.currentTicket)
            XCTAssertNil(f.coordinator.beginPreparation(asset: asset, routeIsCurrent: { true }, accessIsCurrent: { true }))
        }
        f.coordinator.close()
        XCTAssertTrue(attempted); XCTAssertNil(f.coordinator.currentTicket); XCTAssertTrue(f.writes.isEmpty)
        f.onPresentation = nil
        XCTAssertNotNil(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
    }
    func testConsumedPreparationResultRejectsNewSameOwnerRequestBeforeOldErrorOrPause() throws {
        let f = Fixture(), owner = try f.begin(), asset = try preparationAsset()
        let old = try XCTUnwrap(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
        XCTAssertTrue(f.coordinator.consumePreparation(old)); XCTAssertTrue(f.coordinator.isCurrentPreparationResult(old))
        let newer = try XCTUnwrap(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
        XCTAssertTrue(f.coordinator.isCurrent(owner), "A newer request may keep the same playing owner")
        XCTAssertFalse(f.coordinator.isCurrentPreparationResult(old))
        XCTAssertTrue(f.coordinator.isCurrent(newer)); XCTAssertTrue(f.effects.isEmpty)
    }
    func testConsumedResultRechecksValidatorAfterReentrantPublicationStartsNewRequest() throws {
        let f = Fixture(); _ = try f.begin(); let asset = try preparationAsset()
        var reenter = false
        var newer: PodcastPlaybackSessionCoordinator.PreparationTicket?
        let old = try XCTUnwrap(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: {
            if reenter { reenter = false; newer = f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }) }
            return true
        }))
        XCTAssertTrue(f.coordinator.consumePreparation(old)); reenter = true
        XCTAssertFalse(f.coordinator.isCurrentPreparationResult(old))
        XCTAssertTrue(f.coordinator.isCurrent(try XCTUnwrap(newer)))
    }
    func testConsumedPreparationFailureFenceEndsOnPauseAndContextChange() throws {
        let f = Fixture(); _ = try f.begin(); let asset = try preparationAsset()
        let first = try XCTUnwrap(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
        XCTAssertTrue(f.coordinator.consumePreparation(first)); f.coordinator.recordExplicitAction()
        XCTAssertFalse(f.coordinator.isCurrentPreparationResult(first))
        let second = try XCTUnwrap(f.coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
        XCTAssertTrue(f.coordinator.consumePreparation(second)); f.store.changeContext(to: .confirmed(userID: "B"))
        XCTAssertFalse(f.coordinator.isCurrentPreparationResult(second))
    }
    @MainActor private final class Fixture {
        var records: [PodcastProgressNamespace: Data] = [:]
        var writes: [Data] = []
        var effects: [String] = []
        var onCancel: (() -> Void)?
        var onPresentation: (() -> Void)?
        lazy var store = PodcastPlaybackProgressStore(storage: .init(read: { self.records[$0] }, write: { self.records[$0] = $1; self.writes.append($1) }))
        lazy var coordinator = PodcastPlaybackSessionCoordinator(store: store, effects: .init(cancelCallbacks: { self.effects.append("cancel"); self.onCancel?() }, stopPlayback: { self.effects.append("stop") }, clearPresentation: { self.effects.append("presentation"); self.onPresentation?() }, clearNowPlaying: { self.effects.append("now-playing") }, deactivateAudio: { self.effects.append("audio") }))
        init() { _ = coordinator; store.onContextInvalidated = { [weak self] in self?.coordinator.contextInvalidated() }; store.changeContext(to: .guest) }
        func begin() throws -> PodcastPlaybackSessionCoordinator.Ticket { try XCTUnwrap(coordinator.beginSession(episodeID: "episode", articleID: "article")).ticket }
    }
}
