import XCTest
@testable import Apropos

@MainActor
final class ReaderAccountActionsTests: XCTestCase {
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var actualUID: String?
        var reads: [String] = []
        var writes: [(String, ReaderPreferences)] = []
        var verificationCalls: [String] = []
        var refreshCalls: [String] = []
        var onWrite: ((ReaderPreferencesModel.SaveRequest) async throws -> Void)?
        var onVerify: ((CanonicalSessionState.ContextTicket) async -> Void)?
        var onRefresh: ((CanonicalSessionState.ContextTicket) async throws -> Void)?
        lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [unowned self] in
            .init(actualUID: self.actualUID, canonicalUID: self.canonical.snapshot.userID)
        }, load: { [unowned self] ticket, guardOperation in
            guard guardOperation() else { throw CancellationError() }
            self.reads.append(ticket.userID!)
            return .init(preferences: ReaderPreferences(interestTopicIDs: [ticket.userID!]), isFromCache: false)
        }, save: { [unowned self] request, guardOperation in
            guard guardOperation() else { throw CancellationError() }
            self.writes.append((request.userID, request.preferences))
            try await self.onWrite?(request)
        }, schedule: { _ in {} })
        lazy var actions = ReaderAccountActions(canonical: canonical, preferences: preferences,
            verify: { [unowned self] ticket in
                self.verificationCalls.append(ticket.userID!)
                await self.onVerify?(ticket)
            }, refresh: { [unowned self] ticket in
                self.refreshCalls.append(ticket.userID!)
                try await self.onRefresh?(ticket)
            })
        func select(_ uid: String?) async {
            actualUID = uid
            let ticket = preferences.changeContext(to: .confirmed(userID: uid))
            _ = canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: false) })
            preferences.start()
            if let ticket { await preferences.load(ticket) }
        }
    }
    func testConstructionAndUnresolvedCaptureDoNotStartAnyTransport() {
        let fixture = Fixture(); let context = fixture.canonical.contextTicket()
        XCTAssertNil(fixture.actions.captureOwner(userID: "A", context: context))
        XCTAssertNil(fixture.actions.captureSave(ids: ["music"], userID: "A", context: context))
        XCTAssertTrue(fixture.reads.isEmpty); XCTAssertTrue(fixture.writes.isEmpty)
        XCTAssertTrue(fixture.verificationCalls.isEmpty); XCTAssertTrue(fixture.refreshCalls.isEmpty)
    }
    func testActualFormEventCapturesOriginalPayloadBeforeDelayedTaskStarts() async throws {
        let fixture = Fixture(); await fixture.select("A")
        var selected = ["music"]
        let action = try XCTUnwrap(fixture.actions.captureSave(ids: selected, userID: "A", context: fixture.canonical.contextTicket()))
        selected = ["culture"]
        let saved = await fixture.actions.save(action)
        XCTAssertTrue(saved); XCTAssertEqual(fixture.writes.count, 1)
        XCTAssertEqual(fixture.writes.first?.0, "A"); XCTAssertEqual(fixture.writes.first?.1.interestTopicIDs, ["music"])
        XCTAssertEqual(selected, ["culture"])
    }
    func testHeldOriginalAFormActionCannotChooseBForSaveVerifyRefreshOrRetry() async throws {
        let fixture = Fixture(); await fixture.select("A"); let context = fixture.canonical.contextTicket()
        let owner = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: context))
        let save = try XCTUnwrap(fixture.actions.captureSave(ids: ["old-A"], userID: "A", context: context))
        await fixture.select("B"); let reads = fixture.reads
        let saved = await fixture.actions.save(save), verified = await fixture.actions.sendVerification(owner)
        let refreshed = try await fixture.actions.refresh(owner), retried = await fixture.actions.retry(owner)
        XCTAssertFalse(saved); XCTAssertFalse(verified); XCTAssertFalse(refreshed); XCTAssertFalse(retried)
        XCTAssertTrue(fixture.writes.isEmpty); XCTAssertTrue(fixture.verificationCalls.isEmpty); XCTAssertTrue(fixture.refreshCalls.isEmpty)
        XCTAssertEqual(fixture.reads, reads); XCTAssertEqual(fixture.preferences.preferences.interestTopicIDs, ["B"])
    }
    func testOldSameUIDViewCannotCaptureFreshOwnerAfterGuestAndReturn() async throws {
        let fixture = Fixture(); await fixture.select("A"); let oldContext = fixture.canonical.contextTicket()
        let oldAction = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: oldContext))
        await fixture.select(nil); await fixture.select("A")
        XCTAssertNil(fixture.actions.captureOwner(userID: "A", context: oldContext))
        XCTAssertNil(fixture.actions.captureSave(ids: ["old"], userID: "A", context: oldContext))
        let verified = await fixture.actions.sendVerification(oldAction)
        XCTAssertFalse(verified); XCTAssertTrue(fixture.verificationCalls.isEmpty)
        XCTAssertNotNil(fixture.actions.captureOwner(userID: "A", context: fixture.canonical.contextTicket()))
    }
    func testCanonicalAndPreferencesOwnerMismatchCannotBeAdoptedByInitialFormSelection() async {
        let fixture = Fixture(); await fixture.select("A")
        fixture.actualUID = "B"
        _ = fixture.canonical.adopt(ReaderAccountSession(uid: "B", email: "B@example.invalid", isEmailVerified: false))
        XCTAssertNil(fixture.actions.captureOwner(userID: "B", context: fixture.canonical.contextTicket()))
        XCTAssertNil(fixture.actions.captureSave(ids: fixture.preferences.preferences.interestTopicIDs,
            userID: "B", context: fixture.canonical.contextTicket()))
        XCTAssertTrue(fixture.writes.isEmpty)
    }
    func testFreshLoadInvalidatesAlreadyCapturedSaveWithoutStartingProvider() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let save = try XCTUnwrap(fixture.actions.captureSave(ids: ["old-form"], userID: "A", context: fixture.canonical.contextTicket()))
        await fixture.preferences.retry(fixture.preferences.contextTicket())
        let saved = await fixture.actions.save(save)
        XCTAssertFalse(saved); XCTAssertTrue(fixture.writes.isEmpty)
    }
    func testLateVerificationCannotReturnAcceptedOrPublishOldFeedbackForB() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let owner = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: fixture.canonical.contextTicket()))
        let held = AccountActionGate()
        fixture.onVerify = { context in
            guard let ticket = fixture.canonical.beginVerification(context: context) else { return }
            await held.hold()
            _ = fixture.canonical.finishVerification(ticket: ticket, message: "old A sent")
        }
        let sending = Task { await fixture.actions.sendVerification(owner) }
        await held.waitUntilHeld(); await fixture.select("B"); await held.release()
        let accepted = await sending.value
        XCTAssertFalse(accepted); XCTAssertEqual(fixture.verificationCalls, ["A"])
        XCTAssertNil(fixture.canonical.snapshot.verificationMessage); XCTAssertEqual(fixture.canonical.snapshot.userID, "B")
    }
    func testLateRefreshErrorIsDiscardedInsteadOfBecomingNewOwnersError() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let owner = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: fixture.canonical.contextTicket()))
        let held = AccountActionGate()
        fixture.onRefresh = { _ in await held.hold(); throw URLError(.notConnectedToInternet) }
        let refreshing = Task { try await fixture.actions.refresh(owner) }
        await held.waitUntilHeld(); await fixture.select("B"); await held.release()
        let accepted = try await refreshing.value
        XCTAssertFalse(accepted); XCTAssertEqual(fixture.refreshCalls, ["A"])
        XCTAssertNil(fixture.canonical.snapshot.verificationMessage)
    }
    func testCurrentRefreshErrorRemainsVisibleToOriginalForm() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let owner = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: fixture.canonical.contextTicket()))
        fixture.onRefresh = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await fixture.actions.refresh(owner); XCTFail("Current operation error must remain observable") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(fixture.refreshCalls, ["A"])
    }
    func testLateSaveReceiptCannotBecomeSuccessForReplacementOwner() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let action = try XCTUnwrap(fixture.actions.captureSave(ids: ["old-A"], userID: "A", context: fixture.canonical.contextTicket()))
        let held = AccountActionGate(); fixture.onWrite = { _ in await held.hold() }
        let saving = Task { await fixture.actions.save(action) }
        await held.waitUntilHeld(); await fixture.select("B"); await held.release()
        let saved = await saving.value
        // Owner revocation finishes the UI promise before the actual transport
        // callback. Keep the fixture alive until its real slot has drained.
        for _ in 0..<100 {
            if !fixture.preferences.activity.activeSave { break }
            await Task.yield()
        }
        XCTAssertFalse(fixture.preferences.activity.activeSave)
        XCTAssertFalse(saved); XCTAssertEqual(fixture.writes.count, 1); XCTAssertEqual(fixture.writes.first?.0, "A")
        XCTAssertEqual(fixture.preferences.userID, "B"); XCTAssertEqual(fixture.preferences.preferences.interestTopicIDs, ["B"])
    }
    func testHeldVerificationThroughGuestAndSameAccountReturnIsStillStale() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let owner = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: fixture.canonical.contextTicket()))
        let held = AccountActionGate(); fixture.onVerify = { _ in await held.hold() }
        let sending = Task { await fixture.actions.sendVerification(owner) }
        await held.waitUntilHeld(); await fixture.select(nil); await fixture.select("A"); await held.release()
        let accepted = await sending.value
        XCTAssertFalse(accepted); XCTAssertEqual(fixture.verificationCalls, ["A"])
        XCTAssertFalse(fixture.actions.isCurrent(owner))
    }
    func testRetryAndFreshActionsUseOnlyOriginalAcceptedMatchingOwner() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let owner = try XCTUnwrap(fixture.actions.captureOwner(userID: "A", context: fixture.canonical.contextTicket()))
        let retried = await fixture.actions.retry(owner), verified = await fixture.actions.sendVerification(owner)
        let refreshed = try await fixture.actions.refresh(owner)
        XCTAssertTrue(retried); XCTAssertTrue(verified); XCTAssertTrue(refreshed)
        XCTAssertEqual(fixture.reads, ["A", "A"]); XCTAssertEqual(fixture.verificationCalls, ["A"]); XCTAssertEqual(fixture.refreshCalls, ["A"])
    }
    func testSavedReceiptIsUnavailableBeforeAdmissionAndRevokedByFreshAcceptedLoad() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let action = try XCTUnwrap(fixture.actions.captureSave(ids: ["music"], userID: "A", context: fixture.canonical.contextTicket()))
        XCTAssertTrue(fixture.actions.isCurrent(action)); XCTAssertFalse(fixture.actions.isCurrentReceipt(action))
        let saved = await fixture.actions.save(action)
        XCTAssertTrue(saved); XCTAssertTrue(fixture.actions.isCurrentReceipt(action))
        await fixture.preferences.retry(fixture.preferences.contextTicket())
        XCTAssertTrue(fixture.actions.isCurrent(action)); XCTAssertFalse(fixture.actions.isCurrentReceipt(action))
    }
    func testNewActualSaveRevokesPriorSuccessReceiptWithoutChangingOwner() async throws {
        let fixture = Fixture(); await fixture.select("A"); let context = fixture.canonical.contextTicket()
        let first = try XCTUnwrap(fixture.actions.captureSave(ids: ["first"], userID: "A", context: context))
        let firstSaved = await fixture.actions.save(first)
        XCTAssertTrue(firstSaved); XCTAssertTrue(fixture.actions.isCurrentReceipt(first))
        let second = try XCTUnwrap(fixture.actions.captureSave(ids: ["second"], userID: "A", context: context))
        let secondSaved = await fixture.actions.save(second)
        XCTAssertTrue(secondSaved); XCTAssertFalse(fixture.actions.isCurrentReceipt(first))
        XCTAssertTrue(fixture.actions.isCurrentReceipt(second))
    }
    func testSameUIDNewOwnerEpochRevokesPreviouslyAcceptedSavedReceipt() async throws {
        let fixture = Fixture(); await fixture.select("A")
        let action = try XCTUnwrap(fixture.actions.captureSave(ids: ["saved"], userID: "A", context: fixture.canonical.contextTicket()))
        let saved = await fixture.actions.save(action)
        XCTAssertTrue(saved); XCTAssertTrue(fixture.actions.isCurrentReceipt(action))
        await fixture.select(nil); await fixture.select("A")
        XCTAssertFalse(fixture.actions.isCurrentReceipt(action)); XCTAssertFalse(fixture.actions.isCurrent(action))
    }
}

private actor AccountActionGate {
    private var held: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation; let waiting = observer; observer = nil; waiting?.resume()
        }
    }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { let value = held; held = nil; value?.resume() }
}
