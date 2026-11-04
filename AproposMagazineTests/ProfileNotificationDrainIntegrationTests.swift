import Combine
import FirebaseCore
import UserNotifications
import XCTest
@testable import Apropos

/// Actual profile coordinator -> notification service -> both token adapters,
/// sharing one writer runtime. Only physical callbacks and reads are local.
@MainActor
final class ProfileNotificationDrainIntegrationTests: XCTestCase {
    private typealias Runtime = ReaderWriterDrainRuntime
    private typealias Service = NotificationService
    private enum Failure: Error { case unavailable }

    @MainActor private final class Fixture {
        struct PhysicalWrite {
            let current: Runtime.Guard
            var completion: Runtime.Completion?
        }
        let canonical = CanonicalSessionState()
        let state = UserProfileState()
        let events = PassthroughSubject<Void, Never>()
        var uid: String? = "A"
        var merges: [PhysicalWrite] = [], sdkWrites: [PhysicalWrite] = [], httpWrites: [PhysicalWrite] = []
        var requests: [URLRequest] = [], sdkPayloads: [(String, String)] = []
        var profileOutcomes: [Bool] = []
        var fcmCalls = 0, sdkEntries = 0, httpEntries = 0, sdkFeedback = 0, httpFeedback = 0
        var diagnostics: [Service.Diagnostic] = []
        var tokenTasks: [Task<Void, Never>] = []
        var deadlines: [@MainActor () -> Void] = []
        var drains: [Runtime.Completion?] = []
        private var observation: AnyCancellable?

        lazy var runtime = Runtime(canonical: canonical, actualUID: { [weak self] in self?.uid },
            schedule: { [weak self] action in
                self?.deadlines.append(action); self?.events.send(); return {}
            }, makeDrain: { [weak self] in
                guard let self else { throw CancellationError() }
                return .init(wait: { [weak self] completion in
                    self?.drains.append(completion); self?.events.send()
                })
            })

        lazy var manager = UserManager(state: state, effects: .init(
            capturePermission: { [weak self] in
                guard let self else { return nil }
                return ReaderSDKStartupState.application.captureReaderWork(identity: self.canonical,
                    actualUserID: { [weak self] in self?.uid })
            }, identity: { [weak self] in
                .init(actualUID: self?.uid, canonicalUID: self?.canonical.snapshot.userID)
            }, read: { seed, _, _, current in
                guard current() else { throw CancellationError() }
                return .init(profile: seed, isFromCache: false)
            }, write: { _, _, _ in
                XCTFail("Complete profile injection must use the real writer adapter")
                throw Failure.unavailable
            }, subscribe: { _, _ in }, unsubscribe: { _, _ in }, updateFCM: { [weak self] uid, current in
                guard let self, current() else { return }
                self.fcmCalls += 1
                self.notifications.updateFCMTokenOnServer(self.notifications.fcmToken,
                    expectedUserID: uid, stillCurrent: current)
                self.events.send()
            }), currentProfileSeed: { [weak self] in self?.uid.map { Self.profile($0) } },
            profileWriteEffects: .init(performWrite: { [weak self] uid, current, start in
                guard let self else { throw CancellationError() }
                do {
                    try await self.runtime.performWrite(expectedUserID: uid, stillCurrent: current, start: start)
                    self.profileOutcomes.append(true); self.events.send()
                } catch {
                    self.profileOutcomes.append(false); self.events.send(); throw error
                }
            }, merge: { [weak self] uid, fields, current, completion in
                guard let self, current() else { completion(CancellationError()); return }
                XCTAssertEqual(uid, "A"); XCTAssertEqual(fields["uid"] as? String, "A")
                XCTAssertNil(fields["bookmarkedArticles"])
                self.merges.append(.init(current: current, completion: completion)); self.events.send()
            }))

        lazy var notifications = Service(effects: .init(
            resolveOwner: { [weak self] in self?.uid.map(Service.TokenOwner.account) ?? .guest },
            authorizationStatus: { _ in .authorized }, requestAuthorization: { _ in false },
            register: { _ in }, fetchToken: { _ in nil },
            setTopic: { _, _, current, completion in completion(current() ? nil : CancellationError()) },
            saveAccountToken: { [weak self] token, uid, current, completion in
                guard let self else { return }; self.sdkEntries += 1
                let task = Service.saveAccountToken(token, userID: uid, stillCurrent: current,
                    runtime: self.runtime, write: { [weak self] token, uid, admitted, returned in
                        guard let self, admitted() else { returned(CancellationError()); return }
                        self.sdkPayloads.append((token, uid))
                        self.sdkWrites.append(.init(current: admitted, completion: returned)); self.events.send()
                    }, completion: { [weak self] error in
                        self?.sdkFeedback += 1; completion(error); self?.events.send()
                    })
                if let task { self.tokenTasks.append(task) }
            }, sendBackendToken: { [weak self] token, owner, current, completion in
                guard let self else { return }; self.httpEntries += 1
                let task = Service.sendBackendToken(token, owner: owner, stillCurrent: current,
                    runtime: self.runtime, transport: self.transport, completion: { [weak self] error in
                        self?.httpFeedback += 1; completion(error); self?.events.send()
                    })
                if let task { self.tokenTasks.append(task) }
            }, loadSettings: { _ in (.init(), []) }, persistSettings: { _, _, _ in },
            loadCategoryIDs: { _ in [] }, persistCategoryIDs: { _, _ in }, loadToken: { _ in nil },
            persistToken: { _, _ in }, diagnostic: { [weak self] diagnostic, current in
                if current() { self?.diagnostics.append(diagnostic); self?.events.send() }
            }))

