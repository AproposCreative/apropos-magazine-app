import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual UserManager -> coordinator -> state. Only provider effects are held
/// locally; permission comes from the real SDK-startup/canonical composition.
@MainActor
final class UserManagerStartupIntegrationTests: XCTestCase {
    private typealias Coordinator = UserProfileCoordinator
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract
    private enum Failure: Error { case offline }

    @MainActor private final class Lane<Input, Output> {
        private(set) var calls: [Input] = []
        private var pending: [Int: CheckedContinuation<Output, Error>] = [:]
        private var starts: [(Int, XCTestExpectation)] = []
        private var returns: [(Int, XCTestExpectation)] = []
        private var returned = 0
        var active: Int { pending.count }
        func perform(_ input: Input) async throws -> Output {
            defer {
                returned += 1
                let ready = returns.filter { $0.0 <= returned }
                returns.removeAll { $0.0 <= returned }; ready.forEach { $0.1.fulfill() }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let index = calls.count; calls.append(input); pending[index] = continuation
                let ready = starts.filter { $0.0 <= calls.count }
                starts.removeAll { $0.0 <= calls.count }; ready.forEach { $0.1.fulfill() }
            }
        }
        func waitForStarts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if calls.count >= count { return }
            let value = XCTestExpectation(description: "Actual manager provider starts \(count)")
            starts.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func waitForReturns(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if returned >= count { return }
            let value = XCTestExpectation(description: "Actual manager provider returns \(count)")
            returns.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func finish(_ index: Int, _ result: Result<Output, Error>) {
            pending.removeValue(forKey: index)?.resume(with: result)
        }
        func close() {
            let held = Array(pending.values); pending.removeAll()
            held.forEach { $0.resume(throwing: Failure.offline) }
        }
    }

