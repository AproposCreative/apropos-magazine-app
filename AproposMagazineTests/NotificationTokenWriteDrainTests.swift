import FirebaseCore
import UserNotifications
import XCTest
@testable import Apropos

/// Actual notification entry points and account-write adapter. Only physical
/// SDK references/callbacks and unrelated notification effects are local.
@MainActor
final class NotificationTokenWriteDrainTests: XCTestCase {
    private typealias Service = NotificationService
    private typealias Guard = Service.OperationGuard
    private typealias Completion = ReaderWriterDrainRuntime.Completion
    private enum Failure: Error { case unavailable }

    @MainActor private final class Fixture {
        struct Write {
            let token: String, uid: String
            let current: Guard
            let completion: Completion
        }
        let canonical = CanonicalSessionState()
        let startup: ReaderSDKStartupState
        var uid: String? = "A"
        var allowed = true
        var identityReads = 0, preparations = 0, accountEntries = 0, completed = 0
        var persistedTokens: [String] = [], backendOwners: [Service.TokenOwner] = []
        var topics: [String] = [], diagnostics: [Service.Diagnostic] = []
        var writes: [Write] = [], drains: [Completion] = []
        var tasks: [Task<Void, Never>] = []
        var deadlines: [@MainActor () -> Void] = []
        var identityHook: (() -> Void)?, referenceHook: (() -> Void)?
        private var waiters: [(String, Int, XCTestExpectation)] = []
        lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [weak self] in
            guard let self else { return nil }
            self.identityReads += 1; self.identityHook?()
            return self.uid
        }, schedule: { [weak self] action in
            guard let self else { return {} }
            self.deadlines.append(action); self.notify("deadline", self.deadlines.count)
            return {}
        }, makeDrain: { [weak self] in
            guard let self else { throw Failure.unavailable }
            return .init(wait: { [weak self] returned in
                guard let self else { returned(Failure.unavailable); return }
                self.drains.append(returned); self.notify("drain", self.drains.count)
            })
        })
        lazy var service = Service(effects: .init(
            resolveOwner: { [weak self] in self?.uid.map(Service.TokenOwner.account) ?? .guest },
            authorizationStatus: { current in current() ? .authorized : .notDetermined },
            requestAuthorization: { _ in false }, register: { _ in }, fetchToken: { _ in nil },
            setTopic: { [weak self] topic, _, current, completion in
                guard current() else { completion(CancellationError()); return }
                self?.topics.append(topic); self?.notify("topic", self?.topics.count ?? 0); completion(nil)
            }, saveAccountToken: { [weak self] token, uid, current, completion in
                guard let self else { return }
                self.accountEntries += 1
                let task = Service.saveAccountToken(token, userID: uid, stillCurrent: current,
                    runtime: self.runtime, write: { [weak self] token, uid, admitted, returned in
                        guard let self else { returned(Failure.unavailable); return }
                        self.preparations += 1; self.referenceHook?()
                        guard admitted() else { returned(CancellationError()); return }
                        self.writes.append(.init(token: token, uid: uid, current: admitted, completion: returned))
                        self.notify("write", self.writes.count)
                    }, completion: { [weak self] error in
                        self?.completed += 1
                        completion(error)
                    })
                if let task { self.tasks.append(task) }
            }, sendBackendToken: { [weak self] _, owner, current, completion in
                guard current() else { completion(CancellationError()); return }
                self?.backendOwners.append(owner); completion(nil)
            }, loadSettings: { _ in (.init(), []) }, persistSettings: { _, _, _ in },
            loadCategoryIDs: { _ in [] }, persistCategoryIDs: { _, _ in }, loadToken: { _ in nil },
            persistToken: { [weak self] token, current in if current() { self?.persistedTokens.append(token) } },
            diagnostic: { [weak self] diagnostic, current in if current() { self?.diagnostics.append(diagnostic) } }
        ))
        init(closed: Bool = false) {
            startup = closed ? ReaderSDKStartupState() : .application
            _ = canonical.adopt(Self.session("A"))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "local@example.invalid", isEmailVerified: true)
        }
        func select(_ value: String?) { uid = value; _ = canonical.adopt(value.map(Self.session)) }
        func permission() -> Guard {
            let original = startup.captureReaderWork(identity: canonical, actualUserID: { [weak self] in self?.uid })
            return { [weak self] in self?.allowed == true && original?() == true }
        }
        func update(_ token: String = "token", current: Guard? = nil) {
            service.updateFCMTokenOnServer(token, expectedUserID: "A", stillCurrent: current ?? permission())
        }
        func finishTasks() async { for task in tasks { await task.value } }
        private func notify(_ kind: String, _ count: Int) {
            let ready = waiters.filter { $0.0 == kind && $0.1 <= count }
            waiters.removeAll { $0.0 == kind && $0.1 <= count }; ready.forEach { $0.2.fulfill() }
        }
        func wait(_ kind: String, count: Int = 1) async {
            let observed = kind == "write" ? writes.count : kind == "drain" ? drains.count : kind == "topic" ? topics.count : deadlines.count
            if observed >= count { return }
            let expected = XCTestExpectation(description: "Physical notification \(kind) \(count)")
            waiters.append((kind, count, expected))
            let result = await XCTWaiter.fulfillment(of: [expected], timeout: 3)
            XCTAssertEqual(result, .completed)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testConstructionAndClosedStartupDoNotEnterAccountWriter() {
        let f = Fixture(closed: true); _ = f.service; _ = f.runtime
        XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.preparations, 0)
        f.update()
        XCTAssertEqual(f.accountEntries, 0); XCTAssertTrue(f.tasks.isEmpty)
        XCTAssertTrue(f.backendOwners.isEmpty); XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testStoppedRuntimeBlocksFirstReferenceWhileStartupAndBackendRemainValid() throws {
        let f = Fixture(), original = f.permission()
        _ = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        XCTAssertTrue(original())
        f.update(current: original)
        XCTAssertEqual(f.accountEntries, 1); XCTAssertEqual(f.preparations, 0)
        XCTAssertTrue(f.tasks.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        // This fixture isolates the SDK adapter and stubs backend delivery.
        // The real HTTP adapter has its own shared-drain integration tests.
        XCTAssertEqual(f.backendOwners, [.account("A")])
    }

    func testStopBetweenSynchronousCaptureAndTaskPreventsPhysicalWrite() async throws {
        let f = Fixture(); f.update(current: { true })
        XCTAssertEqual(f.tasks.count, 1); XCTAssertEqual(f.preparations, 0)
        _ = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        await f.finishTasks()
        XCTAssertEqual(f.preparations, 0); XCTAssertTrue(f.writes.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testSameUIDRoundTripBeforeTaskCannotBorrowNewGenerationWithWeakCallerGuard() async {
        let f = Fixture(); f.update(current: { true })
        f.select("B"); f.select("A")
        await f.finishTasks()
        XCTAssertEqual(f.preparations, 0); XCTAssertEqual(f.completed, 0)
        XCTAssertTrue(f.diagnostics.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testPhysicalTokenWriteRetainsOriginalPayloadAndSlotUntilCallback() async {
        let f = Fixture(); f.update("original-token")
        await f.wait("write")
        XCTAssertEqual(f.writes[0].uid, "A"); XCTAssertEqual(f.writes[0].token, "original-token")
        XCTAssertEqual(f.completed, 0); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.writes[0].completion(nil); await f.finishTasks()
        XCTAssertEqual(f.completed, 1); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testReferenceHookAccountRoundTripIsRejectedByFinalSDKGuard() async {
        let f = Fixture()
        f.referenceHook = { f.referenceHook = nil; f.select("B"); f.select("A") }
        f.update(current: { true }); await f.finishTasks()
        XCTAssertEqual(f.preparations, 1); XCTAssertTrue(f.writes.isEmpty)
        XCTAssertEqual(f.completed, 0); XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testIdentityHookStopBeforeReferenceCannotAdmitTokenWrite() async {
        let f = Fixture()
        f.identityHook = {
            f.identityHook = nil
            XCTAssertNotNil(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        }
        f.update(current: { true }); await f.finishTasks()
        XCTAssertEqual(f.preparations, 0); XCTAssertTrue(f.writes.isEmpty)
    }

    func testAccountRoundTripDuringPhysicalWriteSuppressesLateErrorAndKeepsSlot() async {
        let f = Fixture(); f.update(current: { true }); await f.wait("write")
        f.select("B"); f.select("A")
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.completed, 0)
        f.writes[0].completion(Failure.unavailable); await f.finishTasks()
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.completed, 0)
        XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testActualProviderMismatchWithoutCanonicalCallbackSuppressesErrorFeedback() async {
        let f = Fixture(); f.update(current: { true }); await f.wait("write")
        f.uid = "B"
        f.writes[0].completion(Failure.unavailable); await f.finishTasks()
        f.uid = "A"
        XCTAssertEqual(f.completed, 0); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testCancellingAccountWriteWaitsForPhysicalCallbackWithoutFeedback() async {
        let f = Fixture(); f.update(); await f.wait("write")
        let task = f.tasks[0]; task.cancel()
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.completed, 0)
        f.writes[0].completion(nil); await task.value
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.completed, 0)
        XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testDrainTimeoutRetainsPendingTokenWriteAndDoesNotRejectHistoricalSuccess() async throws {
        let f = Fixture(); f.update(); await f.wait("write")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { () -> Bool in
            do { _ = try await f.runtime.drain(stop); return true } catch { return false }
        }
        await f.wait("deadline"); f.deadlines[0]()
        let result = await drain.value; XCTAssertFalse(result)
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertTrue(f.drains.isEmpty)
        f.writes[0].completion(nil); await f.finishTasks()
        XCTAssertEqual(f.completed, 1); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
        f.update("later")
        XCTAssertEqual(f.writes.count, 1); XCTAssertEqual(f.preparations, 1)
    }

    func testDrainWaitStartsOnlyAfterPhysicalTokenCallbackAndKeepsItsOwnCancelledSlot() async throws {
        let f = Fixture(); f.update(); await f.wait("write")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { () -> Bool in
            do { _ = try await f.runtime.drain(stop); return true } catch { return false }
        }
        await f.wait("deadline"); XCTAssertTrue(f.drains.isEmpty)
        f.writes[0].completion(nil); await f.finishTasks(); await f.wait("drain")
        XCTAssertEqual(f.completed, 1); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        drain.cancel(); let result = await drain.value; XCTAssertFalse(result)
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        // The physical SDK callback, rather than cancellation, clears the slot.
        f.drains[0](nil)
        let callbackReturned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in f.runtime.isPhysicallyIdle }, object: nil)
        let waited = await XCTWaiter.fulfillment(of: [callbackReturned], timeout: 3)
        XCTAssertEqual(waited, .completed)
    }

    func testCurrentSDKFailureDiagnosesOnceDespiteDuplicateCallback() async {
        let f = Fixture(); f.update(); await f.wait("write")
        f.writes[0].completion(Failure.unavailable)
        f.writes[0].completion(nil)
        await f.finishTasks()
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.diagnostics, [.tokenSaveFailed])
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testNewTokenRevisionSuppressesOldAccountWriteFeedback() async {
        let f = Fixture(), original = f.permission()
        f.service.acceptRegistrationToken("same", owner: .account("A"), registerAccountToken: true, stillCurrent: original)
        await f.wait("write")
        f.service.acceptRegistrationToken("same", owner: .account("A"), registerAccountToken: true, stillCurrent: original)
        await f.wait("write", count: 2)
        f.writes[0].completion(Failure.unavailable); await f.tasks[0].value
        XCTAssertEqual(f.completed, 0)
        XCTAssertFalse(f.diagnostics.contains(.tokenSaveFailed), "Den gamle skrivefejl må ikke diagnosticeres for den nye tokenrevision")
        // Accepting a token also performs the existing topic synchronization.
        // Its successful callbacks legitimately emit topicSucceeded diagnostics.
        XCTAssertTrue(f.diagnostics.allSatisfy { diagnostic in
            if case .topicSucceeded = diagnostic { return true }
            return false
        })
        f.writes[1].completion(nil); await f.tasks[1].value
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.service.fcmToken, "same")
        XCTAssertFalse(f.diagnostics.contains(.tokenSaveFailed))
    }

    func testGuestKeepsLocalTokenAndTopicsWithoutAccountWriteOrBackendRegistration() async {
        let f = Fixture(); f.select(nil)
        f.service.acceptRegistrationToken("guest-token", owner: .guest, registerAccountToken: true, stillCurrent: f.permission())
        await f.wait("topic")
        XCTAssertEqual(f.service.fcmToken, "guest-token"); XCTAssertEqual(f.persistedTokens, ["guest-token"])
        XCTAssertFalse(f.topics.isEmpty); XCTAssertEqual(f.accountEntries, 0)
        XCTAssertEqual(f.preparations, 0); XCTAssertTrue(f.backendOwners.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }
}
