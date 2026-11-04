import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderPreferencesRefreshTests: XCTestCase {
    func testFreshServerInterestsReplacePreviouslyLoadedValuesWithoutRelogin() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }
        await h.loaded("A", ids: ["music", "film"])
        let before = h.model.snapshot
        let request = h.model.captureRefresh(context: h.model.contextTicket())!
        let task = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        XCTAssertEqual(h.model.snapshot, before, "Background refresh must not remove existing content or show loading")
        h.finishRead(1, ids: ["culture"]); await task.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["culture"], "A remote removal must not be silently unioned back")
        XCTAssertTrue(h.model.hasLoaded); XCTAssertNotEqual(h.model.acceptedLoadVersion, before.loadVersion)
        XCTAssertEqual(h.model.snapshot.generation, before.generation)
    }

    func testUnchangedServerValuesDoNotPublishOrChangeFormLoadVersion() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["film"])
        let before = h.model.snapshot
        var publications = 0
        let subscription = h.model.changes.sink { _ in publications += 1 }
        let task = Task { await h.model.refresh(h.model.captureRefresh(context: h.model.contextTicket())!) }
        await h.waitForReads(2); h.finishRead(1, ids: ["film"]); await task.value
        XCTAssertEqual(h.model.snapshot, before); XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }

    func testFailedAndCachedRefreshKeepAcceptedValuesAndVersion() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["accepted"])
        let before = h.model.snapshot
        let failed = Task { await h.model.refresh(h.model.captureRefresh(context: h.model.contextTicket())!) }
        await h.waitForReads(2); h.finishRead(1, error: URLError(.notConnectedToInternet)); await failed.value
        XCTAssertEqual(h.model.snapshot, before)
        let cached = Task { await h.model.refresh(h.model.captureRefresh(context: h.model.contextTicket())!) }
        await h.waitForReads(3); h.finishRead(2, ids: ["stale-cache"], fromCache: true); await cached.value
        XCTAssertEqual(h.model.snapshot, before)
    }

    func testInitialReadErrorSurvivesRefreshErrorAndCacheThenServerHealsIt() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        let initial = Task { await h.model.load(context) }; await h.waitForReads(1)
        h.finishRead(0, error: URLError(.notConnectedToInternet)); await initial.value
        let failedSnapshot = h.model.snapshot
        XCTAssertFalse(failedSnapshot.loaded); XCTAssertNotNil(failedSnapshot.errorMessage)
        for index in 1...2 {
            let task = Task { await h.model.refresh(h.model.captureRefresh(context: context)!) }
            await h.waitForReads(index + 1)
            if index == 1 { h.finishRead(index, error: URLError(.timedOut)) }
            else { h.finishRead(index, ids: ["cached"], fromCache: true) }
            await task.value
            XCTAssertEqual(h.model.snapshot, failedSnapshot)
        }
        let fresh = Task { await h.model.refresh(h.model.captureRefresh(context: context)!) }
        await h.waitForReads(4); h.finishRead(3, ids: ["online"]); await fresh.value
        XCTAssertTrue(h.model.hasLoaded); XCTAssertNil(h.model.errorMessage)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["online"])
    }

    func testServerAbsenceCanRecoverMissingInitialLoadWithoutCompletingOnboarding() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        let task = Task { await h.model.refresh(h.model.captureRefresh(context: context)!) }
        await h.waitForReads(1); h.finishRead(0, absence: true); await task.value
        XCTAssertTrue(h.model.hasLoaded); XCTAssertEqual(h.model.preferences, ReaderPreferences())
        XCTAssertNotNil(h.model.acceptedLoadVersion)
    }

    func testCachedInitialLoadCanRefreshFromServerWithoutAnotherLogin() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        let initial = Task { await h.model.load(context) }; await h.waitForReads(1)
        h.finishRead(0, ids: ["offline"], fromCache: true); await initial.value
        let task = Task { await h.model.refresh(h.model.captureRefresh(context: context)!) }
        await h.waitForReads(2); h.finishRead(1, ids: ["other-device"]); await task.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["other-device"])
    }

    func testRefreshIsSingleUseAndRepeatedForegroundsCoalesce() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), request = h.model.captureRefresh(context: h.model.contextTicket())!
        XCTAssertNil(h.model.captureRefresh(context: context), "The synchronous event already reserved this refresh")
        let task = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        await h.model.refresh(request)
        for _ in 0..<10 { XCTAssertNil(h.model.captureRefresh(context: context)) }
        XCTAssertEqual(h.reads.count, 2); XCTAssertEqual(h.model.activity.activeLoadCount, 1)
        h.finishRead(1, ids: ["fresh"]); await task.value
        await h.model.refresh(request); XCTAssertEqual(h.reads.count, 2)
        XCTAssertNotNil(h.model.captureRefresh(context: context), "A later foreground may start a fresh observation")
    }

    func testPendingFormCaptureIsNotConsumedByRefresh() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), save = h.model.captureSave(ids: ["local"], context: h.model.contextTicket())!
        XCTAssertNil(h.model.captureRefresh(context: context))
        let task = Task { await h.model.saveInterests(save) }; await h.waitForWrites(1)
        h.finishWrite(0); let saved = await task.value
        XCTAssertTrue(saved); XCTAssertEqual(h.model.preferences.interestTopicIDs, ["local"])
    }

    func testCancelledUnstartedSaveRetiresOnlyItsCaptureAndAllowsRefresh() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), save = h.model.captureSave(ids: ["never-dispatched"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(save) }; task.cancel()
        let result = await task.value; XCTAssertFalse(result); XCTAssertTrue(h.writes.isEmpty)
        let request = h.model.captureRefresh(context: context)
        guard let request else { return XCTFail("An abandoned pre-dispatch event must not block all later foreground refreshes") }
        let refresh = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        h.finishRead(1, ids: ["server-current"]); await refresh.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["server-current"])
    }

    func testAbandoningOldSaveCaptureCannotClearNewerPendingEvent() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), old = h.model.captureSave(ids: ["old"], context: h.model.contextTicket())!
        let newer = h.model.captureSave(ids: ["newer-local"], context: context)!
        h.model.abandonCapture(old)
        let cancelledOld = Task { await h.model.saveInterests(old) }; cancelledOld.cancel()
        let oldResult = await cancelledOld.value; XCTAssertFalse(oldResult)
        XCTAssertNil(h.model.captureRefresh(context: context))
        let task = Task { await h.model.saveInterests(newer) }; await h.waitForWrites(1)
        h.finishWrite(0); let result = await task.value; XCTAssertTrue(result)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["newer-local"])
    }

    func testDelayedAndTimedOutWriteKeepPhysicalSlotAndUnconfirmedError() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["original"])
        let context = h.model.contextTicket(), save = h.model.captureSave(ids: ["local"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(save) }; await h.waitForWrites(1)
        XCTAssertNil(h.model.captureRefresh(context: context))
        h.deadlines[0](); let saved = await task.value; XCTAssertFalse(saved)
        let before = h.model.snapshot
        XCTAssertTrue(h.model.activity.activeSave); XCTAssertNil(h.model.captureRefresh(context: context))
        h.finishWrite(0)
        // The persistent unconfirmed error is a barrier even after physical completion.
        await waitUntil { !h.model.activity.activeSave }
        XCTAssertNil(h.model.captureRefresh(context: context)); XCTAssertEqual(h.model.snapshot, before)
    }

    func testFailedSaveRetainsErrorAndRetryIntentInsteadOfAdoptingRemoteValues() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), first = h.model.captureSave(ids: ["local"], context: h.model.contextTicket())!
        let failed = Task { await h.model.saveInterests(first) }; await h.waitForWrites(1)
        h.finishWrite(0, error: URLError(.notConnectedToInternet)); let result = await failed.value
        XCTAssertFalse(result); XCTAssertNil(h.model.captureRefresh(context: context))
        XCTAssertNotNil(h.model.errorMessage); XCTAssertEqual(h.reads.count, 1)
        let retry = h.model.captureSave(ids: ["local"], context: context)!
        let saved = Task { await h.model.saveInterests(retry) }; await h.waitForWrites(2)
        XCTAssertNil(h.model.captureRefresh(context: context))
        h.finishWrite(1); let retried = await saved.value; XCTAssertTrue(retried)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["local"])
    }

    func testNewSaveCaptureWinsOverActiveRefreshAndItsLateResult() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), request = h.model.captureRefresh(context: h.model.contextTicket())!
        let refresh = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        let save = h.model.captureSave(ids: ["local-newer"], context: context)!
        await refresh.value
        XCTAssertFalse(h.reads[1].guardCurrent()); XCTAssertEqual(h.model.activity.activeLoadCount, 1)
        let saved = Task { await h.model.saveInterests(save) }; await h.waitForWrites(1)
        h.finishWrite(0); let result = await saved.value; XCTAssertTrue(result)
        let accepted = h.model.snapshot
        h.finishRead(1, ids: ["old-remote"]); await waitUntil { h.model.activity.activeLoadCount == 0 }
        XCTAssertEqual(h.model.snapshot, accepted)
    }

    func testNewSaveCaptureBeforeRefreshTaskStartsPreventsTheRead() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureRefresh(context: h.model.contextTicket())!
        _ = h.model.captureSave(ids: ["local"], context: h.model.contextTicket())!
        await h.model.refresh(request)
        XCTAssertEqual(h.reads.count, 1)
    }

    func testRefreshReentryCannotStealTheAuthorityOfSaveCapture() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        var nestedRefresh: ReaderPreferencesModel.RefreshRequest?
        h.onIdentityRead = {
            h.onIdentityRead = nil
            nestedRefresh = h.model.captureRefresh(context: h.model.contextTicket())
        }
        let save = h.model.captureSave(ids: ["local-priority"], context: h.model.contextTicket())
        guard let save, let nestedRefresh else { return XCTFail("The injected refresh event must not cancel the button event") }
        await h.model.refresh(nestedRefresh)
        XCTAssertEqual(h.reads.count, 1)
        let task = Task { await h.model.saveInterests(save) }; await h.waitForWrites(1)
        h.finishWrite(0); let result = await task.value; XCTAssertTrue(result)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["local-priority"])
    }

    func testPendingNewerSaveRemainsQueuedBehindOldPhysicalWrite() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), first = h.model.captureSave(ids: ["first"], context: h.model.contextTicket())!
        let a = Task { await h.model.saveInterests(first) }; await h.waitForWrites(1)
        let next = h.model.captureSave(ids: ["latest-local"], context: context)!
        let b = Task { await h.model.saveInterests(next) }; await h.waitForSaving(next)
        XCTAssertNil(h.model.captureRefresh(context: context)); XCTAssertTrue(h.model.activity.pendingSave)
        XCTAssertEqual(h.reads.count, 1); XCTAssertEqual(h.writes.count, 1)
        h.finishWrite(0); await h.waitForWrites(2)
        XCTAssertEqual(h.writes[1].request.preferences.interestTopicIDs, ["latest-local"])
        h.finishWrite(1); let firstResult = await a.value, nextResult = await b.value
        XCTAssertFalse(firstResult); XCTAssertTrue(nextResult)
    }

    func testExplicitLoadSupersedesRefreshWithoutOldCleanupRetiringNewLoad() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), request = h.model.captureRefresh(context: h.model.contextTicket())!
        let refresh = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        let load = Task { await h.model.retry(context) }; await h.waitForReads(3)
        await refresh.value; h.finishRead(1, ids: ["obsolete"])
        await waitUntil { h.model.activity.activeLoadCount == 1 }
        XCTAssertTrue(h.model.isLoading); XCTAssertNil(h.model.captureRefresh(context: context))
        h.finishRead(2, ids: ["explicit"]); await load.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["explicit"])
    }

    func testCancellationRetiresWaiterButKeepsPhysicalReadUntilCallback() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let before = h.model.snapshot, context = h.model.contextTicket()
        let request = h.model.captureRefresh(context: context)!
        let task = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        task.cancel(); await task.value
        XCTAssertFalse(h.reads[1].guardCurrent()); XCTAssertEqual(h.model.activity.activeLoadCount, 1)
        XCTAssertNil(h.model.captureRefresh(context: context))
        h.finishRead(1, ids: ["cancelled"]); await waitUntil { h.model.activity.activeLoadCount == 0 }
        XCTAssertEqual(h.model.snapshot, before)
        XCTAssertNotNil(h.model.captureRefresh(context: context))
    }

    func testCancelledTaskBeforeRefreshEntryDoesNotOccupyReadLane() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureRefresh(context: h.model.contextTicket())!
        let task = Task { await h.model.refresh(request) }; task.cancel(); await task.value
        XCTAssertEqual(h.reads.count, 1); XCTAssertEqual(h.model.activity.activeLoadCount, 0)
        XCTAssertNotNil(h.model.captureRefresh(context: h.model.contextTicket()))
    }

    func testAccountSwitchAndSameUIDReturnRejectOldResponseAndOldCapture() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let originalContext = h.model.contextTicket(), request = h.model.captureRefresh(context: h.model.contextTicket())!
        let task = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        _ = h.select("B"); await h.loaded("A", ids: ["new-A-session"])
        let before = h.model.snapshot
        await task.value; XCTAssertFalse(h.reads[1].guardCurrent())
        XCTAssertNil(h.model.captureRefresh(context: originalContext))
        h.finishRead(1, ids: ["old-A"]); await waitUntil { h.model.activity.activeLoadCount == 0 }
        XCTAssertEqual(h.model.snapshot, before)
        await h.model.refresh(request); XCTAssertEqual(h.reads.count, 3)
    }

    func testRevokedOriginalPermissionNeverBorrowsRestoredPermission() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        var allowed = true
        let request = h.model.captureRefresh(context: h.model.contextTicket(), stillCurrent: { allowed })!
        let before = h.model.snapshot
        let task = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        allowed = false; XCTAssertFalse(h.reads[1].guardCurrent())
        allowed = true; XCTAssertFalse(h.reads[1].guardCurrent())
        h.finishRead(1, ids: ["denied"]); await task.value
        XCTAssertEqual(h.model.snapshot, before)
    }

    func testIdentityReentryDuringCaptureCannotBorrowNewAccount() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket()
        h.onIdentityRead = { h.onIdentityRead = nil; _ = h.select("B") }
        XCTAssertNil(h.model.captureRefresh(context: context))
        XCTAssertEqual(h.reads.count, 1); XCTAssertEqual(h.model.userID, "B")
    }

    func testSaveCapturedDuringRefreshPublicationRejectsRemoteCommit() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureRefresh(context: h.model.contextTicket())!
        var save: ReaderPreferencesModel.SaveRequest?
        let subscription = h.model.objectWillChange.sink {
            guard save == nil else { return }
            save = h.model.captureSave(ids: ["local-during-publication"], context: h.model.contextTicket())
        }
        let task = Task { await h.model.refresh(request) }; await h.waitForReads(2)
        h.finishRead(1, ids: ["remote"]); await task.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["A"])
        guard let save else { return XCTFail("The original form action should remain valid") }
        let write = Task { await h.model.saveInterests(save) }; await h.waitForWrites(1)
        h.finishWrite(0); let result = await write.value; XCTAssertTrue(result)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["local-during-publication"])
        withExtendedLifetime(subscription) {}
    }

    func testUnstartedGuestAndForeignModelCapturesAreInert() async {
        let h = ReaderPreferencesHarness(started: false), foreign = ReaderPreferencesHarness()
        defer { h.close(); foreign.close() }
        let account = h.select("A")
        XCTAssertNil(h.model.captureRefresh(context: account)); XCTAssertEqual(h.identityReads, 0)
        h.model.start(); let guest = h.select(nil)
        XCTAssertNil(h.model.captureRefresh(context: guest)); XCTAssertEqual(h.identityReads, 0)
        await foreign.loaded("A"); _ = h.select("A")
        XCTAssertNil(h.model.captureRefresh(context: foreign.model.contextTicket())); XCTAssertTrue(h.reads.isEmpty)
    }

    /// The injected provider ignores cancellation. Wait for its physical
    /// continuation/defer, without network, clocks, Firebase or SDK startup.
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("The released local provider did not retire its physical slot", file: file, line: line)
    }
}
