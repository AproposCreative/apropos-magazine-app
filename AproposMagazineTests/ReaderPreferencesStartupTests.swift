import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual model and physical callback lanes; no app services or Firebase app.
@MainActor
final class ReaderPreferencesStartupTests: XCTestCase {
    private typealias Model = ReaderPreferencesModel
    @MainActor private final class Harness {
        struct Read {
            let original: Model.Guard
            var continuation: CheckedContinuation<Model.ReadResult, Error>?
        }
        struct Write {
            let request: Model.SaveRequest
            let original: Model.Guard
            var continuation: CheckedContinuation<Void, Error>?
        }
        let canonical = CanonicalSessionState()
        var actualUID: String? = "A"
        var permits = true, capturable = true
        var captures = 0, identities = 0
        var captureHook: (() -> Void)?, identityHook: (() -> Void)?
        var readHook: (() -> Void)?, writeHook: (() -> Void)?, scheduleHook: (() -> Void)?
        var cancelHook: ((Int) -> Void)?
        var reads: [Read] = [], writes: [Write] = []
        var deadlines: [@MainActor () -> Void] = [], cancelledDeadlines: [Int] = []
        private var readWaiters: [(Int, XCTestExpectation)] = [], writeWaiters: [(Int, XCTestExpectation)] = []
        lazy var model = Model(capturePermission: { [weak self] in
            guard let self else { return nil }
            self.captures += 1
            let context = self.canonical.contextTicket()
            self.captureHook?()
            guard self.capturable else { return nil }
            return { [weak self] in self?.permits == true && self?.canonical.isCurrent(context) == true }
        }, identity: { [weak self] in
            guard let self else { return .init(actualUID: nil, canonicalUID: nil) }
            self.identities += 1
            let original = Model.Identity(actualUID: self.actualUID, canonicalUID: self.canonical.snapshot.userID)
            self.identityHook?()
            return original
        }, load: { [weak self] _, original in
            guard let self else { throw CancellationError() }
            self.readHook?()
            guard original() else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                self.reads.append(.init(original: original, continuation: continuation))
                self.notify(read: true)
            }
        }, save: { [weak self] request, original in
            guard let self else { throw CancellationError() }
            self.writeHook?()
            guard original() else { throw CancellationError() }
            try await withCheckedThrowingContinuation { continuation in
                self.writes.append(.init(request: request, original: original, continuation: continuation))
                self.notify(read: false)
            }
        }, schedule: { [weak self] deadline in
            guard let self else { return {} }
            let index = self.deadlines.count; self.deadlines.append(deadline)
            self.scheduleHook?()
            return { [weak self] in self?.cancelledDeadlines.append(index); self?.cancelHook?(index) }
        })
        init(started: Bool = true) { select("A"); if started { model.start() } }
        @discardableResult func select(_ uid: String?) -> Model.ContextTicket {
            actualUID = uid
            canonical.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
            return model.changeContext(to: .confirmed(userID: uid)) ?? model.contextTicket()
        }
        func loaded(_ ids: [String] = ["old"]) async {
            let context = model.contextTicket(), count = reads.count + 1
            let task = Task { await model.load(context) }
            await waitForReads(count); finishRead(count - 1, ids: ids); await task.value
            XCTAssertTrue(model.hasLoaded)
        }
        func finishRead(_ index: Int, ids: [String] = ["new"], missing: Bool = false, cached: Bool = false, fail: Bool = false) {
            let continuation = reads[index].continuation; reads[index].continuation = nil
            if fail { continuation?.resume(throwing: URLError(.notConnectedToInternet)) }
            else { continuation?.resume(returning: .init(preferences: missing ? nil : .init(interestTopicIDs: ids), isFromCache: cached)) }
        }
        func finishWrite(_ index: Int, fail: Bool = false) {
            let continuation = writes[index].continuation; writes[index].continuation = nil
            if fail { continuation?.resume(throwing: URLError(.notConnectedToInternet)) }
            else { continuation?.resume() }
        }
        func waitForReads(_ count: Int) async { await wait(count, read: true) }
        func waitForWrites(_ count: Int) async { await wait(count, read: false) }
        private func wait(_ count: Int, read: Bool) async {
            if (read ? reads.count : writes.count) >= count { return }
            let expectation = XCTestExpectation(description: "Original preferences transport starts")
            if read { readWaiters.append((count, expectation)) } else { writeWaiters.append((count, expectation)) }
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
            XCTAssertEqual(result, .completed)
        }
        private func notify(read: Bool) {
            if read {
                let ready = readWaiters.filter { $0.0 <= reads.count }; readWaiters.removeAll { $0.0 <= reads.count }
                ready.forEach { $0.1.fulfill() }
            } else {
                let ready = writeWaiters.filter { $0.0 <= writes.count }; writeWaiters.removeAll { $0.0 <= writes.count }
                ready.forEach { $0.1.fulfill() }
            }
        }
        func waitForSave(_ request: Model.SaveRequest) async {
            if model.isCurrent(request), model.isSaving { return }
            let expectation = XCTestExpectation(description: "Original save admitted")
            var fulfilled = false
            let observer = model.changes.sink { [weak self] _ in
                guard let self, !fulfilled, self.model.isCurrent(request), self.model.isSaving else { return }
                fulfilled = true; expectation.fulfill()
            }
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
            XCTAssertEqual(result, .completed); withExtendedLifetime(observer) {}
        }
        func close() {
            permits = false; captureHook = nil; identityHook = nil; readHook = nil; writeHook = nil
            scheduleHook = nil; cancelHook = nil
            for index in reads.indices where reads[index].continuation != nil { finishRead(index, fail: true) }
            for index in writes.indices where writes[index].continuation != nil { finishWrite(index, fail: true) }
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testConstructionAndUnstartedLoadDoNotCaptureOrReadIdentity() async {
        let h = Harness(started: false); defer { h.close() }
        XCTAssertEqual(h.captures, 0); XCTAssertEqual(h.identities, 0)
        await h.model.load(h.model.contextTicket())
        XCTAssertNil(h.model.capturePermissionForCurrentContext(h.model.contextTicket()))
        XCTAssertEqual(h.captures, 0); XCTAssertEqual(h.identities, 0); XCTAssertTrue(h.reads.isEmpty)
    }
    func testClosedCaptureCannotPublishLoadingOrReadIdentity() async {
        for unavailable in [true, false] {
            let h = Harness(); defer { h.close() }
            if unavailable { h.capturable = false } else { h.permits = false }
            let before = h.model.snapshot
            await h.model.load(h.model.contextTicket())
            XCTAssertNil(h.model.captureSave(ids: ["music"], context: h.model.contextTicket()))
            XCTAssertEqual(h.model.snapshot, before); XCTAssertEqual(h.identities, 0)
            XCTAssertTrue(h.reads.isEmpty); XCTAssertTrue(h.writes.isEmpty)
        }
    }
    func testClosedParentRejectsDeferredLoadAndRetryBeforeRuntimeCapture() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        await h.model.load(context, stillCurrent: { false }); await h.model.retry(context, stillCurrent: { false })
        XCTAssertEqual(h.captures, 0); XCTAssertEqual(h.identities, 0); XCTAssertFalse(h.model.isLoading)
    }
    func testCancelledTaskBeforeAdmissionDoesNotCaptureOrStartRead() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await h.model.load(context)
        }
        await task.value
        XCTAssertEqual(h.captures, 0); XCTAssertTrue(h.reads.isEmpty); XCTAssertFalse(h.model.isLoading)
    }
    func testSynchronousCaptureLatchesDenialBeforeTaskAndDoesNotAdoptReopenedGate() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        guard let permission = h.model.capturePermissionForCurrentContext(context) else { return XCTFail("Expected capture") }
        h.permits = false; XCTAssertFalse(permission()); h.permits = true
        let count = h.captures
        await h.model.load(context, stillCurrent: permission)
        XCTAssertEqual(h.captures, count); XCTAssertTrue(h.reads.isEmpty)
    }
    func testOrdinaryPermissionCaptureDoesNotInvalidateAnAlreadyActiveRead() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        XCTAssertNotNil(h.model.capturePermissionForCurrentContext(context))
        XCTAssertTrue(h.reads[0].original())
        h.finishRead(0); await task.value
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["new"])
    }
    func testCaptureHookAccountRoundTripCannotStartOriginalLoad() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        h.captureHook = { [unowned h] in h.captureHook = nil; h.select(nil); h.select("A") }
        await h.model.load(context)
        XCTAssertTrue(h.reads.isEmpty); XCTAssertFalse(h.model.isLoading)
    }
    func testNestedNewButtonCaptureSurvivesOuterCaptureHook() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        var newer: Model.SaveRequest?
        h.captureHook = { [unowned h] in
            h.captureHook = nil; newer = h.model.captureSave(ids: ["newer"], context: h.model.contextTicket())
        }
        XCTAssertNil(h.model.captureSave(ids: ["older"], context: h.model.contextTicket()))
        guard let newer else { return XCTFail("Expected the nested original capture") }
        let task = Task { await h.model.saveInterests(newer) }; await h.waitForWrites(1)
        XCTAssertEqual(h.writes[0].request.preferences.interestTopicIDs, ["newer"])
        h.finishWrite(0); let saved = await task.value; XCTAssertTrue(saved)
    }
    func testWillChangeDenialCannotAssignLoadingOrStartRead() async {
        let h = Harness(); defer { h.close() }
        let observer = h.model.objectWillChange.sink { h.permits = false }
        await h.model.load(h.model.contextTicket())
        XCTAssertFalse(h.model.isLoading); XCTAssertTrue(h.reads.isEmpty); XCTAssertNil(h.model.errorMessage)
        withExtendedLifetime(observer) {}
    }
    func testPostPublicationDenialRetiresOwnSpinnerWithoutTransport() async {
        let h = Harness(); defer { h.close() }
        let observer = h.model.changes.sink { if $0.isLoading { h.permits = false } }
        await h.model.load(h.model.contextTicket())
        XCTAssertFalse(h.model.isLoading); XCTAssertFalse(h.model.activity.pendingLoad)
        XCTAssertEqual(h.model.activity.activeLoadCount, 0); XCTAssertTrue(h.reads.isEmpty)
        withExtendedLifetime(observer) {}
    }
    func testReadResultWillChangeDenialCannotPublishPreferencesOrLoadedReceipt() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        let observer = h.model.objectWillChange.sink { h.permits = false }
        h.finishRead(0); await task.value
        XCTAssertFalse(h.model.isLoading); XCTAssertFalse(h.model.hasLoaded)
        XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty); XCTAssertNil(h.model.errorMessage)
        withExtendedLifetime(observer) {}
    }
    func testReadFailureWillChangeDenialCannotPublishOldError() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        let observer = h.model.objectWillChange.sink { h.permits = false }
        h.finishRead(0, fail: true); await task.value
        XCTAssertNil(h.model.errorMessage); XCTAssertFalse(h.model.isLoading)
        withExtendedLifetime(observer) {}
    }
    func testDeniedHeldReadRetainsPhysicalSlotUntilReturnAndCannotRevive() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        h.permits = false; XCTAssertFalse(h.reads[0].original()); h.permits = true
        XCTAssertEqual(h.model.activity.activeLoadCount, 1)
        h.finishRead(0); await task.value
        XCTAssertFalse(h.model.hasLoaded); XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty)
        XCTAssertEqual(h.model.activity.activeLoadCount, 0)
    }
    func testCacheMissingDeniedReplyCannotPublishDefaultsOrRetryError() async {
        let h = Harness(); defer { h.close() }; let context = h.model.contextTicket()
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        h.permits = false; h.finishRead(0, missing: true, cached: true); await task.value
        XCTAssertFalse(h.model.hasLoaded); XCTAssertNil(h.model.errorMessage); XCTAssertFalse(h.model.isLoading)
    }
    func testSaveUsesButtonPermissionWithoutRecaptureAfterTaskStarts() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let captures = h.captures
        h.capturable = false
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        XCTAssertEqual(h.captures, captures)
        h.finishWrite(0); let saved = await task.value
        XCTAssertTrue(saved); XCTAssertTrue(h.model.isCurrent(request)); XCTAssertEqual(h.captures, captures)
    }
    func testButtonPermissionDeniedBeforeSaveCannotBorrowReopenedRuntime() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        var parent = true
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket(), stillCurrent: { parent })!
        let captures = h.captures; parent = false
        let saved = await h.model.saveInterests(request); parent = true
        let retry = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertFalse(retry); XCTAssertEqual(h.captures, captures)
        XCTAssertTrue(h.writes.isEmpty)
    }
    func testSaveBeginWillChangeDenialCannotStartWriteOrSpinner() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let observer = h.model.objectWillChange.sink { h.permits = false }
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty); XCTAssertFalse(h.model.isSaving)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["old"])
        withExtendedLifetime(observer) {}
    }
    func testSaveResultWillChangeDenialCannotAssignValuesOrClaimSuccess() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        let observer = h.model.objectWillChange.sink { h.permits = false }
        h.finishWrite(0); let saved = await task.value
        XCTAssertFalse(saved); XCTAssertFalse(h.model.isSaving); XCTAssertFalse(h.model.isCurrent(request))
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["old"]); XCTAssertNil(h.model.errorMessage)
        withExtendedLifetime(observer) {}
    }
    func testSaveFailureWillChangeDenialCannotPublishUnconfirmedError() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        let observer = h.model.objectWillChange.sink { h.permits = false }
        h.finishWrite(0, fail: true); let saved = await task.value
        XCTAssertFalse(saved); XCTAssertNil(h.model.errorMessage); XCTAssertFalse(h.model.isSaving)
        withExtendedLifetime(observer) {}
    }
    func testDeadlineDenialClearsOnlyOwnSpinnerAndKeepsPhysicalWriteOccupied() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        let observer = h.model.objectWillChange.sink { h.permits = false }
        h.deadlines[0](); let saved = await task.value
        XCTAssertFalse(saved); XCTAssertFalse(h.model.isSaving); XCTAssertNil(h.model.errorMessage)
        XCTAssertTrue(h.model.activity.activeSave); XCTAssertEqual(h.model.preferences.interestTopicIDs, ["old"])
        withExtendedLifetime(observer) {}
    }
    func testSuccessfulReceiptRetainsOriginalDenialEvenWhenGateReopens() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        h.finishWrite(0); let saved = await task.value; XCTAssertTrue(saved)
        XCTAssertTrue(h.model.isCurrent(request)); let captures = h.captures
        h.permits = false; XCTAssertFalse(h.model.isCurrent(request)); h.permits = true
        XCTAssertFalse(h.model.isCurrent(request)); XCTAssertEqual(h.captures, captures)
    }
    func testDeadlineCancellationHookChangingAccountCannotReturnTrueReceipt() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        h.cancelHook = { [unowned h] _ in h.cancelHook = nil; h.select("B") }
        h.finishWrite(0); let saved = await task.value
        XCTAssertFalse(saved); XCTAssertEqual(h.model.userID, "B"); XCTAssertFalse(h.model.isCurrent(request))
        XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty)
    }
    func testDeadlineCancellationHookDenialCannotReturnTrueWithoutAccountChange() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        h.cancelHook = { [unowned h] _ in h.permits = false }
        h.finishWrite(0); let saved = await task.value
        XCTAssertFalse(saved); XCTAssertFalse(h.model.isCurrent(request)); XCTAssertEqual(h.model.userID, "A")
    }
    func testScheduleHookDenialCannotStartPhysicalWrite() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        h.scheduleHook = { [unowned h] in h.permits = false }
        let saved = await h.model.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertTrue(h.writes.isEmpty); XCTAssertFalse(h.model.isSaving)
        XCTAssertEqual(h.cancelledDeadlines, [0])
    }
    func testNestedCaptureDuringCancelledContextPublicationIsNotErased() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        var nested: Model.SaveRequest?, entered = false
        let observer = h.model.objectWillChange.sink {
            guard !entered else { return }; entered = true
            _ = h.model.changeContext(to: .account("A"))
            nested = h.model.captureSave(ids: ["nested"], context: h.model.contextTicket())
        }
        XCTAssertNil(h.model.changeContext(to: .account("B")))
        XCTAssertEqual(h.model.userID, "A")
        guard let nested else { return XCTFail("Nested capture must be retained") }
        let task = Task { await h.model.saveInterests(nested) }; await h.waitForWrites(1)
        h.finishWrite(0); let saved = await task.value; XCTAssertTrue(saved)
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["nested"])
        withExtendedLifetime(observer) {}
    }
    func testSupersededDeadlineCancelCannotScheduleOlderPendingJobAfterNewCapture() async {
        let h = Harness(); defer { h.close() }; await h.loaded()
        let first = h.model.captureSave(ids: ["first"], context: h.model.contextTicket())!
        let a = Task { await h.model.saveInterests(first) }; await h.waitForWrites(1)
        let second = h.model.captureSave(ids: ["second"], context: h.model.contextTicket())!
        var newest: Model.SaveRequest?
        h.cancelHook = { [unowned h] _ in
            h.cancelHook = nil; newest = h.model.captureSave(ids: ["newest"], context: h.model.contextTicket())
        }
        let rejected = await h.model.saveInterests(second)
        XCTAssertFalse(rejected); XCTAssertFalse(h.model.activity.pendingSave)
        XCTAssertEqual(h.deadlines.count, 1); XCTAssertEqual(h.writes.count, 1)
        guard let newest else { return XCTFail("New button capture must remain usable") }
        let c = Task { await h.model.saveInterests(newest) }; await h.waitForSave(newest)
        h.finishWrite(0); await h.waitForWrites(2)
        XCTAssertEqual(h.writes[1].request.preferences.interestTopicIDs, ["newest"])
        h.finishWrite(1); let old = await a.value, current = await c.value
        XCTAssertFalse(old); XCTAssertTrue(current)
    }
}
