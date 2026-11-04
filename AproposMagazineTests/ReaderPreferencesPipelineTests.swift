import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderPreferencesPipelineTests: XCTestCase {
    func testConstructorAndUnresolvedStartAreInert() async {
        let h = ReaderPreferencesHarness(started: false); defer { h.close() }
        XCTAssertEqual(h.identityReads, 0); XCTAssertTrue(h.reads.isEmpty); XCTAssertTrue(h.writes.isEmpty)
        let ticket = h.model.contextTicket()
        await h.model.load(ticket)
        XCTAssertEqual(h.identityReads, 0)
        h.model.start(); await h.model.load(ticket)
        XCTAssertTrue(h.reads.isEmpty); XCTAssertEqual(h.model.snapshot.context, .unresolved)
    }
    func testOriginalFormRequestCannotChooseNewOwnerWhenTaskStartsLate() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["private-A"], context: h.model.contextTicket())!
        await h.loaded("B")
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["B"])
    }
    func testSameUIDReturnDoesNotReviveOldFormRequestOrRetry() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let context = h.model.contextTicket(), request = h.model.captureSave(ids: ["old-A"], context: context)!
        _ = h.select(nil); await h.loaded("A", ids: ["new-A"])
        await h.model.retry(context)
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertEqual(h.reads.count, 2); XCTAssertTrue(h.writes.isEmpty)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["new-A"])
    }
    func testForeignModelTicketCannotReadOrSave() async {
        let a = ReaderPreferencesHarness(), b = ReaderPreferencesHarness(); defer { a.close(); b.close() }
        await a.loaded("A"); _ = b.select("A")
        await b.model.load(a.model.contextTicket())
        XCTAssertTrue(b.reads.isEmpty)
        XCTAssertNil(b.model.captureSave(ids: ["music"], context: a.model.contextTicket()))
    }
    func testNewlyAcceptedLoadInvalidatesPreviouslyCapturedFormRequest() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["old-form"], context: h.model.contextTicket())!
        await h.loaded("A", ids: ["server-new"])
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty)
    }
    func testRequestIsSingleUseAfterSuccessfulWrite() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["new"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1); h.finishWrite(0)
        let saved = await task.value; XCTAssertTrue(saved)
        let replay = await h.model.saveInterests(request)
        XCTAssertFalse(replay); XCTAssertEqual(h.writes.count, 1)
    }
    func testCapturingNewerEventRevokesAnUnstartedOlderEvent() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let a = h.model.captureSave(ids: ["old"], context: h.model.contextTicket())!
        _ = h.model.captureSave(ids: ["new"], context: h.model.contextTicket())!
        let saved = await h.model.saveInterests(a)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty)
    }
    func testReentrantNewerCaptureCannotBeOverwrittenByOuterOlderButtonEvent() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        var newer: ReaderPreferencesModel.SaveRequest?
        h.onIdentityRead = {
            h.onIdentityRead = nil
            newer = h.model.captureSave(ids: ["newer-event"], context: h.model.contextTicket())
        }
        let outer = h.model.captureSave(ids: ["older-event"], context: h.model.contextTicket())
        XCTAssertNil(outer, "Original event cannot borrow authority after a newer capture reentered its identity getter")
        guard let newer else { return XCTFail("Newer event must retain its original capture") }
        let task = Task { await h.model.saveInterests(newer) }; await h.waitForWrites(1)
        XCTAssertEqual(h.writes[0].request.preferences.interestTopicIDs, ["newer-event"])
        h.finishWrite(0); let saved = await task.value; XCTAssertTrue(saved)
    }
    func testFourRealReadSlotsAndOnlyLatestPendingReadSurviveFlood() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        var tasks: [Task<Void, Never>] = []
        for count in 1...4 {
            tasks.append(Task { await h.model.load(context) }); await h.waitForReads(count)
        }
        let pendingStarted = expectation(description: "Pending read publication")
        var pendingCount = 0
        let subscription = h.model.changes.sink { state in
            if state.isLoading { pendingCount += 1; if pendingCount == 2 { pendingStarted.fulfill() } }
        }
        tasks.append(Task { await h.model.load(context) })
        tasks.append(Task { await h.model.load(context) })
        await fulfillment(of: [pendingStarted], timeout: 3)
        XCTAssertEqual(h.model.activity.activeLoadCount, 4); XCTAssertTrue(h.model.activity.pendingLoad)
        XCTAssertEqual(h.reads.count, 4)
        h.finishRead(0, ids: ["stale"]); await h.waitForReads(5)
        XCTAssertEqual(h.model.activity.activeLoadCount, 4)
        h.finishRead(4, ids: ["latest"])
        for task in tasks { await task.value }
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["latest"])
        XCTAssertEqual(h.model.activity.activeLoadCount, 3)
        withExtendedLifetime(subscription) {}
    }
    func testUIWriteDeadlineFinishesFalseWithoutReleasingActualSlot() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["old"])
        let first = h.model.captureSave(ids: ["first"], context: h.model.contextTicket())!
        let a = Task { await h.model.saveInterests(first) }; await h.waitForWrites(1)
        h.deadlines[0]()
        let timedOut = await a.value; XCTAssertFalse(timedOut)
        XCTAssertTrue(h.model.activity.activeSave); XCTAssertFalse(h.model.isSaving)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["old"]); XCTAssertNotNil(h.model.errorMessage)
        let second = h.model.captureSave(ids: ["second"], context: h.model.contextTicket())!
        let b = Task { await h.model.saveInterests(second) }; await h.waitForSaving(second)
        XCTAssertEqual(h.writes.count, 1); XCTAssertTrue(h.model.activity.pendingSave)
        h.finishWrite(0); await h.waitForWrites(2)
        XCTAssertEqual(h.writes[1].request.preferences.interestTopicIDs, ["second"])
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["old"], "Late acknowledgement cannot report old timeout as saved")
        h.finishWrite(1); let saved = await b.value; XCTAssertTrue(saved)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["second"])
    }
    func testHeldOldWriteBlocksNewOwnerWriteUntilActualCallback() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let first = h.model.captureSave(ids: ["old-A"], context: h.model.contextTicket())!
        let a = Task { await h.model.saveInterests(first) }; await h.waitForWrites(1)
        await h.loaded("B")
        let second = h.model.captureSave(ids: ["new-B"], context: h.model.contextTicket())!
        let b = Task { await h.model.saveInterests(second) }; await h.waitForSaving(second)
        let stale = await a.value; XCTAssertFalse(stale)
        XCTAssertEqual(h.writes.count, 1); XCTAssertTrue(h.model.activity.activeSave)
        h.finishWrite(0, error: URLError(.notConnectedToInternet)); await h.waitForWrites(2)
        XCTAssertEqual(h.writes[1].request.userID, "B"); XCTAssertNil(h.model.errorMessage)
        h.finishWrite(1); let saved = await b.value; XCTAssertTrue(saved)
    }
    func testHeldWriteRemainsBarrierAcrossGuestAndSameUIDReturn() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let old = h.model.captureSave(ids: ["old"], context: h.model.contextTicket())!
        let a = Task { await h.model.saveInterests(old) }; await h.waitForWrites(1)
        _ = h.select(nil); await h.loaded("A", ids: ["restored"])
        let new = h.model.captureSave(ids: ["current"], context: h.model.contextTicket())!
        let b = Task { await h.model.saveInterests(new) }; await h.waitForSaving(new)
        XCTAssertEqual(h.writes.count, 1)
        h.finishWrite(0); await h.waitForWrites(2)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["restored"])
        h.finishWrite(1); let oldResult = await a.value, newResult = await b.value
        XCTAssertFalse(oldResult); XCTAssertTrue(newResult)
    }
    func testSerialWriteKeepsOnlyLatestWaitingRequestAndNoFalseReceipt() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let first = h.model.captureSave(ids: ["first"], context: h.model.contextTicket())!
        let a = Task { await h.model.saveInterests(first) }; await h.waitForWrites(1)
        let middle = h.model.captureSave(ids: ["middle"], context: h.model.contextTicket())!
        let b = Task { await h.model.saveInterests(middle) }; await h.waitForSaving(middle)
        let latest = h.model.captureSave(ids: ["latest"], context: h.model.contextTicket())!
        let c = Task { await h.model.saveInterests(latest) }; await h.waitForSaving(latest)
        let middleResult = await b.value; XCTAssertFalse(middleResult)
        XCTAssertEqual(h.writes.count, 1)
        h.finishWrite(0); await h.waitForWrites(2)
        XCTAssertEqual(h.writes[1].request.preferences.interestTopicIDs, ["latest"])
        h.finishWrite(1); let firstResult = await a.value, latestResult = await c.value
        XCTAssertFalse(firstResult); XCTAssertTrue(latestResult); XCTAssertEqual(h.writes.count, 2)
    }
    func testImmediateDeadlineNeverStartsAProviderWrite() async {
        let h = ReaderPreferencesHarness(immediateDeadline: true); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["new"], context: h.model.contextTicket())!
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty); XCTAssertFalse(h.model.isSaving)
        XCTAssertFalse(h.model.activity.activeSave); XCTAssertNotNil(h.model.errorMessage)
    }
    func testCacheMissDoesNotBecomeLoadedDefaultsOrPermitWrite() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        h.finishRead(0, absence: true, fromCache: true); await task.value
        XCTAssertFalse(h.model.hasLoaded); XCTAssertNotNil(h.model.errorMessage)
        XCTAssertNil(h.model.captureSave(ids: ["music"], context: context))
    }
    func testConfirmedServerAbsenceAllowsDefaultsWithoutCompletingOnboarding() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        h.finishRead(0, absence: true); await task.value
        XCTAssertTrue(h.model.hasLoaded); XCTAssertFalse(h.model.preferences.onboardingCompleted)
        XCTAssertNotNil(h.model.captureSave(ids: ["music"], context: context))
    }
    func testReadFailurePreservesValuesButBlocksUnconfirmedOverwriteUntilRetry() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["loaded"])
        let context = h.model.contextTicket(), version = h.model.snapshot.loadVersion
        let task = Task { await h.model.retry(context) }; await h.waitForReads(2)
        h.finishRead(1, error: URLError(.notConnectedToInternet)); await task.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["loaded"]); XCTAssertEqual(h.model.snapshot.loadVersion, version)
        XCTAssertFalse(h.model.hasLoaded); XCTAssertNil(h.model.captureSave(ids: ["new"], context: context))
        await h.loaded("A", ids: ["fresh"])
        XCTAssertNotEqual(h.model.snapshot.loadVersion, version); XCTAssertTrue(h.model.hasLoaded)
    }
    func testIdentityGetterReentryInvalidatesOriginalBeforeAnyRead() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        h.onIdentityRead = { h.onIdentityRead = nil; _ = h.select("B") }
        await h.model.load(context)
        XCTAssertTrue(h.reads.isEmpty); XCTAssertEqual(h.model.userID, "B")
    }
    func testIdentityGetterReentryInvalidatesCapturedSaveBeforeProvider() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["A-private"], context: h.model.contextTicket())!
        h.onIdentityRead = { h.onIdentityRead = nil; _ = h.select("B") }
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty); XCTAssertEqual(h.model.userID, "B")
    }
}

