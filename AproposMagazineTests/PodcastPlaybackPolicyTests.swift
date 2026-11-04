import XCTest
@testable import Apropos

final class PodcastPlaybackPolicyTests: XCTestCase {
    func testQueueAdvancesThroughAllEpisodesAcrossSheetReappearance() throws {
        let episodes = ["A", "B", "C"].map { makeEpisode($0) }
        var queue = PodcastPlaybackQueue.prepared(existing: [], candidates: episodes, currentEpisode: episodes[0])
        var current = episodes[0]
        var trace = [current.id]

        while let next = PodcastPlaybackQueue.next(in: queue, after: current.id) {
            current = next
            trace.append(current.id)
            // Reopening the sheet, even after the repository order changes,
            // must not move the current episode to the start of the session.
            queue = PodcastPlaybackQueue.prepared(existing: queue, candidates: Array(episodes.reversed()), currentEpisode: current)
            XCTAssertLessThanOrEqual(trace.count, episodes.count)
            if trace.count > episodes.count { break }
        }

        XCTAssertEqual(trace, ["A", "B", "C"])
        XCTAssertNil(PodcastPlaybackQueue.next(in: queue, after: "C"))
    }

    func testStartingFromMiddleKeepsRepositoryOrder() {
        let episodes = ["A", "B", "C"].map { makeEpisode($0) }
        let queue = PodcastPlaybackQueue.prepared(existing: [], candidates: episodes, currentEpisode: episodes[1])
        XCTAssertEqual(queue.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(PodcastPlaybackQueue.next(in: queue, after: "B")?.id, "C")
    }

    func testNewEpisodeOutsideSessionCreatesPlayableUniqueQueue() {
        let old = makeEpisode("old")
        let selected = makeEpisode("selected")
        let next = makeEpisode("next")
        let queue = PodcastPlaybackQueue.prepared(
            existing: [old],
            candidates: [next, next, makeEpisode("unavailable", playable: false)],
            currentEpisode: selected
        )
        XCTAssertEqual(queue.map(\.id), ["selected", "next"])
    }

    func testOfflineSelectionRequiresLocalPlaybackURL() throws {
        let remote = try XCTUnwrap(URL(string: "https://fixtures.example.invalid/episode.m4a"))
        let local = URL(fileURLWithPath: "/fixture/episode.m4a")
        XCTAssertFalse(PodcastPlaybackPolicy.canStart(playbackURL: remote, isOnline: false))
        XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: local, isOnline: false))
        XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: remote, isOnline: true))
    }

    func testAutomaticAdvancePreservesPresentationAndUserSelectionOpensPlayer() {
        XCTAssertFalse(PodcastPlaybackPolicy.shouldPresentFullPlayer(reason: .automaticAdvance, isPresented: false))
        XCTAssertTrue(PodcastPlaybackPolicy.shouldPresentFullPlayer(reason: .automaticAdvance, isPresented: true))
        XCTAssertTrue(PodcastPlaybackPolicy.shouldPresentFullPlayer(reason: .userInitiated, isPresented: false))
    }

    func testResumeSeekCanCompleteOnlyOnce() {
        var state = PodcastResumeSeekState()
        let request = state.begin()
        XCTAssertTrue(state.consume(request, itemMatches: true))
        XCTAssertFalse(state.consume(request, itemMatches: true))
    }

    func testPauseSeekOrCloseInvalidatesOutstandingResume() {
        var state = PodcastResumeSeekState()
        let request = state.begin()
        state.invalidate()
        XCTAssertFalse(state.consume(request, itemMatches: true))
        XCTAssertNil(state.activeRequest)
    }

    func testOldItemCompletionCannotConsumeNewItemsResume() {
        var state = PodcastResumeSeekState()
        let oldRequest = state.begin()
        state.invalidate()
        let newRequest = state.begin()
        XCTAssertFalse(state.consume(oldRequest, itemMatches: false))
        XCTAssertEqual(state.activeRequest, newRequest)
        XCTAssertTrue(state.consume(newRequest, itemMatches: true))
    }

    func testResumeCompletionChecksCurrentItemAndCurrentPlaybackIntent() {
        var state = PodcastResumeSeekState()
        let request = state.begin()
        XCTAssertFalse(state.consume(request, itemMatches: false))
        XCTAssertTrue(state.consume(request, itemMatches: true))
        XCTAssertFalse(PodcastResumeSeekState.shouldResume(seekFinished: true, wantsPlayback: false))
        XCTAssertFalse(PodcastResumeSeekState.shouldResume(seekFinished: false, wantsPlayback: true))
        XCTAssertTrue(PodcastResumeSeekState.shouldResume(seekFinished: true, wantsPlayback: true))
    }

    func testFailedResumeKeepsDesiredPositionAndWaitsForExplicitRetry() {
        var state = PodcastResumeSeekState()
        state.prepareEpisode(savedPosition: 120)
        XCTAssertEqual(state.positionToResume(wantsPlayback: true, itemReady: true), 120)
        let failed = state.begin()
        XCTAssertNil(state.positionToResume(wantsPlayback: true, itemReady: true))
        XCTAssertFalse(state.canPersistProgress)
        XCTAssertEqual(state.finishResume(failed, itemMatches: true, seekFinished: false), .retryRequired)
        XCTAssertEqual(state.pendingPosition, 120)
        // The manager transitions wantsPlayback to false on retryRequired.
        XCTAssertNil(state.positionToResume(wantsPlayback: false, itemReady: true))
        XCTAssertFalse(state.canPersistProgress)
        state.prepareExplicitResume()
        XCTAssertEqual(state.positionToResume(wantsPlayback: true, itemReady: true), 120)
        let retry = state.begin()
        XCTAssertEqual(state.finishResume(retry, itemMatches: true, seekFinished: true, observedPosition: 120), .positioned(120))
        XCTAssertNil(state.pendingPosition)
        XCTAssertTrue(state.canPersistProgress)
    }

    func testPauseDuringResumeKeepsPositionAndInvalidatesOldCompletion() {
        var state = PodcastResumeSeekState()
        state.prepareEpisode(savedPosition: 120)
        let request = state.begin()
        state.invalidate()
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: false), .ignored)
        XCTAssertNil(state.positionToResume(wantsPlayback: false, itemReady: true))
        XCTAssertEqual(state.positionToResume(wantsPlayback: true, itemReady: true), 120)
        XCTAssertFalse(state.canPersistProgress)
    }

    func testConfirmedEndPreventsLateProgressAndInvalidatesOldSeek() {
        var state = PodcastResumeSeekState()
        state.prepareEpisode(savedPosition: 9)
        let request = state.begin()
        state.confirmCompletion()
        XCTAssertTrue(state.isCompleted)
        XCTAssertFalse(state.canPersistProgress)
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true), .ignored)
        state.invalidate() // Pause after the end must not re-enable persistence.
        XCTAssertFalse(state.canPersistProgress)
        XCTAssertNil(state.positionToResume(wantsPlayback: true, itemReady: true))
    }

    func testExplicitRestartAfterEndSeeksZeroBeforeAllowingProgress() {
        var state = PodcastResumeSeekState()
        state.confirmCompletion()
        let endedRevision = state.revision
        state.prepareExplicitResume()
        XCTAssertNotEqual(state.revision, endedRevision)
        XCTAssertFalse(state.isCompleted)
        XCTAssertFalse(state.canPersistProgress)
        XCTAssertEqual(state.positionToResume(wantsPlayback: true, itemReady: true), 0)
        let request = state.begin()
        XCTAssertEqual(state.finishResume(request, itemMatches: true, seekFinished: true, observedPosition: 0), .positioned(0))
        XCTAssertTrue(state.canPersistProgress)
    }

    func testManualSeekAndEpisodeReplacementLeaveCompletedState() {
        var state = PodcastResumeSeekState()
        state.confirmCompletion()
        let endedRevision = state.revision
        state.prepareManualSeek()
        XCTAssertNotEqual(state.revision, endedRevision)
        XCTAssertFalse(state.isCompleted)
        XCTAssertTrue(state.canPersistProgress)
        state.confirmCompletion()
        state.prepareEpisode(savedPosition: 42)
        XCTAssertFalse(state.isCompleted)
        XCTAssertEqual(state.pendingPosition, 42)
        XCTAssertFalse(state.canPersistProgress)
    }

    func testExplicitRetryMustReplaceFailedItemEvenWithSameEpisodeAndURL() {
        let episode = makeEpisode("retry")
        XCTAssertFalse(PodcastPlaybackPolicy.canReuseItem(current: episode, requested: episode,
            currentArticleID: "article", requestedArticleID: "article", currentAudioURL: episode.audioURL,
            itemHasFailed: true), "An AVPlayerItem in failed status cannot become playable by resuming it")
    }

    func testHealthyPauseResumeStillReusesIdenticalItem() {
        let episode = makeEpisode("retry")
        XCTAssertTrue(PodcastPlaybackPolicy.canReuseItem(current: episode, requested: episode,
            currentArticleID: "article", requestedArticleID: "article", currentAudioURL: episode.audioURL,
            itemHasFailed: false))
    }

    func testRetryMustNotReuseAnotherArticleOrChangedSource() {
        let episode = makeEpisode("retry")
        XCTAssertFalse(PodcastPlaybackPolicy.canReuseItem(current: episode, requested: episode,
            currentArticleID: "old-article", requestedArticleID: "new-article", currentAudioURL: episode.audioURL,
            itemHasFailed: false))
        XCTAssertFalse(PodcastPlaybackPolicy.canReuseItem(current: episode, requested: makeEpisode("new-source"),
            currentArticleID: "article", requestedArticleID: "article", currentAudioURL: episode.audioURL,
            itemHasFailed: true))
    }

    func testRetryFromMiniOrRemoteControlsKeepsExistingPresentation() {
        XCTAssertFalse(PodcastPlaybackPolicy.shouldPresentFullPlayer(reason: .resumeAfterFailure, isPresented: false))
        XCTAssertTrue(PodcastPlaybackPolicy.shouldPresentFullPlayer(reason: .resumeAfterFailure, isPresented: true))
    }

    private func makeEpisode(_ id: String, playable: Bool = true) -> PodcastEpisode {
        PodcastEpisode(
            id: id, articleId: nil, articleSlug: nil, title: id, subtitle: nil,
            audioURL: playable ? URL(string: "https://fixtures.example.invalid/\(id).m4a") : nil,
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil
        )
    }
}