    @MainActor private final class Fixture {
        struct Read {
            let seed: UserProfile
            let source: Coordinator.ReadSource
            let original: Coordinator.Guard
        }
        struct Write { let profile: UserProfile; let original: Coordinator.Guard }
        struct Followup { let uid: String; let original: Coordinator.Guard }
        let state = UserProfileState()
        let canonical = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        let reads = Lane<Read, Coordinator.ReadResult>()
        let writes = Lane<Write, Void>()
        var providerUID: String?
        var seed: UserProfile?
        var captures = 0, identityReads = 0, seedReads = 0, sdkStarts = 0
        var onSeed: (() -> Void)?
        var onProvider: (() -> Void)?
        var onSubscribe: (() -> Void)?
        var onFCM: (() -> Void)?
        var subscriptions: [String] = [], unsubscriptions: [String] = [], fcm: [String] = []
        var subscribeCalls: [Followup] = [], fcmCalls: [Followup] = []
        lazy var manager = UserManager(state: state, effects: effects,
            currentProfileSeed: { [weak self] in
                guard let self else { return nil }
                self.seedReads += 1; self.onSeed?(); return self.seed
            })
        private var effects: Coordinator.Effects {
            .init(capturePermission: { [weak self] in
                guard let self else { return nil }
                self.captures += 1
                return self.sdk.captureReaderWork(identity: self.canonical, actualUserID: { [weak self] in
                    guard let self else { return nil }
                    self.onProvider?(); return self.providerUID
                })
            }, identity: { [weak self] in
                guard let self else { return .init(actualUID: nil, canonicalUID: nil) }
                self.identityReads += 1
                return .init(actualUID: self.providerUID, canonicalUID: self.canonical.snapshot.userID)
            }, read: { [weak self] seed, source, _, original in
                guard let self, original() else { throw CancellationError() }
                return try await self.reads.perform(.init(seed: seed, source: source, original: original))
            }, write: { [weak self] profile, _, original in
                guard let self, original() else { throw CancellationError() }
                try await self.writes.perform(.init(profile: profile, original: original))
            }, subscribe: { [weak self] profile, original in
                guard let self else { return }
                self.subscribeCalls.append(.init(uid: profile.uid, original: original))
                self.onSubscribe?()
                if original() { self.subscriptions.append(profile.uid) }
            }, unsubscribe: { [weak self] profile, original in
                guard let self else { return }
                if original() { self.unsubscriptions.append(profile.uid) }
            }, updateFCM: { [weak self] uid, original in
                guard let self else { return }
                self.fcmCalls.append(.init(uid: uid, original: original))
                self.onFCM?()
                if original() { self.fcm.append(uid) }
            })
        }
        init(guarded: Bool = false, uid: String? = "A") {
            sdk = guarded ? ReaderSDKStartupState() : .application
            providerUID = uid; seed = uid.map { Self.profile($0) }
            _ = canonical.adopt(uid.map(Self.session))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
        }
        static func profile(_ uid: String = "A", name: String = "Lokal læser") -> UserProfile {
            .init(uid: uid, email: uid + "@example.invalid", displayName: name, photoURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
                favoriteCategories: ["culture"], favoriteAuthors: ["local-author"],
                notificationPreferences: .init(), readingPreferences: .init(),
                readArticles: ["read-" + uid], bookmarkedArticles: ["saved-" + uid], readingProgress: ["read-" + uid: 0.5])
        }
        func start() {
            manager.changeAccountContext(userID: providerUID)
            manager.startObservingSession()
        }
        func select(_ uid: String?) {
            providerUID = uid; seed = uid.map { Self.profile($0) }
            _ = canonical.adopt(uid.map(Self.session))
            manager.changeAccountContext(userID: uid)
        }
        func close() {
            onSeed = nil; onProvider = nil; onSubscribe = nil; onFCM = nil
            manager.suspendForAccountChange(); reads.close(); writes.close()
        }
        func openGuardedStartup() async throws {
            let configuration = try Startup.Configuration(projectID: "local-profile-test", appID: "local-app",
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
            let start: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [weak self] _, admit in
                try admit(); self?.sdkStarts += 1
            }
            let startup = Startup(canonical: canonical, sdkState: sdk, configuration: configuration,
                readMarker: { nil }, readMembership: membership, verify: verify, startSDK: start,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await startup.start(context: canonical.contextTicket())
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func wait(_ state: UserProfileState, file: StaticString = #filePath, line: UInt = #line,
                      _ predicate: @escaping (UserProfileState.Snapshot) -> Bool) async {
        if predicate(state.snapshot) { return }
        let value = XCTestExpectation(description: "Committed manager profile state")
        var finished = false
        let observation = state.changes.sink { snapshot in
            if !finished && predicate(snapshot) { finished = true; value.fulfill() }
        }
        let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
        withExtendedLifetime(observation) {}
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
    private func load(_ f: Fixture, name: String = "Lokal læser") async {
        let profile = Fixture.profile(f.providerUID ?? "A", name: name), index = f.reads.calls.count
        f.manager.loadUserProfile(profile)
        await f.reads.waitForStarts(index + 1)
        f.reads.finish(index, .success(.init(profile: profile, isFromCache: false)))
        await wait(f.state) { $0.loaded && $0.profile?.displayName == name }
    }

    func testInertManagerAndClosedStartupRunNoProfileOrNotificationEffectsThenExplicitRetryWorks() async throws {
        let f = Fixture(guarded: true); defer { f.close() }
        _ = f.manager
        XCTAssertEqual(f.captures, 0); XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.seedReads, 0)
        f.start(); let original = f.manager.profileSnapshot
        f.manager.loadUserProfile(Fixture.profile()); f.manager.retryProfileLoad()
        XCTAssertNil(f.manager.saveUserProfile(Fixture.profile(name: "Afvist ændring")))
        XCTAssertEqual(f.manager.profileSnapshot, original); XCTAssertEqual(f.seedReads, 0)
        XCTAssertTrue(f.reads.calls.isEmpty); XCTAssertTrue(f.writes.calls.isEmpty)
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.unsubscriptions.isEmpty); XCTAssertTrue(f.fcm.isEmpty)
        try await f.openGuardedStartup()
        XCTAssertTrue(f.reads.calls.isEmpty, "Opening startup does not invent a profile load")
        f.manager.retryProfileLoad(); await f.reads.waitForStarts(1)
        f.reads.finish(0, .success(.init(profile: Fixture.profile(), isFromCache: false)))
        await wait(f.state) { $0.loaded }
        XCTAssertEqual(f.sdkStarts, 1); XCTAssertEqual(f.seedReads, 1)
        XCTAssertEqual(f.subscriptions, ["A"]); XCTAssertEqual(f.fcm, ["A"])
        f.manager.retryProfileLoad(); XCTAssertEqual(f.reads.calls.count, 1)
    }

    func testGuestAndUnstartedManagerNeverReadSeedOrStartAccountEffects() {
        for guarded in [false, true] {
            let f = Fixture(guarded: guarded, uid: nil); defer { f.close() }
            f.manager.loadUserProfile(Fixture.profile()); f.manager.retryProfileLoad()
            XCTAssertNil(f.manager.saveUserProfile(Fixture.profile())); XCTAssertEqual(f.captures, 0)
            f.start(); f.manager.loadUserProfile(Fixture.profile()); f.manager.retryProfileLoad()
            XCTAssertEqual(f.seedReads, 0); XCTAssertEqual(f.state.snapshot.context, .guest)
            XCTAssertTrue(f.reads.calls.isEmpty); XCTAssertTrue(f.writes.calls.isEmpty)
            XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.fcm.isEmpty)
        }
    }

