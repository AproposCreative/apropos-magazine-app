import Combine
import FirebaseCore
import UserNotifications
import XCTest
@testable import Apropos

/// Actual Settings capture -> UserManager -> NotificationService. The provider,
/// storage and OS boundaries are all local; no SDK, defaults or APNs are started.
@MainActor
final class NotificationSettingsStartupIntegrationTests: XCTestCase {
    private typealias Service = NotificationService
    private typealias Guard = Service.OperationGuard
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract

    @MainActor private final class Lane<Value> {
        var guards: [Guard] = []
        private var pending: [Int: CheckedContinuation<Value, Error>] = [:]
        private var observers: [(Int, XCTestExpectation)] = []
        func perform(_ original: @escaping Guard) async throws -> Value {
            try await withCheckedThrowingContinuation { continuation in
                let index = guards.count; guards.append(original); pending[index] = continuation
                let ready = observers.filter { $0.0 <= guards.count }
                observers.removeAll { $0.0 <= guards.count }; ready.forEach { $0.1.fulfill() }
            }
        }
        func waitForStarts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if guards.count >= count { return }
            let value = XCTestExpectation(description: "Held notification provider starts \(count)")
            observers.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func finish(_ index: Int, _ result: Result<Value, Error>) {
            pending.removeValue(forKey: index)?.resume(with: result)
        }
        func close() {
            let held = Array(pending.values); pending.removeAll()
            held.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    @MainActor private final class Fixture {
        struct Settings { let preferences: NotificationPreferences; let categories: [String] }
        struct Topic { let name: String; let enabled: Bool; let original: Guard; let complete: Service.Completion }
        let state = UserProfileState()
        let canonical = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        let authorization = Lane<Bool>(), token = Lane<String?>()
        var providerUID: String?
        var providerHook: (() -> Void)?
        var authorizationStatus: UNAuthorizationStatus = .authorized
        var holdAuthorization = false, holdToken = false, holdTopicCompletions = false
        var existingToken: String? = "local-existing-token"
        var captures = 0, profileReads = 0, profileWrites: [UserProfile] = []
        var ownerResolutions = 0, statusReads = 0, authorizationRequests = 0, registrations = 0, tokenFetches = 0
        var settingsReads = 0, categoryReads = 0, tokenReads = 0
        var settings: [Settings] = [], categories: [[String]] = [], persistedTokens: [String] = []
        var topics: [Topic] = [], accountTokens: [(String, String)] = [], backendTokens: [(String, Service.TokenOwner)] = []
        var diagnostics: [Service.Diagnostic] = []
        private var writeObservers: [(Int, XCTestExpectation)] = []

        lazy var manager = UserManager(state: state, effects: .init(capturePermission: { [weak self] in
            guard let self else { return nil }
            self.captures += 1
            return self.sdk.captureReaderWork(identity: self.canonical, actualUserID: { [weak self] in
                guard let self else { return nil }
                self.providerHook?(); return self.providerUID
            })
        }, identity: { [weak self] in
            .init(actualUID: self?.providerUID, canonicalUID: self?.canonical.snapshot.userID)
        }, read: { [weak self] seed, _, _, original in
            guard let self, original() else { throw CancellationError() }
            self.profileReads += 1
            return .init(profile: seed, isFromCache: false)
        }, write: { [weak self] profile, _, original in
            guard let self, original() else { throw CancellationError() }
            self.profileWrites.append(profile)
            let ready = self.writeObservers.filter { $0.0 <= self.profileWrites.count }
            self.writeObservers.removeAll { $0.0 <= self.profileWrites.count }; ready.forEach { $0.1.fulfill() }
        }, subscribe: { _, _ in }, unsubscribe: { _, _ in }, updateFCM: { _, _ in }), currentProfileSeed: { [weak self] in
            self?.providerUID.map { Self.profile($0) }
        })

        lazy var notifications = Service(effects: .init(resolveOwner: { [weak self] in
            self?.ownerResolutions += 1
            return .account("must-not-be-used-by-settings")
        }, authorizationStatus: { [weak self] original in
            guard let self, original() else { return .denied }
            self.statusReads += 1; return self.authorizationStatus
        }, requestAuthorization: { [weak self] original in
            guard let self, original() else { throw CancellationError() }
            self.authorizationRequests += 1
            let granted = self.holdAuthorization ? try await self.authorization.perform(original) : true
            self.authorizationStatus = granted ? .authorized : .denied
            return granted
        }, register: { [weak self] original in
            if original() { self?.registrations += 1 }
        }, fetchToken: { [weak self] original in
            guard let self, original() else { throw CancellationError() }
            self.tokenFetches += 1
            if self.holdToken { return try await self.token.perform(original) }
            return "local-fetched-token"
        }, setTopic: { [weak self] name, enabled, original, complete in
            guard let self, original() else { return }
            self.topics.append(.init(name: name, enabled: enabled, original: original, complete: complete))
            if !self.holdTopicCompletions { complete(nil) }
        }, saveAccountToken: { [weak self] token, uid, original, complete in
            guard let self, original() else { return }
            self.accountTokens.append((token, uid)); complete(nil)
        }, sendBackendToken: { [weak self] token, owner, original, complete in
            guard let self, original() else { return }
            self.backendTokens.append((token, owner)); complete(nil)
        }, loadSettings: { [weak self] original in
            if original() { self?.settingsReads += 1 }
            return (Self.preferences(), [])
        }, persistSettings: { [weak self] preferences, categories, original in
            if original() { self?.settings.append(.init(preferences: preferences, categories: categories)) }
        }, loadCategoryIDs: { [weak self] original in
            if original() { self?.categoryReads += 1 }
            return ["music", "culture"]
        }, persistCategoryIDs: { [weak self] ids, original in
            if original() { self?.categories.append(ids) }
        }, loadToken: { [weak self] original in
            guard let self, original() else { return nil }
            self.tokenReads += 1; return self.existingToken
        }, persistToken: { [weak self] token, original in
            if original() { self?.persistedTokens.append(token) }
        }, diagnostic: { [weak self] diagnostic, original in
            if original() { self?.diagnostics.append(diagnostic) }
        }))

        init(guarded: Bool = false, uid: String? = "A") {
            sdk = guarded ? ReaderSDKStartupState() : .application
            providerUID = uid; _ = canonical.adopt(uid.map(Self.session))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
        }
        static func preferences(articles: Bool = true, podcasts: Bool = false) -> NotificationPreferences {
            .init(newArticles: articles, newPodcasts: podcasts, festivalReminders: false,
                breakingNews: false, weeklyDigest: false)
        }
        static func profile(_ uid: String, name: String = "Lokal læser") -> UserProfile {
            .init(uid: uid, email: uid + "@example.invalid", displayName: name, photoURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
                favoriteCategories: [], favoriteAuthors: [], notificationPreferences: preferences(articles: false),
                readingPreferences: .init(), readArticles: [], bookmarkedArticles: [], readingProgress: [:])
        }
        func start() {
            manager.changeAccountContext(userID: providerUID); manager.startObservingSession()
        }
        func select(_ uid: String?) {
            providerUID = uid; _ = canonical.adopt(uid.map(Self.session))
            manager.changeAccountContext(userID: uid)
        }
        func choose(_ preferences: NotificationPreferences? = nil, ids: [String] = [],
                    all: [String] = ["music", "culture"]) -> (@MainActor () async -> Void)? {
            manager.captureNotificationChoices(preferences: preferences ?? Self.preferences(), categoryIDs: ids, allCategoryIDs: all,
                context: state.contextTicket(), service: notifications)
        }
        func close() { providerHook = nil; manager.suspendForAccountChange(); authorization.close(); token.close() }
        var notificationEffects: Int {
            ownerResolutions + statusReads + authorizationRequests + registrations + tokenFetches
                + settingsReads + categoryReads + tokenReads + settings.count + categories.count
                + persistedTokens.count + topics.count + accountTokens.count + backendTokens.count + diagnostics.count
        }
        func waitForWrites(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if profileWrites.count >= count { return }
            let value = XCTestExpectation(description: "Profile choice reaches original write")
            writeObservers.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func openGuardedStartup() async throws {
            let configuration = try Startup.Configuration(projectID: "local-notification-test", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { request in
                let echo = try JSONSerialization.jsonObject(with: Contract.encode(request))
                let data = try JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echo,
                    "membership": ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 4, "state": "active"],
                    "validUntilMs": 20_000
                ])
                return try Contract.decodeMembershipResponse(data: data, for: request)
            }
            let verify: Startup.Verifier = { challenge in
                .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: configuration.writerFenceRevision,
                    migrationRevision: configuration.migrationRevision, validUntilMs: 20_000)
            }
            let start: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { _, admit in try admit() }
            let startup = Startup(canonical: canonical, sdkState: sdk, configuration: configuration,
                readMarker: { nil }, readMembership: membership, verify: verify, startSDK: start,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await startup.start(context: canonical.contextTicket())
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func loaded(_ f: Fixture, name: String = "Lokal læser") async {
        let ready = XCTestExpectation(description: "Actual profile pipeline accepts local seed")
        var completed = false
        let observation = f.state.changes.sink { value in
            if !completed && value.loaded && value.profile?.displayName == name {
                completed = true; ready.fulfill()
            }
        }
        f.manager.loadUserProfile(Fixture.profile(f.providerUID ?? "A", name: name))
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 3)
        withExtendedLifetime(observation) {}
        XCTAssertEqual(result, .completed)
    }

    func testInertConstructionAndClosedStartupRunNoNotificationEffectsUntilFreshAuthorizedChoice() async throws {
        let f = Fixture(guarded: true); defer { f.close() }
        _ = f.manager; _ = f.notifications
        XCTAssertEqual(f.captures, 0); XCTAssertEqual(f.notificationEffects, 0)
        f.start(); XCTAssertNil(f.choose())
        f.manager.loadUserProfile(Fixture.profile("A"))
        XCTAssertEqual(f.profileReads, 0); XCTAssertTrue(f.profileWrites.isEmpty)
        XCTAssertEqual(f.notificationEffects, 0)
        try await f.openGuardedStartup(); await loaded(f)
        let current = try XCTUnwrap(f.choose()); await current(); await f.waitForWrites(1)
        XCTAssertEqual(f.backendTokens.last?.1, .account("A")); XCTAssertEqual(f.ownerResolutions, 0)
    }

    func testLegacyGuestUsesExplicitGuestOwnerAndClosedGuardedGuestCannotAdoptFallbackAccount() async throws {
        let closed = Fixture(guarded: true, uid: nil); defer { closed.close() }; closed.start()
        XCTAssertNil(closed.choose()); XCTAssertEqual(closed.notificationEffects, 0)
        let f = Fixture(uid: nil); defer { f.close() }; f.start()
        let operation = try XCTUnwrap(f.choose()); await operation()
        XCTAssertEqual(f.backendTokens.last?.1, .guest); XCTAssertTrue(f.accountTokens.isEmpty)
        XCTAssertTrue(f.profileWrites.isEmpty); XCTAssertEqual(f.profileReads, 0); XCTAssertEqual(f.ownerResolutions, 0)
    }

    func testChoiceCapturesPayloadBeforeTaskAndCanOnlyApplyOnce() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        var preferences = Fixture.preferences(articles: false, podcasts: true), ids = ["culture"]
        let originalPreferences = preferences, operation = try XCTUnwrap(f.choose(preferences, ids: ids))
        preferences.newPodcasts = false; ids = ["music"]
        await operation(); await f.waitForWrites(1)
        XCTAssertEqual(f.settings.first?.preferences, originalPreferences); XCTAssertEqual(f.settings.first?.categories, ["culture"])
        XCTAssertEqual(f.profileWrites.first?.notificationPreferences, originalPreferences)
        let effects = f.notificationEffects
        await operation()
        XCTAssertEqual(f.notificationEffects, effects); XCTAssertEqual(f.profileWrites.count, 1)
        XCTAssertFalse(preferences.newPodcasts); XCTAssertEqual(ids, ["music"])
    }

