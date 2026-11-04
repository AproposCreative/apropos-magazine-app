import Combine
import FirebaseCore
import UserNotifications
import XCTest
@testable import Apropos

/// Real token-admission and topic-sync paths; every effect is local and observable.
@MainActor
final class NotificationRegistrationTokenTests: XCTestCase {
    private typealias Service = NotificationService
    @MainActor private final class Harness {
        var allowed = true
        var calls: [String] = []
        var cached: [String] = []
        var accounts: [(String, String, Service.Completion)] = []
        var backends: [(String, Service.TokenOwner, Service.Completion)] = []
        var topics: [(String, Bool, Service.OperationGuard, Service.Completion)] = []
        var diagnostics: [Service.Diagnostic] = []
        var hook: ((String) -> Void)?
        var statusHandler: (() async -> UNAuthorizationStatus)?
        var waiters: [(String, Int, XCTestExpectation)] = []
        lazy var service = Service(effects: .init(
            resolveOwner: { [unowned self] in hit("owner"); return .account("unrelated-account") },
            authorizationStatus: { [unowned self] current in
                guard current() else { return .notDetermined }
                hit("status")
                let status = await statusHandler?() ?? .authorized
                hit("statusReturned")
                return status
            },
            requestAuthorization: { [unowned self] _ in hit("request"); return false },
            register: { [unowned self] _ in hit("register") },
            fetchToken: { [unowned self] _ in hit("fetch"); return "unexpected" },
            setTopic: { [unowned self] topic, enabled, current, completion in
                guard current() else { completion(CancellationError()); return }
                hit("topic")
                guard current() else { completion(CancellationError()); return }
                topics.append((topic, enabled, current, completion))
            },
            saveAccountToken: { [unowned self] token, uid, current, completion in
                guard current() else { completion(CancellationError()); return }
                hit("account")
                guard current() else { completion(CancellationError()); return }
                accounts.append((token, uid, completion))
            },
            sendBackendToken: { [unowned self] token, owner, current, completion in
                guard current() else { completion(CancellationError()); return }
                hit("backend")
                guard current() else { completion(CancellationError()); return }
                backends.append((token, owner, completion))
            },
            loadSettings: { [unowned self] current in
                guard current() else { return (.init(), []) }
                hit("settings"); return (.init(), [])
            },
            persistSettings: { [unowned self] _, _, _ in hit("persistSettings") },
            loadCategoryIDs: { [unowned self] current in guard current() else { return [] }; hit("categories"); return ["culture"] },
            persistCategoryIDs: { [unowned self] _, _ in hit("persistCategories") },
            loadToken: { [unowned self] _ in hit("loadToken"); return nil },
            persistToken: { [unowned self] token, current in
                guard current() else { return }; hit("persist")
                guard current() else { return }; cached.append(token)
            },
            diagnostic: { [unowned self] diagnostic, current in
                guard current() else { return }; hit("diagnostic")
                guard current() else { return }; diagnostics.append(diagnostic)
            }
        ))
        func hit(_ event: String) {
            calls.append(event); hook?(event)
            let ready = waiters.filter { $0.0 == event && count(event) >= $0.1 }
            waiters.removeAll { $0.0 == event && count(event) >= $0.1 }
            ready.forEach { $0.2.fulfill() }
        }
        func count(_ event: String) -> Int { calls.filter { $0 == event }.count }
        func wait(_ event: String, count: Int = 1) async {
            if self.count(event) >= count { return }
            let expectation = XCTestExpectation(description: "Local \(event) \(count)")
            waiters.append((event, count, expectation))
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 2)
            XCTAssertEqual(result, .completed)
        }
        func accept(_ token: String, owner: Service.TokenOwner = .account("A"), register: Bool = true) {
            service.acceptRegistrationToken(token, owner: owner, registerAccountToken: register, stillCurrent: { self.allowed })
        }
    }
    private var failure: Error { URLError(.notConnectedToInternet) }

    func testInertConstructionAndClosedAdmissionHaveNoEffects() {
        XCTAssertNil(FirebaseApp.allApps)
        let h = Harness(); _ = h.service
        XCTAssertTrue(h.calls.isEmpty)
        h.allowed = false; h.accept("denied")
        XCTAssertNil(h.service.fcmToken)
        XCTAssertTrue(h.calls.isEmpty)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testExplicitAccountPublishesCachesSyncsAndRegistersOriginalOwner() async {
        let h = Harness(); h.accept("one", owner: .account("original"))
        XCTAssertEqual(h.service.fcmToken, "one")
        XCTAssertEqual(h.cached, ["one"])
        XCTAssertEqual(h.accounts.map(\.1), ["original"])
        XCTAssertEqual(h.backends.map(\.1), [.account("original")])
        await h.wait("settings")
        XCTAssertFalse(h.topics.isEmpty)
        XCTAssertEqual(h.count("owner"), 0)
        XCTAssertEqual(h.count("request"), 0)
        XCTAssertEqual(h.count("fetch"), 0)
        XCTAssertEqual(h.count("register"), 0)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testExplicitGuestEvenWhenEligibleNeverRegistersWithAnyAccount() async {
        let h = Harness(); h.accept("guest", owner: .guest, register: true)
        await h.wait("settings")
        XCTAssertEqual(h.service.fcmToken, "guest")
        XCTAssertEqual(h.cached, ["guest"])
        XCTAssertFalse(h.topics.isEmpty)
        XCTAssertTrue(h.accounts.isEmpty)
        XCTAssertTrue(h.backends.isEmpty)
        XCTAssertEqual(h.count("owner"), 0)
    }

    func testIneligibleAccountStillCachesAndSyncsWithoutServerRegistration() async {
        let h = Harness(); h.accept("no-profile", owner: .account("A"), register: false)
        await h.wait("settings")
        XCTAssertEqual(h.service.fcmToken, "no-profile")
        XCTAssertEqual(h.cached, ["no-profile"])
        XCTAssertFalse(h.topics.isEmpty)
        XCTAssertTrue(h.accounts.isEmpty)
        XCTAssertTrue(h.backends.isEmpty)
        XCTAssertEqual(h.count("owner"), 0)
    }

    func testPermissionRevokedByPublicationPreventsTokenAndAllFollowups() {
        let h = Harness()
        let subscription = h.service.objectWillChange.sink { h.allowed = false }
        h.accept("old")
        withExtendedLifetime(subscription) {}
        XCTAssertNil(h.service.fcmToken)
        XCTAssertTrue(h.calls.isEmpty)
    }

    func testNestedNewTokenDuringPublicationOwnsStateAndFollowups() async {
        let h = Harness(); var nested = false
        let subscription = h.service.objectWillChange.sink {
            if !nested { nested = true; h.accept("new", owner: .account("B")) }
        }
        h.accept("old", owner: .account("A"))
        await h.wait("settings")
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(h.service.fcmToken, "new")
        XCTAssertEqual(h.cached, ["new"])
        XCTAssertEqual(h.accounts.map(\.0), ["new"])
        XCTAssertEqual(h.accounts.map(\.1), ["B"])
    }

    func testReentrantOriginalGuardCannotOverwriteAcceptedNewerToken() async {
        let h = Harness(); var nested = false
        h.service.acceptRegistrationToken("old", owner: .account("A"), registerAccountToken: true, stillCurrent: {
            if !nested { nested = true; h.accept("new", owner: .account("B")) }
            return true
        })
        await h.wait("settings")
        XCTAssertEqual(h.service.fcmToken, "new")
        XCTAssertEqual(h.cached, ["new"])
        XCTAssertEqual(h.accounts.map(\.1), ["B"])
    }

    func testPersistenceHookDenialStopsTopicAndServerFollowups() {
        let h = Harness()
        h.hook = { if $0 == "persist" { h.allowed = false } }
        h.accept("one")
        XCTAssertEqual(h.service.fcmToken, "one") // Already accepted before permission changed.
        XCTAssertTrue(h.cached.isEmpty)
        XCTAssertTrue(h.accounts.isEmpty)
        XCTAssertTrue(h.backends.isEmpty)
        XCTAssertEqual(h.count("status"), 0)
    }

    func testNestedTokenDuringPersistenceCannotContinueOldRegistration() async {
        let h = Harness(); var nested = false
        h.hook = { event in
            if event == "persist" && !nested { nested = true; h.accept("new", owner: .account("B")) }
        }
        h.accept("old", owner: .account("A"))
        await h.wait("settings")
        XCTAssertEqual(h.cached, ["new"])
        XCTAssertEqual(h.service.fcmToken, "new")
        XCTAssertEqual(h.accounts.map(\.1), ["B"])
        XCTAssertEqual(h.backends.map(\.1), [.account("B")])
    }

    func testAccountWriteHookRevocationPreventsBackendStart() {
        let h = Harness()
        h.hook = { if $0 == "account" { h.allowed = false } }
        h.accept("one")
        XCTAssertEqual(h.cached, ["one"])
        XCTAssertTrue(h.accounts.isEmpty)
        XCTAssertTrue(h.backends.isEmpty)
        XCTAssertEqual(h.count("backend"), 0)
    }

    func testHeldTopicAuthorizationCannotPublishAfterPermissionDenial() async {
        let h = Harness()
        var continuation: CheckedContinuation<UNAuthorizationStatus, Never>?
        h.statusHandler = { await withCheckedContinuation { continuation = $0 } }
        h.accept("one", owner: .guest)
        await h.wait("status")
        h.allowed = false
        continuation?.resume(returning: .authorized)
        await h.wait("statusReturned")
        XCTAssertFalse(h.service.isAuthorized)
        XCTAssertTrue(h.topics.isEmpty)
        XCTAssertEqual(h.count("settings"), 0)
        XCTAssertNil(h.service.lastPushSyncedAt)
    }

    func testOldHeldTopicAuthorizationCannotReplaceNewTokenDiagnostics() async {
        let h = Harness()
        var continuation: CheckedContinuation<UNAuthorizationStatus, Never>?
        h.statusHandler = { await withCheckedContinuation { continuation = $0 } }
        h.accept("old", owner: .guest)
        await h.wait("status")
        h.statusHandler = { .denied }
        h.accept("new", owner: .guest)
        await h.wait("statusReturned")
        let currentSummary = h.service.lastPushSyncSummary
        continuation?.resume(returning: .authorized)
        await h.wait("statusReturned", count: 2)
        XCTAssertEqual(h.service.fcmToken, "new")
        XCTAssertFalse(h.service.isAuthorized)
        XCTAssertEqual(h.service.authorizationStatusDescription, "Afslået")
        XCTAssertEqual(h.service.lastPushSyncSummary, currentSummary)
        XCTAssertTrue(h.topics.isEmpty)
    }

    func testSameTokenStringAfterABARetiresOriginalPhysicalCallbacks() async {
        let h = Harness(); h.accept("T1")
        await h.wait("settings")
        let firstAccount = h.accounts[0].2, firstBackend = h.backends[0].2
        let firstTopic = h.topics.first { $0.1 }!
        h.accept("T2")
        h.accept("T1")
        await h.wait("settings", count: 2)
        let currentSummary = h.service.lastPushSyncSummary
        firstAccount(failure); firstBackend(failure); firstTopic.3(failure)
        XCTAssertEqual(h.service.fcmToken, "T1")
        XCTAssertTrue(h.diagnostics.isEmpty)
        XCTAssertEqual(h.service.lastPushSyncSummary, currentSummary)
        XCTAssertEqual(h.cached, ["T1", "T2", "T1"])
        XCTAssertEqual(h.accounts.map(\.0), ["T1", "T2", "T1"])
    }

    func testFirstLateWriteCallbackDenialLatchesEvenIfPermissionReturns() async {
        let h = Harness(); h.accept("one")
        await h.wait("settings")
        h.allowed = false
        h.accounts[0].2(failure)
        h.allowed = true
        h.backends[0].2(failure)
        h.topics.first { $0.1 }!.3(failure)
        XCTAssertTrue(h.diagnostics.isEmpty)
    }

    func testCurrentWriteFailuresStillReportInjectedDiagnostics() async {
        let h = Harness(); h.accept("one")
        await h.wait("settings")
        h.accounts[0].2(failure); h.backends[0].2(failure)
        XCTAssertEqual(h.diagnostics, [.tokenSaveFailed, .tokenSendFailed])
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testLegacyWritableTokenReplacementAlsoRetiresAcceptedCallback() async {
        let h = Harness(); h.accept("original")
        await h.wait("settings")
        h.service.fcmToken = "compatibility-new"
        h.accounts[0].2(failure); h.backends[0].2(failure)
        h.topics.first { $0.1 }!.3(failure)
        XCTAssertEqual(h.service.fcmToken, "compatibility-new")
        XCTAssertTrue(h.diagnostics.isEmpty)
    }
}