    func testExplicitDeniedParentDoesNotCaptureOrPublishAndObservedDenialCannotReviveHeldRead() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        let before = f.state.snapshot, captures = f.captures
        f.manager.loadUserProfile(Fixture.profile(), stillCurrent: { false })
        XCTAssertEqual(f.state.snapshot, before); XCTAssertEqual(f.captures, captures)
        var allowed = true
        f.manager.loadUserProfile(Fixture.profile(), stillCurrent: { allowed })
        await f.reads.waitForStarts(1)
        let original = try XCTUnwrap(f.reads.calls.first).original
        allowed = false; XCTAssertFalse(original()); allowed = true
        XCTAssertFalse(original()); XCTAssertEqual(f.reads.active, 1)
        f.reads.finish(0, .success(.init(profile: nil, isFromCache: true)))
        await f.reads.waitForReturns(1); await wait(f.state) { !$0.isLoading }
        XCTAssertEqual(f.reads.calls.count, 1); XCTAssertNil(f.manager.currentUser)
        XCTAssertNil(f.manager.errorMessage); XCTAssertTrue(f.writes.calls.isEmpty)
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.fcm.isEmpty)
    }

    func testRetrySeedGetterAccountRoundTripCannotAdmitItsOriginalSeed() async {
        let f = Fixture(); defer { f.close() }; f.start()
        let generation = f.state.snapshot.generation
        f.onSeed = { f.onSeed = nil; f.select("B"); f.select("A") }
        f.manager.retryProfileLoad()
        XCTAssertNotEqual(f.state.snapshot.generation, generation)
        XCTAssertTrue(f.reads.calls.isEmpty); XCTAssertFalse(f.manager.isLoading)
        f.manager.retryProfileLoad(); await f.reads.waitForStarts(1)
        f.reads.finish(0, .success(.init(profile: Fixture.profile(), isFromCache: false)))
        await wait(f.state) { $0.loaded }
        XCTAssertEqual(f.seedReads, 2); XCTAssertEqual(f.subscriptions, ["A"])
    }

    func testRetrySeedGetterNestedLoadKeepsTheNewerSameOwnerRequest() async {
        let f = Fixture(); defer { f.close() }; f.start()
        let newer = Fixture.profile(name: "Ny indlejret profil")
        f.onSeed = { f.onSeed = nil; f.manager.loadUserProfile(newer) }
        f.manager.retryProfileLoad(); await f.reads.waitForStarts(1)
        XCTAssertEqual(f.reads.calls.first?.seed, newer)
        f.reads.finish(0, .success(.init(profile: newer, isFromCache: false)))
        await wait(f.state) { $0.loaded }
        XCTAssertEqual(f.manager.currentUser, newer); XCTAssertEqual(f.reads.calls.count, 1)
    }

    func testFirstPermissionGetterReentryCannotReplaceNewerManagerEntry() async {
        let f = Fixture(); defer { f.close() }; f.start()
        let newer = Fixture.profile(name: "Nyeste tilladte profil")
        f.onProvider = { f.onProvider = nil; f.manager.loadUserProfile(newer) }
        f.manager.loadUserProfile(Fixture.profile(name: "Gammel ydre profil"))
        await f.reads.waitForStarts(1)
        XCTAssertEqual(f.reads.calls.first?.seed, newer)
        f.reads.finish(0, .success(.init(profile: newer, isFromCache: false)))
        await wait(f.state) { $0.loaded }
        XCTAssertEqual(f.manager.currentUser, newer); XCTAssertEqual(f.reads.calls.count, 1)
    }