/// Private in-memory transports, carrying the actual production tickets/guards.
@MainActor
final class ReaderPreferencesHarness {
    struct Read { let context: ReaderPreferencesModel.ContextTicket; let guardCurrent: ReaderPreferencesModel.Guard; var continuation: CheckedContinuation<ReaderPreferencesModel.ReadResult, Error>? }
    struct Write { let request: ReaderPreferencesModel.SaveRequest; let guardCurrent: ReaderPreferencesModel.Guard; var continuation: CheckedContinuation<Void, Error>? }
    var actualUID: String?, canonicalUID: String?
    var identityReads = 0
    var onIdentityRead: (() -> Void)?
    var reads: [Read] = [], writes: [Write] = []
    var deadlines: [() -> Void] = []
    private var readObservers: [(Int, XCTestExpectation)] = [], writeObservers: [(Int, XCTestExpectation)] = []
    private let immediateDeadline: Bool
    lazy var model = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [weak self] in
        guard let self else { return .init(actualUID: nil, canonicalUID: nil) }
        self.identityReads += 1; self.onIdentityRead?()
        return .init(actualUID: self.actualUID, canonicalUID: self.canonicalUID)
    }, load: { [weak self] context, guardCurrent in
        guard let self else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.reads.append(.init(context: context, guardCurrent: guardCurrent, continuation: continuation))
            self.notify(&self.readObservers, count: self.reads.count)
        }
    }, save: { [weak self] request, guardCurrent in
        guard let self else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.writes.append(.init(request: request, guardCurrent: guardCurrent, continuation: continuation))
            self.notify(&self.writeObservers, count: self.writes.count)
        }
    }, schedule: { [weak self] deadline in
        guard let self else { return {} }
        self.deadlines.append(deadline)
        if self.immediateDeadline { deadline() }
        return {}
    })
    init(started: Bool = true, immediateDeadline: Bool = false) {
        self.immediateDeadline = immediateDeadline
        if started { model.start() }
    }
    @discardableResult func select(_ uid: String?) -> ReaderPreferencesModel.ContextTicket {
        actualUID = uid; canonicalUID = uid
        return model.changeContext(to: .confirmed(userID: uid)) ?? model.contextTicket()
    }
    func loaded(_ uid: String, ids: [String]? = nil) async {
        let context = select(uid), count = reads.count + 1
        let task = Task { await model.load(context) }
        await waitForReads(count); finishRead(count - 1, ids: ids ?? [uid]); await task.value
    }
    func finishRead(_ index: Int, ids: [String] = [], absence: Bool = false, fromCache: Bool = false, error: Error? = nil) {
        let continuation = reads[index].continuation; reads[index].continuation = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume(returning: .init(preferences: absence ? nil : ReaderPreferences(interestTopicIDs: ids), isFromCache: fromCache)) }
    }
    func finishWrite(_ index: Int, error: Error? = nil) {
        let continuation = writes[index].continuation; writes[index].continuation = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
    func waitForReads(_ count: Int) async { await wait(count, reads: true) }
    func waitForWrites(_ count: Int) async { await wait(count, reads: false) }
    func waitForSaving(_ request: ReaderPreferencesModel.SaveRequest) async {
        if model.isCurrent(request), model.isSaving { return }
        let expectation = XCTestExpectation(description: "Original request admitted")
        var fulfilled = false
        let subscription = model.changes.sink { [self] _ in
            if !fulfilled, model.isCurrent(request), model.isSaving { fulfilled = true; expectation.fulfill() }
        }
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed)
        withExtendedLifetime(subscription) {}
    }
    private func wait(_ count: Int, reads isRead: Bool) async {
        if (isRead ? reads.count : writes.count) >= count { return }
        let expectation = XCTestExpectation(description: isRead ? "Actual read started" : "Actual write started")
        if isRead { readObservers.append((count, expectation)) } else { writeObservers.append((count, expectation)) }
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed)
    }
    private func notify(_ observers: inout [(Int, XCTestExpectation)], count: Int) {
        let ready = observers.filter { $0.0 <= count }
        observers.removeAll { $0.0 <= count }; ready.forEach { $0.1.fulfill() }
    }
    func close() {
        onIdentityRead = nil
        for index in reads.indices where reads[index].continuation != nil { finishRead(index, error: CancellationError()) }
        for index in writes.indices where writes[index].continuation != nil { finishWrite(index, error: CancellationError()) }
    }
}
