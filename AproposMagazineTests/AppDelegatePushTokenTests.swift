import Combine
import FirebaseCore
import UIKit
import UserNotifications
import XCTest
@testable import Apropos

/// Actual APNs delegate / FCM value entry, with a controlled callback-to-main
/// hop and memory-only effects. No Firebase, APNs registration or defaults.
@MainActor
final class AppDelegatePushTokenTests: XCTestCase {
    private typealias Guard = AppDelegate.PushGuard
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract

    private final class DeliveryQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var work: [@MainActor @Sendable () -> Void] = []
        func append(_ operation: @escaping @MainActor @Sendable () -> Void) {
            lock.lock(); work.append(operation); lock.unlock()
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return work.count }
        private func take() -> (@MainActor @Sendable () -> Void)? {
            lock.lock(); defer { lock.unlock() }
            return work.isEmpty ? nil : work.removeFirst()
        }
        @MainActor func drain() {
            // The controlled provider must not create an unbounded delivery loop.
            for _ in 0..<20 {
                guard let next = take() else { return }
                next()
            }
            XCTAssertEqual(count, 0)
        }
    }

    @MainActor private final class Fixture {
        struct Fetch { let original: Guard; let complete: AppDelegate.PushCompletion }
        struct Accepted { let token: String; let owner: NotificationService.TokenOwner; let original: Guard }
        let canonical = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        let delivery = DeliveryQueue()
        var providerUID: String?
        var providerReads = 0
        var providerHook: (() -> Void)?
        var assignmentHook: (() -> Void)?
        var fetchHook: (() -> Void)?
        var acceptanceHook: (() -> Void)?
        var diagnosticHook: (() -> Void)?
        var acceptanceService: NotificationService?
        var assigned: [Data] = [], fetches: [Fetch] = [], accepted: [Accepted] = []
        var diagnostics: [AppDelegate.PushDiagnostic] = []
        var delegate: AppDelegate?

        init(guarded: Bool = false, uid: String? = "A", restoring: Bool = false) {
            sdk = guarded ? ReaderSDKStartupState() : .application
            providerUID = uid
            if !restoring { _ = canonical.adopt(uid.map(Self.session)) }
            let queue = delivery
            let effects = AppDelegate.PushTokenEffects(assignAPNS: { [weak self] data, original in
                guard let self else { return }
                self.assignmentHook?()
                guard original() else { return }
                self.assigned.append(data)
            }, fetchToken: { [weak self] original, completion in
                guard let self, original() else { return }
                self.fetches.append(.init(original: original, complete: completion))
                self.fetchHook?()
            }, deliver: { operation in queue.append(operation) }, acceptToken: { [weak self] token, owner, original in
                guard let self else { return }
                self.acceptanceHook?()
                guard original() else { return }
                self.acceptanceService?.acceptRegistrationToken(token, owner: owner,
                    registerAccountToken: true, stillCurrent: original)
                guard original() else { return }
                self.accepted.append(.init(token: token, owner: owner, original: original))
            }, diagnostic: { [weak self] value, original in
                guard let self else { return }
                self.diagnosticHook?()
                guard original() else { return }
                self.diagnostics.append(value)
            })
            delegate = AppDelegate(startup: sdk, identity: canonical, actualUserID: { [weak self] in
                guard let self else { return nil }
                self.providerReads += 1; self.providerHook?(); return self.providerUID
            }, pushTokenEffects: effects)
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "local@example.invalid", isEmailVerified: true)
        }
        func select(_ uid: String?) { providerUID = uid; _ = canonical.adopt(uid.map(Self.session)) }
        func register(_ bytes: Data = Data([1, 2, 3])) {
            delegate?.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: bytes)
        }
        func token(_ token: String?) { delegate?.receivePushRegistrationToken(token) }
        func registrationFailed() {
            delegate?.application(UIApplication.shared,
                didFailToRegisterForRemoteNotificationsWithError: URLError(.notConnectedToInternet))
        }
        func flush() { delivery.drain() }
        var effectsCount: Int { assigned.count + fetches.count + accepted.count + diagnostics.count }
        func openStartup() async throws {
            let configuration = try Startup.Configuration(projectID: "local-push-test", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { request in
                let echo = try JSONSerialization.jsonObject(with: Contract.encode(request))
                return try Contract.decodeMembershipResponse(data: JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echo,
                    "membership": ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 3, "state": "active"],
                    "validUntilMs": 20_000
                ]), for: request)
            }
            let verify: Startup.Verifier = { challenge in
                .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: configuration.writerFenceRevision,
                    migrationRevision: configuration.migrationRevision, validUntilMs: 20_000)
            }
            let start: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { _, admit in
                try admit() // The actual startup admission, with no SDK initialization.
            }
            let coordinator = Startup(canonical: canonical, sdkState: sdk, configuration: configuration,
                readMarker: { nil }, readMembership: membership, verify: verify, startSDK: start,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await coordinator.start(context: canonical.contextTicket())
        }
    }

    /// The actual downstream service, with every external effect counted in memory.
    @MainActor private final class TokenSink {
        var events: [String] = [], persisted: [String] = []
        var topics: [(String, Bool)] = [], accounts: [(String, String)] = []
        var backend: [(String, NotificationService.TokenOwner)] = []
        var diagnostics: [NotificationService.Diagnostic] = []
        private var topicsFinished = false
        private var topicWaiter: XCTestExpectation?
        lazy var service = NotificationService(effects: .init(resolveOwner: { [weak self] in
            self?.events.append("unexpected-owner"); return .account("wrong-fallback")
        }, authorizationStatus: { [weak self] current in
            guard current() else { return .denied }
            self?.events.append("authorization"); return .authorized
        }, requestAuthorization: { [weak self] current in
            if current() { self?.events.append("unexpected-request") }; return false
        }, register: { [weak self] current in
            if current() { self?.events.append("unexpected-register") }
        }, fetchToken: { [weak self] current in
            if current() { self?.events.append("unexpected-fetch") }; return nil
        }, setTopic: { [weak self] topic, enabled, current, completion in
            guard let self, current() else { return }
            self.events.append("topic"); self.topics.append((topic, enabled)); completion(nil)
            if topic == "weekly_digest" {
                self.topicsFinished = true
                self.topicWaiter?.fulfill(); self.topicWaiter = nil
            }
        }, saveAccountToken: { [weak self] token, uid, current, completion in
            guard current() else { return }
            self?.events.append("account"); self?.accounts.append((token, uid)); completion(nil)
        }, sendBackendToken: { [weak self] token, owner, current, completion in
            guard current() else { return }
            self?.events.append("backend"); self?.backend.append((token, owner)); completion(nil)
        }, loadSettings: { [weak self] current in
            if current() { self?.events.append("settings-read") }
            return (.init(newArticles: true, newPodcasts: false, festivalReminders: false,
                breakingNews: false, weeklyDigest: false), [])
        }, persistSettings: { [weak self] _, _, current in
            if current() { self?.events.append("settings-write") }
        }, loadCategoryIDs: { [weak self] current in
            if current() { self?.events.append("categories-read") }; return ["culture"]
        }, persistCategoryIDs: { [weak self] _, current in
            if current() { self?.events.append("categories-write") }
        }, loadToken: { [weak self] current in
            if current() { self?.events.append("token-read") }; return nil
        }, persistToken: { [weak self] token, current in
            guard current() else { return }
            self?.events.append("token-write"); self?.persisted.append(token)
        }, diagnostic: { [weak self] diagnostic, current in
            guard current() else { return }
            self?.events.append("diagnostic"); self?.diagnostics.append(diagnostic)
        }))
        func waitForTopics() async {
            if topicsFinished { return }
            let value = XCTestExpectation(description: "Actual service completes local topic synchronization")
            topicWaiter = value
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testConstructionAndClosedStartupDoNotExecuteAnyPushEffect() {
        for restoring in [false, true] {
            let f = Fixture(guarded: true, restoring: restoring)
            XCTAssertEqual(f.providerReads, 0); XCTAssertEqual(f.effectsCount, 0)
            f.register(); f.token("closed-token"); f.registrationFailed(); f.flush()
            XCTAssertEqual(f.effectsCount, 0); XCTAssertTrue(f.fetches.isEmpty)
            XCTAssertEqual(f.delivery.count, 0)
        }
        let unresolved = Fixture(uid: nil, restoring: true)
        unresolved.register(); unresolved.token("unresolved-token"); unresolved.registrationFailed(); unresolved.flush()
        XCTAssertEqual(unresolved.effectsCount, 0); XCTAssertEqual(unresolved.providerReads, 0)
        XCTAssertEqual(unresolved.delivery.count, 0)
        let delegate = AppDelegate()
        delegate.receivePushRegistrationToken("test-host-token")
        delegate.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data([9]))
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testRealAuthorizedStartupAllowsAPNsThenOriginalAccountTokenOnControlledMainHop() async throws {
        let f = Fixture(guarded: true)
        try await f.openStartup()
        let bytes = Data([4, 5, 6]); f.register(bytes)
        XCTAssertEqual(f.assigned, [bytes]); XCTAssertEqual(f.fetches.count, 1)
        f.fetches[0].complete("account-token", nil)
        XCTAssertTrue(f.accepted.isEmpty); XCTAssertEqual(f.delivery.count, 1)
        f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["account-token"])
        XCTAssertEqual(f.accepted.first?.owner, .account("A")); XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testGuestTokenCarriesExplicitGuestOwnerAndClosedGuardedGuestRemainsClosed() {
        let closed = Fixture(guarded: true, uid: nil)
        closed.token("closed-guest"); closed.register(); closed.flush()
        XCTAssertEqual(closed.effectsCount, 0)
        let f = Fixture(uid: nil)
        f.token("guest-token"); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["guest-token"])
        XCTAssertEqual(f.accepted.first?.owner, .guest)
        XCTAssertTrue(f.assigned.isEmpty); XCTAssertTrue(f.fetches.isEmpty)
    }

    func testNewerDirectTokenRetiresHeldAPNsFetchBeforeItsFirstResult() throws {
        let f = Fixture(); f.register()
        let old = try XCTUnwrap(f.fetches.first)
        f.token("new-token"); f.flush()
        old.complete("old-token", nil); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["new-token"]); XCTAssertFalse(old.original())
        XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testQueuedAPNsResultCannotOverwriteTokenReceivedBeforeMainDelivery() throws {
        let f = Fixture(); f.register()
        let old = try XCTUnwrap(f.fetches.first)
        old.complete("queued-old-token", nil)
        XCTAssertEqual(f.delivery.count, 1); XCTAssertTrue(f.accepted.isEmpty)
        f.token("newer-token"); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["newer-token"]); XCTAssertFalse(old.original())
    }

    func testFetchErrorWinsOverSimultaneousTokenAndCallbackIsConsumedOnce() throws {
        let f = Fixture(); f.register()
        let fetch = try XCTUnwrap(f.fetches.first)
        fetch.complete("must-not-be-accepted", URLError(.cannotConnectToHost))
        fetch.complete("duplicate-success", nil)
        f.flush()
        XCTAssertTrue(f.accepted.isEmpty); XCTAssertEqual(f.diagnostics, [.fetchFailed])
        fetch.complete(nil, URLError(.networkConnectionLost)); f.flush()
        XCTAssertEqual(f.diagnostics, [.fetchFailed])
    }

    func testNilDirectTokenDoesNotCancelValidPendingFetch() throws {
        let f = Fixture(); f.register()
        let fetch = try XCTUnwrap(f.fetches.first)
        f.token(nil); f.flush()
        XCTAssertTrue(fetch.original())
        fetch.complete("still-current-token", nil); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["still-current-token"])
    }

    func testNestedTokenDuringProviderGetterRetiresOuterRegistrationBeforeSDKEffects() {
        let f = Fixture()
        f.providerHook = {
            f.providerHook = nil
            f.token("nested-token")
        }
        f.register(); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["nested-token"])
        XCTAssertTrue(f.assigned.isEmpty); XCTAssertTrue(f.fetches.isEmpty)
    }

    func testNestedTokenDuringAPNsAssignmentStopsOuterFetch() {
        let f = Fixture()
        f.assignmentHook = {
            f.assignmentHook = nil
            f.token("assignment-replacement")
        }
        f.register(); f.flush()
        XCTAssertTrue(f.fetches.isEmpty)
        XCTAssertEqual(f.accepted.map(\.token), ["assignment-replacement"])
    }

    func testFirstLateFailureCannotPublishDiagnosticsAfterNewerEntryDuringFetch() throws {
        let f = Fixture()
        f.fetchHook = {
            f.fetchHook = nil
            f.token("fresh-during-fetch")
        }
        f.register()
        let old = try XCTUnwrap(f.fetches.first)
        old.complete(nil, URLError(.networkConnectionLost)); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["fresh-during-fetch"])
        XCTAssertTrue(f.diagnostics.isEmpty); XCTAssertFalse(old.original())
    }

    func testAccountRoundTripBetweenPhysicalResultAndMainHopCannotAcceptOldOwner() throws {
        let f = Fixture(); f.register()
        let old = try XCTUnwrap(f.fetches.first)
        old.complete("old-A", nil)
        f.select("B"); f.select("A"); f.flush()
        XCTAssertTrue(f.accepted.isEmpty); XCTAssertTrue(f.diagnostics.isEmpty); XCTAssertFalse(old.original())
        f.token("fresh-A"); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["fresh-A"])
        XCTAssertEqual(f.accepted.last?.owner, .account("A"))
    }

    func testObservedProviderMismatchCannotReviveWhenUIDReturnsWithoutCanonicalChange() throws {
        let f = Fixture(); f.register()
        let old = try XCTUnwrap(f.fetches.first)
        f.providerUID = "B"; XCTAssertFalse(old.original())
        f.providerUID = "A"
        old.complete("old-provider-token", nil); f.flush()
        XCTAssertTrue(f.accepted.isEmpty); XCTAssertFalse(old.original())
        f.token("new-provider-token"); f.flush()
        XCTAssertEqual(f.accepted.map(\.token), ["new-provider-token"])
    }

    func testAccountReplacementInsideAcceptanceEffectRevokesItsFinalWriteGuard() throws {
        let f = Fixture(); f.register()
        let old = try XCTUnwrap(f.fetches.first)
        f.acceptanceHook = {
            f.acceptanceHook = nil
            f.select("B"); f.select("A")
        }
        old.complete("must-not-persist", nil); f.flush()
        XCTAssertTrue(f.accepted.isEmpty); XCTAssertFalse(old.original())
    }

    func testRegistrationFailureDiagnosticUsesCurrentPermissionAndFinalGuard() {
        let f = Fixture()
        f.registrationFailed(); f.flush()
        XCTAssertEqual(f.diagnostics, [.registrationFailed])
        f.diagnosticHook = {
            f.diagnosticHook = nil
            f.select("B"); f.select("A")
        }
        f.registrationFailed(); f.flush()
        XCTAssertEqual(f.diagnostics, [.registrationFailed])
        XCTAssertTrue(f.accepted.isEmpty)
    }

    func testHeldCallbackDoesNotKeepDelegateAliveOrPublishAfterDeallocation() throws {
        let f = Fixture(); f.register()
        let fetch = try XCTUnwrap(f.fetches.first)
        weak var delegate: AppDelegate?
        delegate = f.delegate
        f.delegate = nil
        XCTAssertNil(delegate)
        fetch.complete("late-after-release", nil); f.flush()
        XCTAssertTrue(f.accepted.isEmpty); XCTAssertTrue(f.diagnostics.isEmpty)
        XCTAssertFalse(fetch.original())
    }

    func testActualNotificationServicePersistsAndSendsOnlyNewerTokenAfterQueuedAPNsResult() async throws {
        let f = Fixture(), sink = TokenSink(); f.acceptanceService = sink.service
        f.register()
        let old = try XCTUnwrap(f.fetches.first)
        old.complete("queued-old", nil)
        f.token("new-value"); f.flush()
        await sink.waitForTopics()
        XCTAssertEqual(sink.service.fcmToken, "new-value")
        XCTAssertEqual(sink.persisted, ["new-value"])
        XCTAssertEqual(sink.accounts.map(\.0), ["new-value"]); XCTAssertEqual(sink.accounts.map(\.1), ["A"])
        XCTAssertEqual(sink.backend.map(\.0), ["new-value"]); XCTAssertEqual(sink.backend.map(\.1), [.account("A")])
        XCTAssertTrue(sink.topics.contains { $0.0 == "new_articles" && $0.1 })
        XCTAssertNotNil(sink.service.lastPushSyncedAt)
        XCTAssertFalse(sink.events.contains { $0.hasPrefix("unexpected-") })
        XCTAssertFalse(old.original()); XCTAssertTrue(f.diagnostics.isEmpty)
    }

    func testActualNotificationServiceRejectsOldMainHopAndPublicationReentryAfterAccountRoundTrip() async throws {
        let f = Fixture(), sink = TokenSink(); f.acceptanceService = sink.service
        f.register()
        let old = try XCTUnwrap(f.fetches.first)
        old.complete("old-A", nil)
        f.select("B"); f.select("A"); f.flush()
        XCTAssertTrue(sink.events.isEmpty); XCTAssertNil(sink.service.fcmToken)
        var changed = false
        let observation = sink.service.objectWillChange.sink {
            guard !changed else { return }; changed = true
            f.select("B"); f.select("A")
        }
        f.token("revoked-during-publication"); f.flush()
        XCTAssertTrue(changed); XCTAssertNil(sink.service.fcmToken)
        XCTAssertTrue(sink.events.isEmpty); XCTAssertTrue(sink.persisted.isEmpty)
        observation.cancel()
        f.token("fresh-A"); f.flush(); await sink.waitForTopics()
        XCTAssertEqual(sink.service.fcmToken, "fresh-A"); XCTAssertEqual(sink.persisted, ["fresh-A"])
        XCTAssertEqual(sink.accounts.map(\.0), ["fresh-A"]); XCTAssertEqual(sink.backend.map(\.1), [.account("A")])
        XCTAssertFalse(sink.events.contains { $0.hasPrefix("unexpected-") })
    }
}
