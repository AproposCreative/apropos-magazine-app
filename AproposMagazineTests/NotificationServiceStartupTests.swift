import Combine
import FirebaseCore
import UserNotifications
import XCTest
@testable import Apropos

/// Exercises the same service algorithm as production with only local injected effects.
@MainActor
final class NotificationServiceStartupTests: XCTestCase {
    private typealias Service = NotificationService
    @MainActor private final class Harness {
        var events: [String] = []
        var owner: Service.TokenOwner = .account("A")
        var allowed = true
        var sourceStatus: UNAuthorizationStatus = .authorized
        var persistedToken: String?
        var fetchedToken: String? = "fetched"
        var stored: [(String, String)] = []
        var sent: [(String, Service.TokenOwner)] = []
        var topics: [(String, Bool, Service.OperationGuard, Service.Completion)] = []
        var accountCompletions: [Service.Completion] = []
        var backendCompletions: [Service.Completion] = []
        var diagnostics: [Service.Diagnostic] = []
        var preferences = NotificationPreferences()
        var categories: [String] = []
        var hook: ((String) -> Void)?
        var statusHandler: (() async -> UNAuthorizationStatus)?
        var requestHandler: (() async throws -> Bool)?
        var registerHandler: (() async -> Void)?
        var tokenHandler: (() async throws -> String?)?
        var waiters: [(String, Int, XCTestExpectation)] = []
        lazy var service = Service(effects: Service.Effects(
            resolveOwner: { [unowned self] in hit("owner"); return owner },
            authorizationStatus: { [unowned self] current in
                guard current() else { return .notDetermined }
                hit("status")
                return await statusHandler?() ?? sourceStatus
            },
            requestAuthorization: { [unowned self] current in
                guard current() else { throw CancellationError() }
                hit("request")
                if let requestHandler { return try await requestHandler() }
                sourceStatus = .authorized
                return true
            },
            register: { [unowned self] current in
                guard current() else { return }; hit("register"); await registerHandler?()
            },
            fetchToken: { [unowned self] current in
                guard current() else { throw CancellationError() }; hit("fetch")
                if let tokenHandler { return try await tokenHandler() }
                return fetchedToken
            },
            setTopic: { [unowned self] topic, enabled, current, completion in
                guard current() else { completion(CancellationError()); return }
                hit("topic"); topics.append((topic, enabled, current, completion))
            },
            saveAccountToken: { [unowned self] token, uid, current, completion in
                guard current() else { completion(CancellationError()); return }
                hit("account"); stored.append((token, uid)); accountCompletions.append(completion)
            },
            sendBackendToken: { [unowned self] token, owner, current, completion in
                guard current() else { completion(CancellationError()); return }
                hit("backend"); sent.append((token, owner)); backendCompletions.append(completion)
            },
            loadSettings: { [unowned self] current in
                guard current() else { return (NotificationPreferences(), []) }
                hit("loadSettings"); return (preferences, categories)
            },
            persistSettings: { [unowned self] preferences, ids, current in
                guard current() else { return }; hit("persistSettings")
                guard current() else { return }; self.preferences = preferences; categories = ids
            },
            loadCategoryIDs: { [unowned self] current in guard current() else { return [] }; hit("loadCategories"); return categories },
            persistCategoryIDs: { [unowned self] ids, current in guard current() else { return }; hit("persistCategories"); categories = ids },
            loadToken: { [unowned self] current in guard current() else { return nil }; hit("loadToken"); return persistedToken },
            persistToken: { [unowned self] token, current in guard current() else { return }; hit("persistToken"); persistedToken = token },
            diagnostic: { [unowned self] diagnostic, current in
                guard current() else { return }; hit("diagnostic"); guard current() else { return }; diagnostics.append(diagnostic)
            }
        ))
        func hit(_ event: String) {
            events.append(event); hook?(event)
            let ready = waiters.filter { $0.0 == event && count(event) >= $0.1 }
            waiters.removeAll { $0.0 == event && count(event) >= $0.1 }
            ready.forEach { $0.2.fulfill() }
        }
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        func wait(_ event: String, count: Int = 1) async {
            if self.count(event) >= count { return }
            let expectation = XCTestExpectation(description: "Local \(event) \(count)")
            waiters.append((event, count, expectation))
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 2)
            XCTAssertEqual(result, .completed)
        }
        func activate(owner: Service.TokenOwner? = .account("A"), preferences: NotificationPreferences = .init()) async {
            await service.activateArticlePushNotifications(preferences: preferences, selectedCategoryIds: [], allCategoryIds: ["culture"],
                owner: owner, stillCurrent: { self.allowed })
        }
    }
    private var failure: Error { URLError(.notConnectedToInternet) }

    func testConstructionAndClosedActivationTouchNoEffectsOrFirebase() async {
        XCTAssertNil(FirebaseApp.allApps)
        let h = Harness(); _ = h.service
        XCTAssertTrue(h.events.isEmpty)
        h.allowed = false
        await h.activate(owner: nil)
        XCTAssertTrue(h.events.isEmpty)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testGuestNeverResolvesOrWritesCurrentAccount() async {
        let h = Harness()
        await h.activate(owner: .guest)
        XCTAssertEqual(h.count("owner"), 0)
        XCTAssertTrue(h.stored.isEmpty)
        XCTAssertEqual(h.sent.map(\.1), [.guest])
        XCTAssertEqual(h.sent.map(\.0), ["fetched"])
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testLegacyOwnerCapturedBeforeAuthorizationAwait() async {
        let h = Harness()
        var continuation: CheckedContinuation<UNAuthorizationStatus, Never>?
        h.statusHandler = { await withCheckedContinuation { continuation = $0 } }
        let task = Task { await h.activate(owner: nil) }
        await h.wait("status")
        h.owner = .account("B")
        continuation?.resume(returning: .authorized)
        await task.value
        XCTAssertEqual(h.count("owner"), 1)
        XCTAssertEqual(h.stored.map(\.1), ["A"])
        XCTAssertEqual(h.sent.map(\.1), [.account("A")])
    }

    func testDeniedHeldAuthorizationCannotPublishOrRegister() async {
        let h = Harness()
        var continuation: CheckedContinuation<UNAuthorizationStatus, Never>?
        h.statusHandler = { await withCheckedContinuation { continuation = $0 } }
        let task = Task { await h.activate() }
        await h.wait("status")
        h.allowed = false
        continuation?.resume(returning: .authorized)
        await task.value
        XCTAssertFalse(h.service.isAuthorized)
        XCTAssertEqual(h.service.authorizationStatusDescription, "Ukendt")
        XCTAssertEqual(h.count("register"), 0)
        XCTAssertEqual(h.count("fetch"), 0)
    }

    func testDeniedPermissionRequestDoesNotRegisterAfterCallback() async {
        let h = Harness(); h.sourceStatus = .notDetermined
        var continuation: CheckedContinuation<Bool, Error>?
        h.requestHandler = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let task = Task { await h.activate() }
        await h.wait("request")
        h.allowed = false; continuation?.resume(returning: true)
        await task.value
        XCTAssertEqual(h.count("register"), 0)
        XCTAssertEqual(h.count("status"), 1)
        XCTAssertTrue(h.diagnostics.isEmpty)
    }

    func testPermissionFailurePublishesOnlyForOriginalAction() async {
        let h = Harness(); h.sourceStatus = .denied
        h.requestHandler = { throw URLError(.notConnectedToInternet) }
        await h.activate()
        XCTAssertEqual(h.diagnostics, [.permissionFailed])
        XCTAssertEqual(h.service.lastPushSyncSummary, "Kunne ikke anmode om tilladelse.")
        XCTAssertEqual(h.count("register"), 0)
    }

    func testHeldRegistrationDenialStopsTokenAndTopics() async {
        let h = Harness()
        var continuation: CheckedContinuation<Void, Never>?
        h.registerHandler = { await withCheckedContinuation { continuation = $0 } }
        let task = Task { await h.activate() }
        await h.wait("register")
        h.allowed = false; continuation?.resume()
        await task.value
        XCTAssertEqual(h.count("fetch"), 0)
        XCTAssertTrue(h.topics.isEmpty)
        XCTAssertTrue(h.stored.isEmpty)
    }

    func testHeldTokenCannotPublishAfterOriginalPermissionDenied() async {
        let h = Harness()
        var continuation: CheckedContinuation<String?, Error>?
        h.tokenHandler = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let task = Task { await h.activate() }
        await h.wait("fetch")
        h.allowed = false; continuation?.resume(returning: "old")
        await task.value
        XCTAssertNil(h.service.fcmToken)
        XCTAssertEqual(h.count("persistToken"), 0)
        XCTAssertTrue(h.topics.isEmpty)
        XCTAssertTrue(h.sent.isEmpty)
    }

    func testReplacementActivationRetiresOldHeldToken() async {
        let h = Harness()
        var continuation: CheckedContinuation<String?, Error>?
        h.tokenHandler = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let old = Task { await h.activate(owner: .account("A")) }
        await h.wait("fetch")
        h.tokenHandler = nil; h.fetchedToken = "new"
        await h.activate(owner: .account("B"))
        continuation?.resume(returning: "old")
        await old.value
        XCTAssertEqual(h.service.fcmToken, "new")
        XCTAssertEqual(h.stored.map(\.1), ["B"])
        XCTAssertEqual(h.sent.map(\.0), ["new"])
        XCTAssertEqual(h.count("persistToken"), 1)
    }

    func testNewAppDelegateTokenWinsOverHeldRefresh() async {
        let h = Harness()
        var continuation: CheckedContinuation<String?, Error>?
        h.tokenHandler = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let task = Task { await h.activate() }
        await h.wait("fetch")
        h.service.fcmToken = "delegate-new"
        continuation?.resume(returning: "fetch-old")
        await task.value
        XCTAssertEqual(h.service.fcmToken, "delegate-new")
        XCTAssertEqual(h.sent.map(\.0), ["delegate-new"])
        XCTAssertEqual(h.count("persistToken"), 0)
    }

    func testLateTopicCallbackLatchesDenialAndCannotRevive() async {
        let h = Harness(); await h.activate()
        let topic = h.topics[0]
        let oldSummary = h.service.lastPushSyncSummary
        h.allowed = false
        XCTAssertFalse(topic.2())
        h.allowed = true
        topic.3(failure)
        XCTAssertTrue(h.diagnostics.isEmpty)
        XCTAssertEqual(h.service.lastPushSyncSummary, oldSummary)
    }

    func testTopicCallbackOnlyProcessesFirstPhysicalResult() async {
        let h = Harness(); await h.activate()
        let topic = h.topics.first { $0.1 }!
        topic.3(failure); topic.3(nil)
        XCTAssertEqual(h.diagnostics, [.topicFailed(topic.0, true)])
        XCTAssertEqual(h.service.lastPushSyncSummary, "Kunne ikke tilmelde \(topic.0).")
    }

    func testLateTokenWriteDiagnosticsCannotCrossOriginalPermission() async {
        let h = Harness(); await h.activate()
        h.allowed = false
        h.accountCompletions[0](failure)
        h.allowed = true
        h.backendCompletions[0](failure)
        XCTAssertTrue(h.diagnostics.isEmpty)
    }

    func testDiagnosticReentryCannotPublishOldFailureSummary() async {
        let h = Harness(); await h.activate()
        let old = h.service.lastPushSyncSummary
        h.hook = { event in if event == "diagnostic" { h.allowed = false } }
        h.topics.first { $0.1 }!.3(failure)
        XCTAssertEqual(h.service.lastPushSyncSummary, old)
        XCTAssertTrue(h.diagnostics.isEmpty)
    }

    func testAuthorizationWillChangeDenialPreventsAssignmentAndNextEffect() async {
        let h = Harness()
        let subscription = h.service.objectWillChange.sink { h.allowed = false }
        await h.activate()
        withExtendedLifetime(subscription) {}
        XCTAssertFalse(h.service.isAuthorized)
        XCTAssertEqual(h.service.authorizationStatusDescription, "Ukendt")
        XCTAssertEqual(h.count("register"), 0)
    }

    func testTokenWillChangeDenialPreventsAssignmentAndPersistence() async {
        let h = Harness(); var armed = false
        h.hook = { if $0 == "fetch" { armed = true } }
        let subscription = h.service.objectWillChange.sink { if armed { h.allowed = false } }
        await h.activate()
        withExtendedLifetime(subscription) {}
        XCTAssertNil(h.service.fcmToken)
        XCTAssertEqual(h.count("persistToken"), 0)
        XCTAssertTrue(h.topics.isEmpty)
    }

    func testSettingsEffectReentryDenialStopsAuthorization() async {
        let h = Harness()
        h.hook = { if $0 == "persistSettings" { h.allowed = false } }
        await h.activate()
        XCTAssertEqual(h.count("status"), 0)
        XCTAssertTrue(h.stored.isEmpty)
    }

    func testDisabledChoicesNeedNoOwnerAuthorizationRegistrationOrToken() async {
        let h = Harness()
        await h.activate(owner: nil, preferences: .init(newArticles: false, newPodcasts: false,
            festivalReminders: false, breakingNews: false, weeklyDigest: false))
        XCTAssertEqual(h.count("owner"), 0)
        XCTAssertEqual(h.count("status"), 0)
        XCTAssertEqual(h.count("request"), 0)
        XCTAssertEqual(h.count("register"), 0)
        XCTAssertEqual(h.count("fetch"), 0)
        XCTAssertEqual(h.count("loadToken"), 0)
        XCTAssertFalse(h.topics.isEmpty)
        XCTAssertTrue(h.topics.allSatisfy { !$0.1 })
        XCTAssertEqual(h.service.lastPushSyncSummary, "Notifikationer er slået fra.")
    }

    func testResyncRestoresPersistedTokenAfterInertInitWithoutFetch() async {
        let h = Harness(); h.persistedToken = "persisted"
        _ = h.service; XCTAssertTrue(h.events.isEmpty)
        await h.service.resyncPushSubscriptions(stillCurrent: { h.allowed })
        XCTAssertEqual(h.service.fcmToken, "persisted")
        XCTAssertEqual(h.count("fetch"), 0)
        XCTAssertEqual(h.sent.map(\.0), ["persisted"])
        XCTAssertFalse(h.service.isResyncingPush)
        XCTAssertNotNil(h.service.lastPushSyncedAt)
    }

    func testBootstrapUsesInjectedStorageAndClosedBootstrapIsInert() async {
        let h = Harness(); h.persistedToken = "persisted"
        h.allowed = false
        await h.service.bootstrapPushNotifications(stillCurrent: { h.allowed })
        XCTAssertTrue(h.events.isEmpty)
        h.allowed = true
        await h.service.bootstrapPushNotifications(stillCurrent: { h.allowed })
        XCTAssertEqual(h.count("loadToken"), 1)
        XCTAssertEqual(h.count("fetch"), 0)
        XCTAssertEqual(h.count("loadSettings"), 1)
        XCTAssertEqual(h.sent.map(\.0), ["persisted"])
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testOriginalResyncCleanupCannotClearReplacementBusyState() async {
        let h = Harness()
        var continuations: [CheckedContinuation<UNAuthorizationStatus, Never>] = []
        h.statusHandler = { await withCheckedContinuation { continuations.append($0) } }
        let first = Task { await h.service.resyncPushSubscriptions(stillCurrent: { h.allowed }) }
        await h.wait("status")
        let second = Task { await h.service.resyncPushSubscriptions(stillCurrent: { h.allowed }) }
        await h.wait("status", count: 2)
        continuations[0].resume(returning: .authorized)
        await first.value
        XCTAssertTrue(h.service.isResyncingPush)
        h.allowed = false
        continuations[1].resume(returning: .authorized)
        await second.value
        XCTAssertFalse(h.service.isResyncingPush)
        XCTAssertEqual(h.count("register"), 0)
    }

    func testGuardedCategoryPersistenceDeniedBeforeEffect() {
        let h = Harness(); h.allowed = false
        h.service.persistAllCategoryIds(["new"], stillCurrent: { h.allowed })
        XCTAssertTrue(h.events.isEmpty)
    }

    func testCancelledHeldTokenHasNoFollowupEffects() async {
        let h = Harness()
        var continuation: CheckedContinuation<String?, Error>?
        h.tokenHandler = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let task = Task { await h.activate() }
        await h.wait("fetch")
        task.cancel(); continuation?.resume(returning: "late")
        await task.value
        XCTAssertNil(h.service.fcmToken)
        XCTAssertTrue(h.topics.isEmpty)
        XCTAssertTrue(h.sent.isEmpty)
    }
}