    func testCacheMissUsesServerProofAndDefaultProfileFCMWaitsForPhysicalSave() async {
        let f = Fixture(); defer { f.close() }; f.start()
        f.manager.loadUserProfile(Fixture.profile()); await f.reads.waitForStarts(1)
        f.reads.finish(0, .success(.init(profile: nil, isFromCache: true)))
        await f.reads.waitForStarts(2)
        if case .server = f.reads.calls[1].source {} else { XCTFail("Cache absence needs explicit server proof") }
        XCTAssertNil(f.manager.currentUser); XCTAssertTrue(f.writes.calls.isEmpty)
        f.reads.finish(1, .success(.init(profile: nil, isFromCache: false)))
        await f.writes.waitForStarts(1)
        XCTAssertEqual(f.writes.calls.first?.profile, Fixture.profile())
        XCTAssertEqual(f.subscriptions, ["A"]); XCTAssertTrue(f.fcm.isEmpty)
        XCTAssertEqual(f.writes.active, 1)
        f.writes.finish(0, .success(())); await f.writes.waitForReturns(1)
        XCTAssertEqual(f.fcm, ["A"]); XCTAssertTrue(f.manager.profileSnapshot.writeReady)
    }

    func testReadFailureRetryUsesCurrentProviderSeedAndOnlySuccessEnablesSave() async {
        let f = Fixture(); defer { f.close() }; f.start()
        f.manager.loadUserProfile(Fixture.profile()); await f.reads.waitForStarts(1)
        f.reads.finish(0, .failure(Failure.offline))
        await wait(f.state) { !$0.isLoading && $0.errorMessage != nil }
        XCTAssertNil(f.manager.saveUserProfile(Fixture.profile())); XCTAssertTrue(f.writes.calls.isEmpty)
        let refreshed = Fixture.profile(name: "Aktuel providerprofil"); f.seed = refreshed
        f.manager.retryProfileLoad(); await f.reads.waitForStarts(2)
        XCTAssertEqual(f.reads.calls[1].seed, refreshed)
        f.reads.finish(1, .success(.init(profile: refreshed, isFromCache: false)))
        await wait(f.state) { $0.loaded && $0.errorMessage == nil }
        XCTAssertEqual(f.manager.currentUser, refreshed)
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Gem faktisk ændring")))
        await f.writes.waitForStarts(1); f.writes.finish(0, .success(()))
        await f.writes.waitForReturns(1); XCTAssertEqual(f.fcm, ["A", "A"])
    }

