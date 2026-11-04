import FirebaseCore
import Foundation
import UserNotifications
import XCTest
@testable import Apropos

/// Actual notification service and backend request/adapter, with a real local
/// writer runtime. Only endpoint/date and suspended HTTP tasks are injected.
/// No URLSession, Firebase app, APNs, defaults or production endpoint is used.
@MainActor
final class NotificationBackendTokenDrainTests: XCTestCase {
    private typealias Service = NotificationService
    private typealias Guard = Service.OperationGuard
    private typealias Callback = ReaderWriterDrainRuntime.Completion
    private enum Failure: Error { case offline }

    @MainActor private final class Fixture {
        struct Network {
            let request: URLRequest
            let current: Guard
            let callback: Callback
            var resumes = 0
            var cancels = 0
            var delivered = false
        }
        let canonical = CanonicalSessionState()
        let startup: ReaderSDKStartupState
        var uid: String? = "A"
        var allowed = true
        var endpointURL = URL(string: "https://backend.example.invalid/fcm")
        let date = Date(timeIntervalSince1970: 1_700_000_123.5)
        var endpointReads = 0, dateReads = 0, identityReads = 0, drainFactories = 0
        var accountEntries = 0, backendEntries = 0, completed = 0
        var completionErrors: [Bool] = []
        var networks: [Network] = []
        var tasks: [Task<Void, Never>] = []
        var drains: [Callback] = []
        var deadlines: [@MainActor () -> Void] = []
        var diagnostics: [Service.Diagnostic] = []
        var endpointHook: (@MainActor () -> Void)?
        var makeTaskHook: (@MainActor () -> Void)?
        var resumeHook: (@MainActor (Int) -> Void)?
        private var waiters: [(String, Int, XCTestExpectation)] = []

        lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [weak self] in
            guard let self else { return nil }
            self.identityReads += 1; return self.uid
        }, schedule: { [weak self] action in
            self?.deadlines.append(action); self?.notify("deadline")
            return {}
        }, makeDrain: { [weak self] in
            guard let self else { throw Failure.offline }
            self.drainFactories += 1
            return .init(wait: { [weak self] callback in
                self?.drains.append(callback); self?.notify("drain")
            })
        })

        var transport: Service.BackendTokenTransport {
            .init(endpoint: { [weak self] in
                guard let self else { return nil }
                self.endpointReads += 1; self.endpointHook?(); return self.endpointURL
            }, now: { [weak self] in
                guard let self else { return Date(timeIntervalSince1970: 0) }
                self.dateReads += 1; return self.date
            }, makeTask: { [weak self] request, current, callback in
                guard let self else { throw Failure.offline }
                guard current() else { throw CancellationError() }
                let index = self.networks.count
                self.networks.append(.init(request: request, current: current, callback: callback))
                self.makeTaskHook?()
                self.notify("make")
                return .init(resume: { [weak self] in
                    guard let self else { return }
                    self.networks[index].resumes += 1
                    self.resumeHook?(index)
                    self.notify("resume")
                }, cancel: { [weak self] in
                    guard let self else { return }
                    self.networks[index].cancels += 1; self.notify("cancel")
                })
            })
        }

        lazy var service = Service(effects: .init(
            resolveOwner: { [weak self] in self?.uid.map(Service.TokenOwner.account) ?? .guest },
            authorizationStatus: { _ in .denied }, requestAuthorization: { _ in false },
            register: { _ in }, fetchToken: { _ in nil }, setTopic: { _, _, _, completion in completion(nil) },
            saveAccountToken: { [weak self] _, _, current, completion in
                guard current() else { completion(CancellationError()); return }
                self?.accountEntries += 1; completion(nil)
            }, sendBackendToken: { [weak self] token, owner, current, completion in
                guard let self else { return }
                self.backendEntries += 1
                _ = self.send(token, owner: owner, current: current, after: completion)
            }, loadSettings: { _ in (.init(), []) }, persistSettings: { _, _, _ in },
            loadCategoryIDs: { _ in [] }, persistCategoryIDs: { _, _ in }, loadToken: { _ in nil },
            persistToken: { _, _ in }, diagnostic: { [weak self] diagnostic, current in
                if current() { self?.diagnostics.append(diagnostic) }
            }
        ))

        init(closed: Bool = false) {
            startup = closed ? ReaderSDKStartupState() : .application
            _ = canonical.adopt(Self.session("A"))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "local@example.invalid", isEmailVerified: true)
        }
        func select(_ next: String?) { uid = next; _ = canonical.adopt(next.map(Self.session)) }
        func permission() -> Guard {
            let original = startup.captureReaderWork(identity: canonical, actualUserID: { [weak self] in self?.uid })
            return { [weak self] in self?.allowed == true && original?() == true }
        }
        @discardableResult
        func send(_ token: String = "token", owner: Service.TokenOwner = .account("A"), current: Guard? = nil,
                  after: Service.Completion? = nil) -> Task<Void, Never>? {
            let accountRuntime: ReaderWriterDrainRuntime?
            switch owner { case .guest: accountRuntime = nil; case .account: accountRuntime = runtime }
            let task = Service.sendBackendToken(token, owner: owner, stillCurrent: current ?? permission(),
                runtime: accountRuntime, transport: transport, completion: { [weak self] error in
                    guard let self else { return }
                    self.completed += 1; self.completionErrors.append(error != nil)
                    after?(error); self.notify("complete")
                })
            if let task { tasks.append(task) }
            return task
        }
        func update(_ token: String = "token", current: Guard? = nil) {
            service.updateFCMTokenOnServer(token, expectedUserID: "A", stillCurrent: current ?? permission())
        }
        func deliver(_ index: Int, error: Error? = nil) {
            guard networks.indices.contains(index) else { XCTFail("Missing physical task"); return }
            networks[index].delivered = true
            networks[index].callback(error)
        }
        func finishTasks() async { for task in tasks { await task.value } }
        func count(_ kind: String) -> Int {
            switch kind {
            case "make": return networks.count
            case "resume": return networks.reduce(0) { $0 + $1.resumes }
            case "cancel": return networks.reduce(0) { $0 + $1.cancels }
            case "complete": return completed
            case "drain": return drains.count
            default: return deadlines.count
            }
        }
        private func notify(_ kind: String) {
            let ready = waiters.filter { $0.0 == kind && $0.1 <= count(kind) }
            waiters.removeAll { $0.0 == kind && $0.1 <= count(kind) }; ready.forEach { $0.2.fulfill() }
        }
        func wait(_ kind: String, count: Int = 1) async {
            if self.count(kind) >= count { return }
            let ready = XCTestExpectation(description: "Backend physical \(kind) \(count)")
            waiters.append((kind, count, ready))
            let result = await XCTWaiter.fulfillment(of: [ready], timeout: 3)
            XCTAssertEqual(result, .completed)
        }
        func payload(_ index: Int = 0) throws -> [String: Any] {
            let data = try XCTUnwrap(networks[index].request.httpBody)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        func close() {
            endpointHook = nil; makeTaskHook = nil; resumeHook = nil
            tasks.forEach { $0.cancel() }
            for index in networks.indices where !networks[index].delivered { deliver(index, error: Failure.offline) }
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testConstructionAndClosedStartupReachNoEndpointOrTaskFactory() {
        let f = Fixture(closed: true); defer { f.close() }; _ = f.service; _ = f.runtime
        XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.endpointReads, 0)
        f.update()
        XCTAssertEqual(f.backendEntries, 0); XCTAssertEqual(f.accountEntries, 0)
        XCTAssertEqual(f.endpointReads, 0); XCTAssertEqual(f.dateReads, 0)
        XCTAssertTrue(f.tasks.isEmpty); XCTAssertTrue(f.networks.isEmpty)
        XCTAssertNil(Service.sendBackendToken("token", owner: .account("A"), stillCurrent: { true },
            runtime: nil, transport: f.transport, completion: { _ in XCTFail("No account-runtime fallback") }))
        XCTAssertEqual(f.endpointReads, 0); XCTAssertEqual(f.identityReads, 0)
    }

    func testNilEndpointIsSynchronousNoOpWithoutClockTaskOrPhysicalSlot() {
        let f = Fixture(); defer { f.close() }; f.endpointURL = nil
        XCTAssertNil(f.send())
        XCTAssertEqual(f.endpointReads, 1); XCTAssertEqual(f.dateReads, 0)
        XCTAssertTrue(f.tasks.isEmpty); XCTAssertTrue(f.networks.isEmpty)
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.completionErrors, [false])
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.drainFactories, 0)
    }

    func testActualServiceKeepsOriginalPayloadHeadersAndTimeoutUntilHTTPCallback() async throws {
        let f = Fixture(); defer { f.close() }; f.update("token/æ")
        await f.wait("resume")
        XCTAssertEqual(f.networks.count, 1); XCTAssertEqual(f.completed, 0)
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        let request = f.networks[0].request
        XCTAssertEqual(request.url, f.endpointURL); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "AproposMagazine-iOS/1.0")
        let body = try f.payload()
        XCTAssertEqual(Set(body.keys), Set(["fcmToken", "userId", "platform", "timestamp"]))
        XCTAssertEqual(body["fcmToken"] as? String, "token/æ")
        XCTAssertEqual(body["userId"] as? String, "A"); XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["timestamp"] as? Double, f.date.timeIntervalSince1970)
        f.deliver(0); await f.finishTasks()
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.completionErrors, [false])
        XCTAssertTrue(f.diagnostics.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testStoppedRuntimeBlocksBackendWhileStartupPermissionRemainsValid() throws {
        let f = Fixture(); defer { f.close() }; let original = f.permission()
        _ = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        XCTAssertTrue(original())
        f.update(current: original)
        XCTAssertEqual(f.backendEntries, 1); XCTAssertEqual(f.endpointReads, 0)
        XCTAssertTrue(f.tasks.isEmpty); XCTAssertTrue(f.networks.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testStopBetweenCaptureAndTaskPreventsHTTPTaskCreation() async throws {
        let f = Fixture(); defer { f.close() }
        let task = try XCTUnwrap(f.send(current: { true }))
        XCTAssertTrue(f.networks.isEmpty)
        _ = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        await task.value
        XCTAssertTrue(f.networks.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testWeakCallerGuardCannotAdoptSameUIDAfterABABeforeTask() async throws {
        let f = Fixture(); defer { f.close() }
        let task = try XCTUnwrap(f.send(current: { true }))
        f.select("B"); f.select("A")
        await task.value
        XCTAssertTrue(f.networks.isEmpty); XCTAssertEqual(f.completed, 0)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testEndpointHookAccountRoundTripCannotRetagCapturedRequest() async {
        let f = Fixture(); defer { f.close() }
        f.endpointHook = { f.endpointHook = nil; f.select("B"); f.select("A") }
        _ = f.send(current: { true })
        await f.finishTasks()
        XCTAssertEqual(f.endpointReads, 1); XCTAssertEqual(f.dateReads, 0)
        XCTAssertTrue(f.networks.isEmpty); XCTAssertEqual(f.completed, 0)
    }

    func testStopDuringSuspendedTaskCreationCancelsWithoutResume() async {
        let f = Fixture(); defer { f.close() }
        f.makeTaskHook = {
            f.makeTaskHook = nil
            XCTAssertNotNil(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        }
        f.update(); await f.finishTasks()
        XCTAssertEqual(f.networks.count, 1)
        XCTAssertEqual(f.networks[0].resumes, 0); XCTAssertEqual(f.networks[0].cancels, 1)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testAccountRoundTripDuringTaskCreationCancelsWithoutResumeOrFeedback() async {
        let f = Fixture(); defer { f.close() }
        f.makeTaskHook = { f.makeTaskHook = nil; f.select("B"); f.select("A") }
        _ = f.send(current: { true }); await f.finishTasks()
        XCTAssertEqual(f.networks.count, 1)
        XCTAssertEqual(f.networks[0].resumes, 0); XCTAssertEqual(f.networks[0].cancels, 1)
        XCTAssertEqual(f.completed, 0); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testStartedHTTPWriteCancellationKeepsSlotUntilPhysicalCallback() async throws {
        let f = Fixture(); defer { f.close() }
        let task = try XCTUnwrap(f.send())
        await f.wait("resume"); task.cancel()
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.completed, 0)
        f.deliver(0); await task.value
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.completed, 0)
    }

    func testDrainTimeoutKeepsStartedHTTPWriteAndHistoricalCompletion() async throws {
        let f = Fixture(); defer { f.close() }; _ = f.send()
        await f.wait("resume")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("deadline"); f.deadlines[0]()
        do { _ = try await drain.value; XCTFail("Expected deadline") }
        catch { XCTAssertEqual(error as? ReaderWriterDrainCoordinator.Failure, .timedOut) }
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertTrue(f.drains.isEmpty)
        f.deliver(0); await f.finishTasks()
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.completionErrors, [false])
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.drainFactories, 0)
        XCTAssertNil(f.send("next")); XCTAssertEqual(f.networks.count, 1)
    }

    func testDrainStartsOnlyAfterBackendCallbackReturns() async throws {
        let f = Fixture(); defer { f.close() }; _ = f.send()
        await f.wait("resume")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("deadline"); XCTAssertTrue(f.drains.isEmpty)
        f.deliver(0); await f.finishTasks(); await f.wait("drain")
        XCTAssertEqual(f.completed, 1); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.drains[0](nil)
        let receipt = try await drain.value
        XCTAssertTrue(f.runtime.isCurrent(receipt)); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testLateHTTPFailureAfterAccountABAHasNoFeedbackAndKeepsSlotUntilReturn() async {
        let f = Fixture(); defer { f.close() }; f.update(current: { true })
        await f.wait("resume")
        f.select("B"); f.select("A")
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.deliver(0, error: Failure.offline); await f.finishTasks()
        XCTAssertEqual(f.completed, 0); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testDuplicatePhysicalCallbackDeliversOneCurrentFailure() async {
        let f = Fixture(); defer { f.close() }; f.update()
        await f.wait("resume")
        f.deliver(0, error: Failure.offline); f.deliver(0)
        await f.finishTasks()
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.completionErrors, [true])
        XCTAssertEqual(f.diagnostics, [.tokenSendFailed]); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testSynchronousResumeCallbackStillCompletesExactlyOnce() async {
        let f = Fixture(); defer { f.close() }
        f.resumeHook = { index in f.deliver(index); f.deliver(index, error: Failure.offline) }
        f.update(); await f.finishTasks()
        XCTAssertEqual(f.networks.count, 1); XCTAssertEqual(f.networks[0].resumes, 1)
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.completionErrors, [false])
        XCTAssertTrue(f.diagnostics.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testPrematureSuccessDuringTaskCreationCancelsWithoutResumingOrClaimingSuccess() async {
        let f = Fixture(); defer { f.close() }
        f.makeTaskHook = { f.makeTaskHook = nil; f.deliver(0) }
        f.update(); await f.finishTasks()
        XCTAssertEqual(f.networks.count, 1)
        XCTAssertEqual(f.networks[0].resumes, 0); XCTAssertEqual(f.networks[0].cancels, 1)
        XCTAssertEqual(f.completed, 1); XCTAssertEqual(f.completionErrors, [true])
        XCTAssertEqual(f.diagnostics, [.tokenSendFailed]); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testNewTokenRevisionRejectsOldHTTPFeedbackEvenWhenTokenTextMatches() async {
        let f = Fixture(); defer { f.close() }; let original = f.permission()
        f.service.acceptRegistrationToken("same", owner: .account("A"), registerAccountToken: true, stillCurrent: original)
        await f.wait("resume")
        f.service.acceptRegistrationToken("same", owner: .account("A"), registerAccountToken: true, stillCurrent: original)
        await f.wait("resume", count: 2)
        f.deliver(0, error: Failure.offline); await f.tasks[0].value
        XCTAssertEqual(f.completed, 0); XCTAssertFalse(f.diagnostics.contains(.tokenSendFailed))
        XCTAssertEqual(f.service.fcmToken, "same")
        f.deliver(1); await f.tasks[1].value
        XCTAssertEqual(f.completed, 1); XCTAssertFalse(f.diagnostics.contains(.tokenSendFailed))
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testGuestRequestStaysAnonymousWithoutAccountAdmission() async throws {
        let f = Fixture(); defer { f.close() }; f.select(nil)
        f.service.updateFCMTokenOnServer("guest-token", stillCurrent: f.permission())
        await f.wait("resume")
        XCTAssertEqual(f.accountEntries, 0); XCTAssertEqual(f.identityReads, 0)
        XCTAssertTrue(f.runtime.isPhysicallyIdle, "Anonymous HTTP does not borrow an account write slot")
        let body = try f.payload()
        XCTAssertEqual(body["userId"] as? String, "anonymous")
        XCTAssertEqual(body["fcmToken"] as? String, "guest-token")
        f.select("B")
        f.deliver(0, error: Failure.offline); await f.finishTasks()
        XCTAssertEqual(f.completed, 0); XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testProviderUIDMismatchAtCompletionCannotPublishAccountError() async {
        let f = Fixture(); defer { f.close() }; f.update(current: { true })
        await f.wait("resume"); f.uid = "B"
        f.deliver(0, error: Failure.offline); await f.finishTasks()
        f.uid = "A"
        XCTAssertEqual(f.completed, 0); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }
}
