import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderAccountVerificationCoordinatorTests: XCTestCase {
    @MainActor private final class Fixture {
        typealias Guard = ReaderAccountVerificationCoordinator.Guard
        let state = CanonicalSessionState()
        var actualUID: String?
        var identityReads = 0
        var onIdentity: (() -> Void)?
        var sends: [String] = []
        var refreshes: [String] = []
        var tokenRefreshes: [String] = []
        var send: ((CanonicalSessionState.VerificationTicket, @escaping Guard) async throws -> Void)?
        var refresh: ((CanonicalSessionState.RefreshTicket, @escaping Guard) async throws -> ReaderAccountSession)?
        lazy var coordinator = ReaderAccountVerificationCoordinator(state: state, effects: .init(
            actualUserID: { [unowned self] in
                self.identityReads += 1; self.onIdentity?(); return self.actualUID
            }, send: { [unowned self] ticket, permitted in
                guard permitted() else { throw CancellationError() }
                self.sends.append(ticket.userID!)
                try await self.send?(ticket, permitted)
            }, refresh: { [unowned self] ticket, permitted in
                guard permitted() else { throw CancellationError() }
                self.refreshes.append(ticket.userID!)
                if let refresh = self.refresh { return try await refresh(ticket, permitted) }
                return self.account(ticket.userID!, verified: true)
            }))
        func account(_ uid: String = "A", verified: Bool = false) -> ReaderAccountSession {
            ReaderAccountSession(uid: uid, email: uid + "@example.invalid", isEmailVerified: verified)
        }
        @discardableResult func select(_ uid: String?, verified: Bool = false) -> CanonicalSessionState.ContextTicket {
            actualUID = uid
            _ = state.adopt(uid.map { account($0, verified: verified) })
            return state.contextTicket()
        }
    }
    @MainActor private final class Gate {
        var held: CheckedContinuation<Void, Error>?
        private var observer: CheckedContinuation<Void, Never>?
        func hold() async throws {
            try await withCheckedThrowingContinuation { continuation in
                held = continuation; let waiting = observer; observer = nil; waiting?.resume()
            }
        }
        func waitUntilHeld() async {
            if held != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func release(error: Error? = nil) {
            let value = held; held = nil
            if let error { value?.resume(throwing: error) } else { value?.resume() }
        }
    }

    func testConstructionIsInertAndUnresolvedOrGuestCannotStartProviderEffects() async throws {
        let fixture = Fixture()
        XCTAssertFalse(fixture.coordinator.activity.sending); XCTAssertFalse(fixture.coordinator.activity.refreshing)
        XCTAssertEqual(fixture.identityReads, 0)
        await fixture.coordinator.sendVerification(context: fixture.state.contextTicket())
        try await fixture.coordinator.refreshSession(context: fixture.state.contextTicket())
        let guest = fixture.select(nil)
        await fixture.coordinator.sendVerification(context: guest); try await fixture.coordinator.refreshSession(context: guest)
        XCTAssertTrue(fixture.sends.isEmpty); XCTAssertTrue(fixture.refreshes.isEmpty)
    }
    func testCurrentSendSuccessFinishesOnlyActualSlotAndPublishesHonestFeedback() async {
        let fixture = Fixture(); let context = fixture.select("A")
        await fixture.coordinator.sendVerification(context: context)
        XCTAssertEqual(fixture.sends, ["A"]); XCTAssertFalse(fixture.coordinator.activity.sending)
        XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle)
        XCTAssertTrue(fixture.state.snapshot.verificationMessage?.contains("Bekræftelsesmail sendt") == true)
    }
    func testCurrentSendFailureKeepsAccountAndShowsFailureWithoutFalseSentStatus() async {
        let fixture = Fixture(); let context = fixture.select("A")
        fixture.send = { _, _ in throw URLError(.notConnectedToInternet) }
        await fixture.coordinator.sendVerification(context: context)
        XCTAssertEqual(fixture.state.snapshot.userID, "A"); XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle)
        XCTAssertTrue(fixture.state.snapshot.verificationMessage?.contains("kunne ikke sendes") == true)
        XCTAssertFalse(fixture.coordinator.activity.sending)
    }
    func testHeldASendKeepsActualSlotThroughBAndReportsBusyWithoutStartingBProvider() async {
        let fixture = Fixture(); let a = fixture.select("A"); let gate = Gate()
        fixture.send = { _, _ in try await gate.hold() }
        let sending = Task { await fixture.coordinator.sendVerification(context: a) }
        await gate.waitUntilHeld(); let b = fixture.select("B")
        await fixture.coordinator.sendVerification(context: b)
        XCTAssertEqual(fixture.sends, ["A"]); XCTAssertTrue(fixture.coordinator.activity.sending)
        XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle)
        let busy = fixture.state.snapshot.verificationMessage
        XCTAssertTrue(busy?.contains("tidligere anmodning") == true)
        gate.release(); await sending.value
        XCTAssertFalse(fixture.coordinator.activity.sending); XCTAssertEqual(fixture.state.snapshot.verificationMessage, busy)
        fixture.send = nil; await fixture.coordinator.sendVerification(context: b)
        XCTAssertEqual(fixture.sends, ["A", "B"])
        XCTAssertTrue(fixture.state.snapshot.verificationMessage?.contains("Bekræftelsesmail sendt") == true)
    }
    func testLateOldSendFailureCannotReplaceBFeedbackAndStillMustDrainActualSlot() async {
        let fixture = Fixture(); let a = fixture.select("A"); let gate = Gate()
        fixture.send = { _, _ in try await gate.hold() }
        let sending = Task { await fixture.coordinator.sendVerification(context: a) }
        await gate.waitUntilHeld(); let b = fixture.select("B")
        await fixture.coordinator.sendVerification(context: b); let busy = fixture.state.snapshot.verificationMessage
        gate.release(error: URLError(.notConnectedToInternet)); await sending.value
        XCTAssertEqual(fixture.state.snapshot.verificationMessage, busy); XCTAssertEqual(fixture.sends, ["A"])
        XCTAssertFalse(fixture.coordinator.activity.sending)
    }
    func testHeldSendThroughGuestAndSameUIDReturnNeverRevivesOldOperation() async {
        let fixture = Fixture(); let a = fixture.select("A"); let gate = Gate()
        fixture.send = { _, _ in try await gate.hold() }
        let sending = Task { await fixture.coordinator.sendVerification(context: a) }
        await gate.waitUntilHeld(); _ = fixture.select(nil); let newerA = fixture.select("A")
        await fixture.coordinator.sendVerification(context: newerA)
        XCTAssertEqual(fixture.sends, ["A"]); XCTAssertTrue(fixture.coordinator.activity.sending)
        gate.release(); await sending.value
        XCTAssertFalse(fixture.coordinator.activity.sending)
        XCTAssertTrue(fixture.state.snapshot.verificationMessage?.contains("tidligere anmodning") == true)
        XCTAssertFalse(fixture.state.isCurrent(a)); XCTAssertTrue(fixture.state.isCurrent(newerA))
    }
    func testHeldARefreshKeepsActualSlotThroughBAndRejectsOriginalResult() async throws {
        let fixture = Fixture(); let a = fixture.select("A"); let gate = Gate()
        fixture.refresh = { [unowned fixture] ticket, _ in try await gate.hold(); return fixture.account(ticket.userID!, verified: true) }
        let refreshing = Task { try await fixture.coordinator.refreshSession(context: a) }
        await gate.waitUntilHeld(); let b = fixture.select("B")
        try await fixture.coordinator.refreshSession(context: b)
        XCTAssertEqual(fixture.refreshes, ["A"]); XCTAssertTrue(fixture.coordinator.activity.refreshing)
        XCTAssertTrue(fixture.state.snapshot.verificationMessage?.contains("tidligere anmodning") == true)
        gate.release(); try await refreshing.value
        XCTAssertFalse(fixture.coordinator.activity.refreshing); XCTAssertEqual(fixture.state.snapshot.session, fixture.account("B"))
        fixture.refresh = nil; try await fixture.coordinator.refreshSession(context: b)
        XCTAssertEqual(fixture.refreshes, ["A", "B"]); XCTAssertTrue(fixture.state.snapshot.session!.isEmailVerified)
    }
    func testLateRefreshFailureDoesNotThrowIntoNewOwnersFormOrChangeItsFeedback() async throws {
        let fixture = Fixture(); let a = fixture.select("A"); let gate = Gate()
        fixture.refresh = { _, _ in try await gate.hold(); throw URLError(.notConnectedToInternet) }
        let refreshing = Task { try await fixture.coordinator.refreshSession(context: a) }
        await gate.waitUntilHeld(); _ = fixture.select("B")
        gate.release(); try await refreshing.value
        XCTAssertNil(fixture.state.snapshot.verificationMessage); XCTAssertFalse(fixture.coordinator.activity.refreshing)
        XCTAssertEqual(fixture.state.snapshot.userID, "B")
    }
    func testCurrentRefreshFailureRemainsObservableAndLeavesOriginalAccountUnverified() async {
        let fixture = Fixture(); let context = fixture.select("A")
        fixture.refresh = { _, _ in throw URLError(.notConnectedToInternet) }
        do { try await fixture.coordinator.refreshSession(context: context); XCTFail("Current failure must be observable") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(fixture.state.snapshot.session, fixture.account("A")); XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle)
        XCTAssertTrue(fixture.state.snapshot.verificationMessage?.contains("Kunne ikke kontrollere") == true)
        XCTAssertFalse(fixture.coordinator.activity.refreshing)
    }
    func testOriginalRefreshResponseMustMatchItsOwnUIDBeforeAcceptance() async {
        let fixture = Fixture(); let context = fixture.select("A")
        fixture.refresh = { [unowned fixture] _, _ in fixture.account("B", verified: true) }
        do { try await fixture.coordinator.refreshSession(context: context); XCTFail("Foreign provider response must fail") }
        catch { XCTAssertTrue(error is ReaderAccountVerificationCoordinator.Failure) }
        XCTAssertEqual(fixture.state.snapshot.session, fixture.account("A")); XCTAssertNotNil(fixture.state.snapshot.verificationMessage)
        XCTAssertFalse(fixture.coordinator.activity.refreshing)
    }
    func testSameOwnerVerifiedCanonicalCallbackDuringRefreshStillAllowsOriginalFinalTokenEffect() async throws {
        let fixture = Fixture(); let context = fixture.select("A"); let gate = Gate()
        fixture.refresh = { [unowned fixture] ticket, permitted in
            try await gate.hold()
            guard permitted() else { throw CancellationError() }
            fixture.tokenRefreshes.append(ticket.userID!)
            return fixture.account(ticket.userID!, verified: true)
        }
        let refreshing = Task { try await fixture.coordinator.refreshSession(context: context) }
        await gate.waitUntilHeld()
        _ = fixture.state.adopt(fixture.account("A", verified: true))
        XCTAssertTrue(fixture.coordinator.activity.refreshing); XCTAssertEqual(fixture.state.snapshot.verificationStatus, .refreshing)
        gate.release(); try await refreshing.value
        XCTAssertEqual(fixture.tokenRefreshes, ["A"]); XCTAssertTrue(fixture.state.snapshot.session!.isEmailVerified)
        XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle); XCTAssertFalse(fixture.coordinator.activity.refreshing)
    }
    func testNewSameUIDEpochAfterGuestPreventsOriginalRefreshFinalTokenEffect() async throws {
        let fixture = Fixture(); let context = fixture.select("A"); let gate = Gate()
        fixture.refresh = { [unowned fixture] ticket, permitted in
            try await gate.hold()
            guard permitted() else { throw CancellationError() }
            fixture.tokenRefreshes.append(ticket.userID!)
            return fixture.account(ticket.userID!, verified: true)
        }
        let refreshing = Task { try await fixture.coordinator.refreshSession(context: context) }
        await gate.waitUntilHeld(); _ = fixture.select(nil); _ = fixture.select("A", verified: true)
        gate.release(); try await refreshing.value
        XCTAssertTrue(fixture.tokenRefreshes.isEmpty); XCTAssertFalse(fixture.coordinator.activity.refreshing)
        XCTAssertNil(fixture.state.snapshot.verificationMessage)
    }
    func testIdentityGetterReentryCannotStartVerificationForLaterOwner() async {
        let fixture = Fixture(); let original = fixture.select("A"); var once = true
        fixture.onIdentity = { [unowned fixture] in if once { once = false; _ = fixture.select("B") } }
        await fixture.coordinator.sendVerification(context: original)
        XCTAssertTrue(fixture.sends.isEmpty); XCTAssertEqual(fixture.state.snapshot.userID, "B")
        XCTAssertFalse(fixture.coordinator.activity.sending)
    }
    func testVerificationWillChangeOwnerReentryPreventsProviderEntryAndOldSendingState() async {
        let fixture = Fixture(); let context = fixture.select("A"); var once = true
        let subscription = fixture.state.objectWillChange.sink {
            if once { once = false; _ = fixture.select("B") }
        }
        await fixture.coordinator.sendVerification(context: context)
        XCTAssertTrue(fixture.sends.isEmpty); XCTAssertEqual(fixture.state.snapshot.userID, "B")
        XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle); XCTAssertFalse(fixture.coordinator.activity.sending)
        withExtendedLifetime(subscription) {}
    }
    func testIdentityGetterReentryDuringBeginValidationCancelsOwnProposalBeforeProvider() async {
        let fixture = Fixture(); let context = fixture.select("A")
        fixture.onIdentity = { [unowned fixture] in if fixture.identityReads == 2 { _ = fixture.select(nil); _ = fixture.select("A") } }
        await fixture.coordinator.sendVerification(context: context)
        XCTAssertTrue(fixture.sends.isEmpty); XCTAssertFalse(fixture.state.isCurrent(context))
        XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle)
    }
    func testFinalRefreshPublicationWillChangeOwnerReentryCannotPublishOrThrowOldFeedback() async throws {
        let fixture = Fixture(); let context = fixture.select("A"); let gate = Gate()
        fixture.refresh = { [unowned fixture] ticket, _ in try await gate.hold(); return fixture.account(ticket.userID!, verified: true) }
        let refreshing = Task { try await fixture.coordinator.refreshSession(context: context) }
        await gate.waitUntilHeld(); var once = true
        let subscription = fixture.state.objectWillChange.sink {
            if once { once = false; _ = fixture.select("B") }
        }
        gate.release(); try await refreshing.value
        XCTAssertEqual(fixture.state.snapshot.session, fixture.account("B")); XCTAssertNil(fixture.state.snapshot.verificationMessage)
        XCTAssertFalse(fixture.coordinator.activity.refreshing)
        withExtendedLifetime(subscription) {}
    }
    func testIdentityReadAfterActualSendReturnCannotPublishFeedbackAfterNestedNewEpoch() async {
        let fixture = Fixture(); let context = fixture.select("A")
        fixture.send = { [unowned fixture] _, _ in
            var once = true
            fixture.onIdentity = { [unowned fixture] in
                if once { once = false; _ = fixture.select(nil); _ = fixture.select("A") }
            }
        }
        await fixture.coordinator.sendVerification(context: context)
        XCTAssertEqual(fixture.sends, ["A"]); XCTAssertFalse(fixture.state.isCurrent(context))
        XCTAssertNil(fixture.state.snapshot.verificationMessage); XCTAssertEqual(fixture.state.snapshot.verificationStatus, .idle)
        XCTAssertFalse(fixture.coordinator.activity.sending)
    }
    func testBusyFeedbackWillChangeReentryCannotAttachOldRequestMessageToC() async {
        let fixture = Fixture(); let original = fixture.select("A"); let gate = Gate()
        fixture.send = { _, _ in try await gate.hold() }
        let sending = Task { await fixture.coordinator.sendVerification(context: original) }
        await gate.waitUntilHeld(); let b = fixture.select("B"); var once = true
        let subscription = fixture.state.objectWillChange.sink {
            if once { once = false; _ = fixture.select("C") }
        }
        await fixture.coordinator.sendVerification(context: b)
        XCTAssertEqual(fixture.sends, ["A"]); XCTAssertEqual(fixture.state.snapshot.userID, "C")
        XCTAssertNil(fixture.state.snapshot.verificationMessage); XCTAssertTrue(fixture.coordinator.activity.sending)
        gate.release(); await sending.value
        XCTAssertFalse(fixture.coordinator.activity.sending); XCTAssertNil(fixture.state.snapshot.verificationMessage)
        withExtendedLifetime(subscription) {}
    }
}