    func testHeldAccountRoundTripCannotApplyOldProfileOrItsDerivedEffects() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        f.manager.loadUserProfile(Fixture.profile(name: "Gammel A")); await f.reads.waitForStarts(1)
        let original = try XCTUnwrap(f.reads.calls.first).original
        f.select("B"); f.select("A")
        XCTAssertFalse(original()); XCTAssertEqual(f.reads.active, 1)
        let current = Fixture.profile(name: "Ny A"); f.seed = current
        f.manager.retryProfileLoad(); await f.reads.waitForStarts(2)
        XCTAssertEqual(f.reads.active, 2, "The stale physical read stays held while the new owner can load")
        f.reads.finish(1, .success(.init(profile: current, isFromCache: false)))
        await wait(f.state) { $0.loaded }
        let accepted = f.manager.profileSnapshot
        f.reads.finish(0, .success(.init(profile: nil, isFromCache: false)))
        await f.reads.waitForReturns(2)
        XCTAssertEqual(f.manager.profileSnapshot, accepted); XCTAssertEqual(f.manager.currentUser, current)
        XCTAssertEqual(f.subscriptions, ["A"]); XCTAssertEqual(f.fcm, ["A"]); XCTAssertTrue(f.writes.calls.isEmpty)
    }

    func testGuardedStartupPermissionDoesNotTransferToSameUIDAfterAccountRoundTrip() async throws {
        let f = Fixture(guarded: true); defer { f.close() }; f.start()
        try await f.openGuardedStartup()
        f.manager.loadUserProfile(Fixture.profile()); await f.reads.waitForStarts(1)
        f.select("B"); f.select("A")
        f.manager.retryProfileLoad(); XCTAssertEqual(f.reads.calls.count, 1)
        f.reads.finish(0, .success(.init(profile: Fixture.profile(), isFromCache: false)))
        await f.reads.waitForReturns(1)
        XCTAssertFalse(f.sdk.permitsReaderServices(identity: f.canonical))
        XCTAssertNil(f.manager.currentUser); XCTAssertFalse(f.manager.isLoading)
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.writes.calls.isEmpty); XCTAssertTrue(f.fcm.isEmpty)
    }

    func testTopicReentryRejectsDefaultSaveAndFCMAtTheActualEffectBoundary() async {
        let f = Fixture(); defer { f.close() }; f.start()
        f.onSubscribe = { f.onSubscribe = nil; f.select("B"); f.select("A") }
        f.manager.loadUserProfile(Fixture.profile()); await f.reads.waitForStarts(1)
        f.reads.finish(0, .success(.init(profile: nil, isFromCache: false)))
        await f.reads.waitForReturns(1)
        XCTAssertEqual(f.subscribeCalls.count, 1); XCTAssertTrue(f.subscriptions.isEmpty)
        XCTAssertTrue(f.writes.calls.isEmpty); XCTAssertTrue(f.fcm.isEmpty); XCTAssertNil(f.manager.currentUser)
        await load(f)
        XCTAssertEqual(f.subscriptions, ["A"]); XCTAssertEqual(f.fcm, ["A"])
    }

    func testHeldSaveAndFCMCallbacksKeepOriginalAccountAfterProviderMismatch() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await load(f)
        f.manager.saveUserProfile(Fixture.profile(name: "Ændret profil"))
        await f.writes.waitForStarts(1)
        let original = try XCTUnwrap(f.writes.calls.first).original
        f.providerUID = "B"; XCTAssertFalse(original()); f.providerUID = "A"
        XCTAssertFalse(original()); XCTAssertEqual(f.writes.active, 1)
        f.writes.finish(0, .failure(Failure.offline)); await f.writes.waitForReturns(1)
        XCTAssertNil(f.manager.errorMessage); XCTAssertEqual(f.fcm, ["A"])
        let oldFCM = try XCTUnwrap(f.fcmCalls.first).original
        f.select("B"); f.select("A"); XCTAssertFalse(oldFCM())
        XCTAssertEqual(f.fcm, ["A"], "No stale save result or delayed FCM callback gains new authority")
    }

    func testNotificationRevocationRetiresLoadingAndCannotCancelReplacement() async {
        for replace in [false, true] {
            let f = Fixture(); defer { f.close() }; f.start()
            var allowed = true, changed = false
            let observation = f.manager.profileChanges.sink { snapshot in
                if !changed && snapshot.isLoading {
                    changed = true; allowed = false
                    if replace { f.manager.loadUserProfile(Fixture.profile(name: "Ny efter notifikation")) }
                }
            }
            f.manager.loadUserProfile(Fixture.profile(name: "Afvist ydre"), stillCurrent: { allowed })
            XCTAssertTrue(changed)
            if replace {
                await f.reads.waitForStarts(1)
                XCTAssertEqual(f.reads.calls.first?.seed.displayName, "Ny efter notifikation")
                f.reads.finish(0, .success(.init(profile: Fixture.profile(name: "Ny efter notifikation"), isFromCache: false)))
                await wait(f.state) { $0.loaded }
                XCTAssertEqual(f.manager.currentUser?.displayName, "Ny efter notifikation")
            } else {
                XCTAssertFalse(f.manager.isLoading); XCTAssertTrue(f.reads.calls.isEmpty)
                XCTAssertNil(f.manager.currentUser); XCTAssertNil(f.manager.errorMessage)
            }
            withExtendedLifetime(observation) {}
        }
    }

    func testReleasedManagerCannotStartItsAlreadyScheduledReadOrNotificationEffects() async {
        let state = UserProfileState(), canonical = CanonicalSessionState()
        let sdk = ReaderSDKStartupState.application
        _ = canonical.adopt(Fixture.session("A"))
        var reads = 0, writes = 0, notifications = 0
        let effects = Coordinator.Effects(capturePermission: {
            sdk.captureReaderWork(identity: canonical, actualUserID: { "A" })
        }, identity: { .init(actualUID: "A", canonicalUID: canonical.snapshot.userID) }, read: { _, _, _, _ in
            reads += 1; return .init(profile: Fixture.profile(), isFromCache: false)
        }, write: { _, _, _ in writes += 1 }, subscribe: { _, _ in notifications += 1 },
            unsubscribe: { _, _ in notifications += 1 }, updateFCM: { _, _ in notifications += 1 })
        var manager: UserManager? = UserManager(state: state, effects: effects, currentProfileSeed: { Fixture.profile() })
        weak var released = manager
        manager?.changeAccountContext(userID: "A"); manager?.startObservingSession()
        manager?.loadUserProfile(Fixture.profile())
        XCTAssertTrue(state.snapshot.isLoading); XCTAssertEqual(reads, 0)
        manager = nil
        XCTAssertNil(released, "The scheduled coordinator job must not keep its manager alive")
        await wait(state) { !$0.isLoading }
        XCTAssertEqual(reads, 0); XCTAssertEqual(writes, 0); XCTAssertEqual(notifications, 0)
        XCTAssertNil(state.snapshot.profile); XCTAssertNil(state.snapshot.errorMessage)
    }
}