    func testDelayedAccountChoiceCannotApplyAfterSameUIDRoundTrip() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let old = try XCTUnwrap(f.choose(Fixture.preferences(podcasts: true)))
        f.select("B"); f.select("A"); await loaded(f, name: "Ny A")
        let before = f.state.snapshot
        await old()
        XCTAssertEqual(f.state.snapshot, before); XCTAssertTrue(f.profileWrites.isEmpty)
        XCTAssertEqual(f.notificationEffects, 0)
    }

    func testDelayedGuestChoiceCannotRegisterTokenForLaterAccount() async throws {
        let f = Fixture(uid: nil); defer { f.close() }; f.start()
        let guest = try XCTUnwrap(f.choose())
        f.select("A"); await loaded(f); await guest()
        XCTAssertTrue(f.backendTokens.isEmpty); XCTAssertTrue(f.accountTokens.isEmpty)
        XCTAssertTrue(f.profileWrites.isEmpty); XCTAssertEqual(f.notificationEffects, 0)
    }

    func testLatestSynchronousChoiceWinsBeforeEitherTaskStarts() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let old = try XCTUnwrap(f.choose(Fixture.preferences(podcasts: true), ids: ["music"]))
        let newPreferences = Fixture.preferences(articles: false, podcasts: true)
        let current = try XCTUnwrap(f.choose(newPreferences, ids: ["culture"]))
        await old(); XCTAssertEqual(f.notificationEffects, 0); XCTAssertTrue(f.profileWrites.isEmpty)
        await current(); await f.waitForWrites(1)
        XCTAssertEqual(f.settings.map(\.categories), [["culture"]])
        XCTAssertEqual(f.profileWrites.first?.notificationPreferences, newPreferences)
    }

    func testRejectedStaleAccountCaptureDoesNotCancelAlreadyCapturedCurrentAccountChoice() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let oldContext = f.state.contextTicket()
        f.select("B"); await loaded(f, name: "Aktuel B")
        let current = try XCTUnwrap(f.choose(Fixture.preferences(podcasts: true), ids: ["culture"]))
        let stale = f.manager.captureNotificationChoices(preferences: Fixture.preferences(), categoryIDs: ["music"],
            allCategoryIDs: ["music", "culture"], context: oldContext, service: f.notifications)
        XCTAssertNil(stale); XCTAssertEqual(f.notificationEffects, 0)
        await current(); await f.waitForWrites(1)
        XCTAssertEqual(f.settings.map(\.categories), [["culture"]])
        XCTAssertEqual(f.profileWrites.first?.uid, "B")
        XCTAssertEqual(f.backendTokens.last?.1, .account("B"))
    }

    func testReentrantProviderGetterKeepsNewerCapturedChoiceInsteadOfOuterChoice() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        var newer: (@MainActor () async -> Void)?
        f.providerHook = {
            f.providerHook = nil
            newer = f.choose(Fixture.preferences(podcasts: true), ids: ["culture"])
        }
        let outer = f.choose(Fixture.preferences(), ids: ["music"])
        XCTAssertNil(outer); XCTAssertEqual(f.notificationEffects, 0)
        let operation = try XCTUnwrap(newer); await operation(); await f.waitForWrites(1)
        XCTAssertEqual(f.settings.map(\.categories), [["culture"]])
    }

    func testProfileSavePublicationCannotActivateOldChoiceAfterReplacementOrAccountChange() async throws {
        for replaceChoice in [false, true] {
            let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
            let old = try XCTUnwrap(f.choose(Fixture.preferences(podcasts: true), ids: ["music"]))
            var changed = false, replacement: (@MainActor () async -> Void)?
            let observation = f.state.objectWillChange.sink {
                guard !changed else { return }; changed = true
                if replaceChoice { replacement = f.choose(Fixture.preferences(), ids: ["culture"]) }
                else { f.select("B"); f.select("A") }
            }
            await old()
            XCTAssertTrue(changed); XCTAssertEqual(f.notificationEffects, 0); XCTAssertTrue(f.profileWrites.isEmpty)
            if replaceChoice {
                let operation = try XCTUnwrap(replacement); await operation(); await f.waitForWrites(1)
                XCTAssertEqual(f.settings.map(\.categories), [["culture"]])
            } else { XCTAssertNil(f.manager.currentUser) }
            withExtendedLifetime(observation) {}
        }
    }

    func testLateAuthorizationAfterAccountRoundTripCannotContinueToTokenOrTopics() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        f.authorizationStatus = .notDetermined; f.holdAuthorization = true; f.existingToken = nil
        let operation = try XCTUnwrap(f.choose()), task = Task { await operation() }
        await f.authorization.waitForStarts(1)
        let persistedBefore = f.settings.count, categoryWrites = f.categories.count
        f.select("B"); f.select("A"); await loaded(f, name: "Ny konto")
        f.authorization.finish(0, .success(true)); await task.value
        XCTAssertEqual(f.settings.count, persistedBefore); XCTAssertEqual(f.categories.count, categoryWrites)
        XCTAssertEqual(f.registrations, 0); XCTAssertEqual(f.tokenFetches, 0); XCTAssertTrue(f.topics.isEmpty)
        XCTAssertTrue(f.backendTokens.isEmpty); XCTAssertTrue(f.accountTokens.isEmpty)
        XCTAssertFalse(f.notifications.isAuthorized)
    }

    func testCancelledHeldTokenCannotPersistOrPublishLateTokenAndCallbacks() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        f.existingToken = nil; f.holdToken = true
        let operation = try XCTUnwrap(f.choose()), task = Task { await operation() }
        await f.token.waitForStarts(1)
        XCTAssertGreaterThan(f.registrations, 0)
        task.cancel()
        f.token.finish(0, .success("late-token-for-old-choice")); await task.value
        XCTAssertTrue(f.persistedTokens.isEmpty); XCTAssertNil(f.notifications.fcmToken)
        XCTAssertTrue(f.topics.isEmpty); XCTAssertTrue(f.accountTokens.isEmpty); XCTAssertTrue(f.backendTokens.isEmpty)
        XCTAssertFalse(f.token.guards[0]())
    }

    func testReplacementWhileAuthorizationWaitsKeepsLatestOffSettingsAndDiagnostics() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        f.authorizationStatus = .notDetermined; f.holdAuthorization = true
        let first = try XCTUnwrap(f.choose()), old = Task { await first() }
        await f.authorization.waitForStarts(1)
        let disabled = Fixture.preferences(articles: false, podcasts: false)
        let latest = try XCTUnwrap(f.choose(disabled)); await latest()
        let summary = f.notifications.lastPushSyncSummary, topics = f.notifications.subscribedTopicsDescription
        let diagnosticCount = f.diagnostics.count, settingsCount = f.settings.count
        f.authorization.finish(0, .success(true)); await old.value
        XCTAssertEqual(f.settings.count, settingsCount); XCTAssertEqual(f.settings.last?.preferences, disabled)
        XCTAssertEqual(f.notifications.lastPushSyncSummary, summary)
        XCTAssertEqual(f.notifications.subscribedTopicsDescription, topics); XCTAssertEqual(f.diagnostics.count, diagnosticCount)
        XCTAssertTrue(f.backendTokens.isEmpty); XCTAssertTrue(f.accountTokens.isEmpty)
    }

    func testFreshProfileLoadInvalidatesCapturedChoiceEvenWithoutAnAccountChange() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let old = try XCTUnwrap(f.choose(Fixture.preferences(podcasts: true)))
        await loaded(f, name: "Ny serverprofil")
        let current = f.state.snapshot
        await old()
        XCTAssertEqual(f.state.snapshot, current); XCTAssertTrue(f.profileWrites.isEmpty)
        XCTAssertEqual(f.notificationEffects, 0)
    }

    func testOldTopicCallbackCannotPublishErrorAfterOwnerRoundTrip() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        f.holdTopicCompletions = true
        let operation = try XCTUnwrap(f.choose()); await operation(); await f.waitForWrites(1)
        let topic = try XCTUnwrap(f.topics.first)
        f.select(nil); f.select("A"); await loaded(f, name: "Ny A")
        let summary = f.notifications.lastPushSyncSummary, diagnosticCount = f.diagnostics.count
        XCTAssertFalse(topic.original())
        topic.complete(URLError(.networkConnectionLost))
        XCTAssertEqual(f.notifications.lastPushSyncSummary, summary); XCTAssertEqual(f.diagnostics.count, diagnosticCount)
    }

    func testCancelledTaskBeforeChoiceExecutionCannotWriteOrActivateAnything() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let operation = try XCTUnwrap(f.choose()), before = f.state.snapshot
        let task = Task { await operation() }
        task.cancel(); await task.value
        XCTAssertEqual(f.state.snapshot, before); XCTAssertTrue(f.profileWrites.isEmpty)
        XCTAssertEqual(f.notificationEffects, 0)
    }
}