        private var transport: Service.BackendTokenTransport {
            .init(endpoint: { URL(string: "https://local.example.invalid/token") },
                now: { Date(timeIntervalSince1970: 1_700_000_000) },
                makeTask: { [weak self] request, current, completion in
                    guard let self, current() else { throw CancellationError() }
                    self.requests.append(request)
                    return .init(resume: { [weak self] in
                        guard let self else { return }
                        self.httpWrites.append(.init(current: current, completion: completion)); self.events.send()
                    }, cancel: { completion(CancellationError()) })
                })
        }
        init() {
            _ = canonical.adopt(Self.session("A"))
            observation = state.changes.sink { [weak self] _ in self?.events.send() }
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "local@example.invalid", isEmailVerified: true)
        }
        static func profile(_ uid: String = "A", name: String = "Original") -> UserProfile {
            .init(uid: uid, email: "local@example.invalid", displayName: name, photoURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_000),
                favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
                readArticles: [], bookmarkedArticles: [], readingProgress: [:])
        }
        func start() async {
            manager.changeAccountContext(userID: uid); manager.startObservingSession()
            manager.loadUserProfile(Self.profile())
            await wait("Actual profile load and FCM follow-up") { self.state.snapshot.loaded && self.fcmCalls == 1 }
            XCTAssertTrue(sdkWrites.isEmpty); XCTAssertTrue(httpWrites.isEmpty)
            notifications.fcmToken = "original-token"
        }
        func save(_ name: String) async {
            let count = merges.count + 1
            XCTAssertNotNil(manager.saveUserProfile(Self.profile(name: name)))
            await wait("Actual profile physical merge") { self.merges.count == count }
        }
        func beginTokenWrites() async {
            await save("First save")
            finish(&merges, 0)
            await wait("Both actual token transports start") { self.sdkWrites.count == 1 && self.httpWrites.count == 1 }
        }
        func select(_ next: String) {
            uid = next; _ = canonical.adopt(Self.session(next)); manager.changeAccountContext(userID: next)
        }
        func finish(_ writes: inout [PhysicalWrite], _ index: Int, error: Error? = nil) {
            guard writes.indices.contains(index), let completion = writes[index].completion else {
                XCTFail("Expected a held physical callback"); return
            }
            writes[index].completion = nil; completion(error)
        }
        func finishDrain() {
            guard !drains.isEmpty, let completion = drains[0] else { XCTFail("Missing physical drain"); return }
            drains[0] = nil; completion(nil)
        }
        func finishTokenTasks() async { for task in tokenTasks { await task.value } }
        func wait(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                  _ predicate: @escaping @MainActor () -> Bool) async {
            if predicate() { return }
            let ready = XCTestExpectation(description: description)
            var finished = false
            let observation = events.sink {
                if !finished && predicate() { finished = true; ready.fulfill() }
            }
            let result = await XCTWaiter.fulfillment(of: [ready], timeout: 3)
            withExtendedLifetime(observation) {}
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func close() {
            manager.suspendForAccountChange(); tokenTasks.forEach { $0.cancel() }
            for i in merges.indices where merges[i].completion != nil { finish(&merges, i, error: Failure.unavailable) }
            for i in sdkWrites.indices where sdkWrites[i].completion != nil { finish(&sdkWrites, i, error: Failure.unavailable) }
            for i in httpWrites.indices where httpWrites[i].completion != nil { finish(&httpWrites, i, error: Failure.unavailable) }
            for i in drains.indices { let completion = drains[i]; drains[i] = nil; completion?(Failure.unavailable) }
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testActualProfileSuccessStartsBothOriginalTokenWritesThroughOneRuntime() async throws {
        let f = Fixture(); defer { f.close() }; await f.start(); await f.save("Updated")
        XCTAssertEqual(f.sdkEntries, 0); XCTAssertEqual(f.httpEntries, 0)
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.finish(&f.merges, 0)
        await f.wait("Original profile starts both token writes") { f.sdkWrites.count == 1 && f.httpWrites.count == 1 }
        XCTAssertEqual(f.profileOutcomes, [true]); XCTAssertEqual(f.fcmCalls, 2)
        XCTAssertEqual(f.sdkPayloads[0].0, "original-token"); XCTAssertEqual(f.sdkPayloads[0].1, "A")
        let body = try XCTUnwrap(f.requests[0].httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["userId"] as? String, "A"); XCTAssertEqual(payload["fcmToken"] as? String, "original-token")
        f.finish(&f.sdkWrites, 0)
        await f.wait("SDK receipt") { f.sdkFeedback == 1 }
        XCTAssertFalse(f.runtime.isPhysicallyIdle, "The HTTP callback still owns the same shared runtime")
        f.finish(&f.httpWrites, 0); await f.finishTokenTasks()
        XCTAssertEqual(f.httpFeedback, 1); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        XCTAssertTrue(f.diagnostics.isEmpty); XCTAssertNil(f.manager.errorMessage)
    }

    func testStopWaitsForAllThreePhysicalCallbacksAndLateProfileFollowupStartsNeitherTokenTransport() async throws {
        let f = Fixture(); defer { f.close() }; await f.start(); await f.beginTokenWrites(); await f.save("Held profile")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("Drain waits for the three writes") { f.deadlines.count == 1 }
        XCTAssertTrue(f.drains.isEmpty)
        f.finish(&f.merges, 1)
        await f.wait("Pre-stop profile success reaches the actual notification service") { f.fcmCalls == 3 }
        XCTAssertEqual(f.profileOutcomes, [true, true])
        XCTAssertEqual(f.sdkEntries, 2); XCTAssertEqual(f.httpEntries, 2)
        XCTAssertEqual(f.sdkWrites.count, 1); XCTAssertEqual(f.httpWrites.count, 1); XCTAssertEqual(f.requests.count, 1)
        XCTAssertTrue(f.drains.isEmpty)
        f.finish(&f.sdkWrites, 0); await f.tokenTasks[0].value
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertTrue(f.drains.isEmpty)
        f.finish(&f.httpWrites, 0); await f.finishTokenTasks()
        await f.wait("SDK drain starts only after HTTP also returns") { f.drains.count == 1 }
        f.finishDrain(); let receipt = try await drain.value
        XCTAssertTrue(f.runtime.isCurrent(receipt)); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        XCTAssertEqual(f.sdkWrites.count, 1); XCTAssertEqual(f.httpWrites.count, 1)
        XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testDrainTimeoutKeepsAllPhysicalWritesAndStoppedProfileFollowupCannotRestartThem() async throws {
        let f = Fixture(); defer { f.close() }; await f.start(); await f.beginTokenWrites(); await f.save("Held")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("Drain deadline") { f.deadlines.count == 1 }
        f.deadlines[0]()
        do { _ = try await drain.value; XCTFail("The deadline must fail the caller") }
        catch { XCTAssertEqual(error as? ReaderWriterDrainCoordinator.Failure, .timedOut) }
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.profileOutcomes, [true])
        f.finish(&f.merges, 1)
        await f.wait("Legitimate pre-stop profile returns") { f.fcmCalls == 3 }
        XCTAssertEqual(f.sdkWrites.count, 1); XCTAssertEqual(f.httpWrites.count, 1)
        f.finish(&f.sdkWrites, 0, error: Failure.unavailable); await f.tokenTasks[0].value
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.finish(&f.httpWrites, 0, error: Failure.unavailable); await f.finishTokenTasks()
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertEqual(f.sdkFeedback, 0); XCTAssertEqual(f.httpFeedback, 0)
        XCTAssertFalse(f.diagnostics.contains(.tokenSaveFailed)); XCTAssertFalse(f.diagnostics.contains(.tokenSendFailed))
    }

    func testCancelledDrainAndAccountRoundTripKeepSlotsWithoutOldProfileOrTokenFeedback() async throws {
        let f = Fixture(); defer { f.close() }; await f.start(); await f.beginTokenWrites(); await f.save("Old A")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("Cancelable drain") { f.deadlines.count == 1 }
        drain.cancel()
        do { _ = try await drain.value; XCTFail("Cancellation must not return a drain receipt") }
        catch { XCTAssertEqual(error as? ReaderWriterDrainCoordinator.Failure, .cancelled) }
        f.select("B"); f.select("A"); f.tokenTasks.forEach { $0.cancel() }
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.profileOutcomes, [true])
        XCTAssertFalse(f.merges[1].current()); XCTAssertFalse(f.sdkWrites[0].current()); XCTAssertFalse(f.httpWrites[0].current())
        f.finish(&f.merges, 1, error: Failure.unavailable)
        await f.wait("Stale profile physically returns") { f.profileOutcomes.count == 2 }
        XCTAssertEqual(f.profileOutcomes, [true, false]); XCTAssertEqual(f.fcmCalls, 2)
        f.finish(&f.sdkWrites, 0, error: Failure.unavailable); await f.tokenTasks[0].value
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.finish(&f.httpWrites, 0, error: Failure.unavailable); await f.finishTokenTasks()
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertEqual(f.sdkFeedback, 0); XCTAssertEqual(f.httpFeedback, 0); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertNil(f.manager.errorMessage); XCTAssertEqual(f.sdkEntries, 1); XCTAssertEqual(f.httpEntries, 1)
    }
}
