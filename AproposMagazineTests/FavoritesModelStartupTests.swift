import Combine
import XCTest
@testable import Apropos

@MainActor
final class FavoritesModelStartupTests: XCTestCase {
    func testDeniedBeginDispatchPreservesQueuedIntentWithoutStartedWrite() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        try await h.manuallyReady()
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        let revision = h.record?.recordRevision
        let ticket = await h.model.beginDispatch(mutation, stillCurrent: { false })
        XCTAssertNil(ticket)
        XCTAssertEqual(h.record?.recordRevision, revision)
        XCTAssertEqual(h.record?.pending.first?.phase, .queued)
        XCTAssertTrue(h.model.isCurrent(mutation))
    }

    func testDenialWhileWaitingForInitialLocalCommitNeverCreatesStartedRecord() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        try await h.manuallyReady(); h.holdWrites = true
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        let task = Task { await h.model.beginDispatch(mutation, stillCurrent: { h.allowed }) }
        await favoriteStartupSettle()
        h.allowed = false; h.releaseWrite()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(h.heldWrites.isEmpty)
        XCTAssertEqual(h.record?.pending.first?.phase, .queued)
    }

    func testRecoveryBeginWillChangeRevocationRetiresOnlyOriginalRunningState() throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        h.owner("A")
        let ticket = try XCTUnwrap(h.model.recoveryTicket())
        let subscription = h.model.objectWillChange.sink { h.allowed = false }
        XCTAssertFalse(h.model.beginRecovery(ticket, stillCurrent: { h.allowed }))
        withExtendedLifetime(subscription) {}
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertEqual(h.model.snapshot.state, .recoveryFailed)
    }

    func testRecoveryFinalPublicationRevocationCannotLeaveReadyState() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        h.owner("A")
        let ticket = try XCTUnwrap(h.model.recoveryTicket())
        XCTAssertTrue(h.model.beginRecovery(ticket))
        let subscription = h.model.objectWillChange.sink { h.allowed = false }
        let success = await h.model.finishRecovery(ticket, success: true, stillCurrent: { h.allowed })
        withExtendedLifetime(subscription) {}
        XCTAssertFalse(success)
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertEqual(h.model.snapshot.state, .recoveryFailed)
    }

    func testRecoveryAfterRequeueDiskAwaitRechecksOriginalPermission() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        try await h.manuallyReady()
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        let dispatch = await h.model.beginDispatch(mutation)
        XCTAssertNotNil(dispatch)
        h.owner(nil); h.owner("A")
        let recovery = try XCTUnwrap(h.model.recoveryTicket())
        XCTAssertTrue(h.model.beginRecovery(recovery))
        h.holdWrites = true
        let task = Task { await h.model.finishRecovery(recovery, success: true, stillCurrent: { h.allowed }) }
        await favoriteStartupWait { h.heldWrites.count == 1 }
        XCTAssertEqual(h.heldWrites[0].record.pending.first?.intentID, mutation.id)
        h.allowed = false; h.releaseWrite()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertEqual(h.model.snapshot.state, .recoveryFailed)
        XCTAssertEqual(h.record?.pending.first?.intentID, mutation.id)
        XCTAssertEqual(h.record?.pending.first?.phase, .queued)
    }

    func testRevokedProviderResultPersistsOnlyLocalFailure() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        try await h.manuallyReady()
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        let possible = await h.model.beginDispatch(mutation)
        let ticket = try XCTUnwrap(possible)
        let success = await h.model.finishDispatch(ticket, result: .acknowledged, stillCurrent: { false })
        XCTAssertFalse(success)
        XCTAssertEqual(h.record?.pending.first?.phase, .failed)
        XCTAssertEqual(h.model.snapshot.pendingArticleIDs, ["article"])
    }

    func testRegisteredHistoricalACKCannotRetireAfterPermissionChangesDuringDiskWrite() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        try await h.manuallyReady()
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        let possible = await h.model.beginDispatch(mutation)
        let ticket = try XCTUnwrap(possible)
        let observation = try XCTUnwrap(h.model.observationTicket())
        XCTAssertTrue(h.model.applyRemote(.init(articles: [favoriteStartupArticle()], isFromCache: false,
            hasPendingWrites: false), ticket: observation))
        h.holdWrites = true
        let task = Task { await h.model.finishDispatch(ticket, result: .acknowledged, stillCurrent: { h.allowed }) }
        await favoriteStartupWait { h.heldWrites.count == 1 }
        XCTAssertEqual(h.heldWrites[0].record.pending.first?.phase, .acknowledged)
        h.allowed = false; h.releaseWrite()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(h.heldWrites.isEmpty)
        XCTAssertEqual(h.record?.pending.first?.phase, .acknowledged)
        XCTAssertEqual(h.model.snapshot.pendingArticleIDs, ["article"])
    }

    func testRecoveryPermissionHookReplacingOwnerCannotFailNewOwner() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        h.owner("A")
        let original = try XCTUnwrap(h.model.recoveryTicket())
        XCTAssertTrue(h.model.beginRecovery(original))
        var changed = false
        let success = await h.model.finishRecovery(original, success: true, stillCurrent: {
            if !changed { changed = true; h.owner("B") }
            return true
        })
        XCTAssertFalse(success)
        XCTAssertEqual(h.model.context, .confirmed(userID: "B"))
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertNotEqual(h.model.snapshot.state, .recoveryFailed)
        XCTAssertTrue(h.model.recoveryIsRequired)
    }

    func testReceiptGuardReentryCannotAcknowledgeReplacementMutation() async throws {
        let h = FavoriteStartupHarness(connected: false); defer { h.stop() }
        try await h.manuallyReady()
        let old = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        let possible = await h.model.beginDispatch(old)
        let ticket = try XCTUnwrap(possible)
        var changed = false
        let success = await h.model.finishDispatch(ticket, result: .acknowledged, stillCurrent: {
            if !changed { changed = true; _ = h.model.setFavorite(favoriteStartupArticle(), enabled: false) }
            return true
        })
        XCTAssertFalse(success)
        XCTAssertEqual(h.record?.pending.first?.phase, .queued)
        XCTAssertEqual(h.record?.pending.first?.enabled, false)
        XCTAssertNotEqual(h.record?.pending.first?.intentID, old.id)
    }
}
