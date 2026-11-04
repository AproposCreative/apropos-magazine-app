import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual profile orchestration with held local providers. Startup denial is
/// independent of UID, so these cases also cover a gate closing in-place.
@MainActor
final class UserProfileCoordinatorStartupTests: XCTestCase {
    private typealias Coordinator = UserProfileCoordinator
    private enum Failure: Error { case offline }

    @MainActor private final class Lane<Input, Output> {
        private(set) var calls: [Input] = []
        private var pending: [Int: CheckedContinuation<Output, Error>] = [:]
        private var startWaiters: [(Int, XCTestExpectation)] = []
        private var finishWaiters: [(Int, XCTestExpectation)] = []
        private var finished = 0
        var active: Int { pending.count }
        func perform(_ input: Input) async throws -> Output {
            defer {
                finished += 1
                let ready = finishWaiters.filter { $0.0 <= finished }
                finishWaiters.removeAll { $0.0 <= finished }; ready.forEach { $0.1.fulfill() }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let index = calls.count; calls.append(input); pending[index] = continuation
                let ready = startWaiters.filter { $0.0 <= calls.count }
                startWaiters.removeAll { $0.0 <= calls.count }; ready.forEach { $0.1.fulfill() }
            }
        }
        func waitForStarts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if calls.count >= count { return }
            let expectation = XCTestExpectation(description: "Profile effect started")
            startWaiters.append((count, expectation))
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func waitForReturns(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if finished >= count { return }
            let expectation = XCTestExpectation(description: "Physical profile effect returned")
            finishWaiters.append((count, expectation))
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func finish(_ index: Int, _ value: Result<Output, Error>) { pending.removeValue(forKey: index)?.resume(with: value) }
        func close() {
            let held = Array(pending.values); pending.removeAll()
            held.forEach { $0.resume(throwing: Failure.offline) }
        }
    }
    @MainActor private final class Harness {
        struct Read { let seed: UserProfile; let source: Coordinator.ReadSource; let guardOriginal: Coordinator.Guard }
        struct Write { let profile: UserProfile; let guardOriginal: Coordinator.Guard }
        struct Followup { let uid: String; let guardOriginal: Coordinator.Guard }
        let state = UserProfileState()
        let canonical = CanonicalSessionState()
        let reads = Lane<Read, Coordinator.ReadResult>()
        let writes = Lane<Write, Void>()
        var providerUID: String? = "A"
        var permits = true
        var capturable = true
        var captures = 0, identityLookups = 0
        var onCapture: (() -> Void)?
        var onIdentity: (() -> Void)?
        var onRead: (() -> Void)?
        var onWrite: (() -> Void)?
        var onSubscribe: (() -> Void)?
        var onUnsubscribe: (() -> Void)?
        var onFCM: (() -> Void)?
        var subscribed: [String] = [], unsubscribed: [String] = [], fcm: [String] = []
        var subscribeCalls: [Followup] = [], unsubscribeCalls: [Followup] = [], fcmCalls: [Followup] = []
        lazy var coordinator = Coordinator(state: state, effects: .init(capturePermission: { [weak self] in
            guard let self else { return nil }
            self.captures += 1
            let original = self.canonical.contextTicket()
            self.onCapture?()
            guard self.capturable else { return nil }
            return { [weak self] in self?.permits == true && self?.canonical.isCurrent(original) == true }
        }, identity: { [weak self] in
            guard let self else { return .init(actualUID: nil, canonicalUID: nil) }
            self.identityLookups += 1
            let original = Coordinator.Identity(actualUID: self.providerUID, canonicalUID: self.canonical.snapshot.userID)
            self.onIdentity?()
            return original
        }, read: { [weak self] seed, source, _, original in
            guard let self else { throw CancellationError() }
            self.onRead?()
            guard original() else { throw CancellationError() }
            return try await self.reads.perform(.init(seed: seed, source: source, guardOriginal: original))
        }, write: { [weak self] profile, _, original in
            guard let self else { throw CancellationError() }
            self.onWrite?()
            guard original() else { throw CancellationError() }
            try await self.writes.perform(.init(profile: profile, guardOriginal: original))
        }, subscribe: { [weak self] profile, original in
            guard let self else { return }
            self.subscribeCalls.append(.init(uid: profile.uid, guardOriginal: original))
            self.onSubscribe?()
            if original() { self.subscribed.append(profile.uid) }
        }, unsubscribe: { [weak self] profile, original in
            guard let self else { return }
            self.unsubscribeCalls.append(.init(uid: profile.uid, guardOriginal: original))
            self.onUnsubscribe?()
            if original() { self.unsubscribed.append(profile.uid) }
        }, updateFCM: { [weak self] uid, original in
            guard let self else { return }
            self.fcmCalls.append(.init(uid: uid, guardOriginal: original))
            self.onFCM?()
            if original() { self.fcm.append(uid) }
        }))
        init(started: Bool = true) {
            select("A")
            if started { coordinator.start() }
        }
        func select(_ uid: String?) {
            providerUID = uid
            canonical.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
            coordinator.changeAccountContext(userID: uid)
        }
        func close() {
            permits = false; onCapture = nil; onIdentity = nil; onRead = nil; onWrite = nil
            onSubscribe = nil; onUnsubscribe = nil; onFCM = nil
            coordinator.suspendForAccountChange(); reads.close(); writes.close()
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func profile(_ uid: String = "A", name: String = "Læser") -> UserProfile {
        UserProfile(uid: uid, email: "reader@example.invalid", displayName: name, photoURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
            favoriteCategories: ["culture"], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
            readArticles: [], bookmarkedArticles: [], readingProgress: [:])
    }
    private func load(_ h: Harness) async {
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.reads.finish(0, .success(.init(profile: profile(), isFromCache: false)))
        await h.reads.waitForReturns(1)
        XCTAssertTrue(h.state.snapshot.loaded)
    }

    func testClosedCaptureDoesNotReadIdentityPublishLoadingOrStartAnyEffect() {
        for noCapture in [true, false] {
            let h = Harness(); defer { h.close() }
            if noCapture { h.capturable = false } else { h.permits = false }
            let before = h.state.snapshot
            h.coordinator.load(profile()); XCTAssertNil(h.coordinator.save(profile()))
            XCTAssertEqual(h.state.snapshot, before); XCTAssertEqual(h.identityLookups, 0)
            XCTAssertTrue(h.reads.calls.isEmpty); XCTAssertTrue(h.writes.calls.isEmpty)
            XCTAssertTrue(h.subscribed.isEmpty); XCTAssertTrue(h.fcm.isEmpty)
        }
    }
    func testClosedParentPermissionDoesNotCaptureRuntimeAuthority() {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile(), stillCurrent: { false })
        XCTAssertNil(h.coordinator.save(profile(), stillCurrent: { false }))
        XCTAssertEqual(h.captures, 0); XCTAssertEqual(h.identityLookups, 0)
        XCTAssertFalse(h.state.snapshot.isLoading)
    }
    func testCaptureHookNestedLoadKeepsNewerIntent() async {
        let h = Harness(); defer { h.close() }
        h.onCapture = { [unowned h] in h.onCapture = nil; h.coordinator.load(self.profile(name: "Ny")) }
        h.coordinator.load(profile(name: "Gammel")); await h.reads.waitForStarts(1)
        XCTAssertEqual(h.reads.calls.count, 1); XCTAssertEqual(h.reads.calls[0].seed.displayName, "Ny")
        h.reads.finish(0, .success(.init(profile: profile(name: "Ny"), isFromCache: false)))
        await h.reads.waitForReturns(1); XCTAssertEqual(h.state.snapshot.profile?.displayName, "Ny")
    }
    func testCaptureHookNestedSaveKeepsNewerEdit() async {
        let h = Harness(); defer { h.close() }; await load(h)
        h.onCapture = { [unowned h] in h.onCapture = nil; h.coordinator.save(self.profile(name: "Ny")) }
        XCTAssertNil(h.coordinator.save(profile(name: "Gammel")))
        await h.writes.waitForStarts(1)
        XCTAssertEqual(h.writes.calls[0].profile.displayName, "Ny")
        XCTAssertEqual(h.state.snapshot.profile?.displayName, "Ny")
    }
    func testIdentityHookPermissionDenialDoesNotBeginLoad() {
        let h = Harness(); defer { h.close() }
        h.onIdentity = { [unowned h] in h.onIdentity = nil; h.permits = false }
        h.coordinator.load(profile())
        XCTAssertFalse(h.state.snapshot.isLoading); XCTAssertTrue(h.reads.calls.isEmpty)
    }
    func testPermissionClosingInsideReadEffectPreventsPhysicalProviderStart() async {
        let h = Harness(); defer { h.close() }
        let attempted = XCTestExpectation(description: "Original read guard reaches the adapter")
        h.onRead = { [unowned h] in h.permits = false; attempted.fulfill() }
        h.coordinator.load(profile())
        let result = await XCTWaiter.fulfillment(of: [attempted], timeout: 3)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(h.reads.calls.isEmpty); XCTAssertFalse(h.state.snapshot.isLoading)
        XCTAssertNil(h.state.snapshot.errorMessage); XCTAssertTrue(h.subscribed.isEmpty)
    }
    func testPermissionClosingInsideWriteEffectPreventsPhysicalProviderStart() async {
        let h = Harness(); defer { h.close() }; await load(h); h.fcm.removeAll()
        let attempted = XCTestExpectation(description: "Original write guard reaches the adapter")
        h.onWrite = { [unowned h] in h.permits = false; attempted.fulfill() }
        h.coordinator.save(profile(name: "Lokal ændring"))
        let result = await XCTWaiter.fulfillment(of: [attempted], timeout: 3)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(h.writes.calls.isEmpty); XCTAssertFalse(h.coordinator.activity.saving)
        XCTAssertNil(h.state.snapshot.errorMessage); XCTAssertTrue(h.fcm.isEmpty)
    }
    func testWillChangePermissionDenialDoesNotAssignLoadingOrStartProvider() {
        let h = Harness(); defer { h.close() }
        let observer = h.state.objectWillChange.sink { h.permits = false }
        h.coordinator.load(profile())
        XCTAssertFalse(h.state.snapshot.isLoading); XCTAssertTrue(h.reads.calls.isEmpty)
        withExtendedLifetime(observer) {}
    }
    func testPostBeginPublicationDenialRetiresOnlyThatLoadingState() {
        let h = Harness(); defer { h.close() }
        let observer = h.state.changes.sink { if $0.isLoading { h.permits = false } }
        h.coordinator.load(profile())
        XCTAssertFalse(h.state.snapshot.isLoading); XCTAssertNil(h.state.snapshot.errorMessage)
        XCTAssertFalse(h.coordinator.activity.loading); XCTAssertTrue(h.reads.calls.isEmpty)
        withExtendedLifetime(observer) {}
    }
    func testWillChangeDenialDuringReadCompletionCannotAssignProfileOrRunFollowups() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        let observer = h.state.objectWillChange.sink { h.permits = false }
        h.reads.finish(0, .success(.init(profile: profile(), isFromCache: false)))
        await h.reads.waitForReturns(1)
        XCTAssertNil(h.state.snapshot.profile); XCTAssertFalse(h.state.snapshot.isLoading)
        XCTAssertTrue(h.subscribed.isEmpty); XCTAssertTrue(h.fcm.isEmpty); XCTAssertTrue(h.writes.calls.isEmpty)
        withExtendedLifetime(observer) {}
    }
    func testDeniedHeldReadKeepsPhysicalSlotUntilReturnAndDenialCannotRevive() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.permits = false; XCTAssertFalse(h.reads.calls[0].guardOriginal()); h.permits = true
        XCTAssertEqual(h.coordinator.activity.activeLoadCount, 1)
        h.reads.finish(0, .success(.init(profile: profile(), isFromCache: false)))
        await h.reads.waitForReturns(1)
        XCTAssertNil(h.state.snapshot.profile); XCTAssertFalse(h.state.snapshot.isLoading)
        XCTAssertTrue(h.subscribed.isEmpty); XCTAssertTrue(h.fcm.isEmpty)
        h.coordinator.load(profile()); await h.reads.waitForStarts(2)
        XCTAssertTrue(h.reads.calls[1].guardOriginal())
    }
    func testParentDenialLatchesAcrossDelayedReadResult() async {
        let h = Harness(); defer { h.close() }; var parent = true
        h.coordinator.load(profile(), stillCurrent: { parent }); await h.reads.waitForStarts(1)
        parent = false; XCTAssertFalse(h.reads.calls[0].guardOriginal()); parent = true
        h.reads.finish(0, .success(.init(profile: profile(), isFromCache: false)))
        await h.reads.waitForReturns(1)
        XCTAssertNil(h.state.snapshot.profile); XCTAssertTrue(h.subscribed.isEmpty)
    }
    func testCacheMissDoesNotStartServerFallbackAfterOriginalPermissionRevocation() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.permits = false
        h.reads.finish(0, .success(.init(profile: nil, isFromCache: true)))
        await h.reads.waitForReturns(1)
        XCTAssertEqual(h.reads.calls.count, 1); XCTAssertTrue(h.writes.calls.isEmpty)
        XCTAssertNil(h.state.snapshot.profile); XCTAssertFalse(h.state.snapshot.isLoading)
    }
    func testFallbackAndDefaultWriteReuseOriginalPermissionWithoutRecapture() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.reads.finish(0, .success(.init(profile: nil, isFromCache: true))); await h.reads.waitForStarts(2)
        if case .server = h.reads.calls[1].source {} else { XCTFail("Expected explicit server fallback") }
        h.reads.finish(1, .success(.init(profile: nil, isFromCache: false))); await h.writes.waitForStarts(1)
        XCTAssertEqual(h.captures, 1); XCTAssertEqual(h.writes.calls[0].profile.uid, "A")
        h.permits = false; XCTAssertFalse(h.writes.calls[0].guardOriginal()); h.permits = true
        h.writes.finish(0, .success(())); await h.writes.waitForReturns(1)
        XCTAssertTrue(h.fcm.isEmpty); XCTAssertEqual(h.captures, 1)
    }
    func testTopicHookDenialSuppressesDefaultCreationAndFCM() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.onSubscribe = { [unowned h] in h.permits = false }
        h.reads.finish(0, .success(.init(profile: nil, isFromCache: false))); await h.reads.waitForReturns(1)
        XCTAssertTrue(h.subscribed.isEmpty); XCTAssertTrue(h.writes.calls.isEmpty); XCTAssertTrue(h.fcm.isEmpty)
        XCTAssertEqual(h.captures, 1)
    }
    func testFCMHookDenialRejectsFollowupAtItsPhysicalBoundary() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.onFCM = { [unowned h] in h.permits = false }
        h.reads.finish(0, .success(.init(profile: profile(), isFromCache: false))); await h.reads.waitForReturns(1)
        XCTAssertEqual(h.subscribed, ["A"]); XCTAssertTrue(h.fcm.isEmpty)
        h.permits = true; XCTAssertFalse(h.fcmCalls[0].guardOriginal())
    }
    func testAccountABAReturnCannotAdoptOldReadOrItsFollowups() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1)
        h.select(nil); h.select("A")
        h.reads.finish(0, .success(.init(profile: profile(), isFromCache: false))); await h.reads.waitForReturns(1)
        XCTAssertNil(h.state.snapshot.profile); XCTAssertTrue(h.subscribed.isEmpty); XCTAssertTrue(h.fcm.isEmpty)
        XCTAssertFalse(h.reads.calls[0].guardOriginal())
    }
    func testLateFailureDoesNotPublishAfterPermissionClosed() async {
        let h = Harness(); defer { h.close() }
        h.coordinator.load(profile()); await h.reads.waitForStarts(1); h.permits = false
        h.reads.finish(0, .failure(Failure.offline)); await h.reads.waitForReturns(1)
        XCTAssertNil(h.state.snapshot.errorMessage); XCTAssertFalse(h.state.snapshot.isLoading)
    }
    func testSaveGateDenialBeforeWillChangePreservesPriorProfile() async {
        let h = Harness(); defer { h.close() }; await load(h)
        let previous = h.state.snapshot.profile
        let observer = h.state.objectWillChange.sink { h.permits = false }
        XCTAssertNil(h.coordinator.save(profile(name: "Afvist")))
        XCTAssertEqual(h.state.snapshot.profile, previous); XCTAssertTrue(h.writes.calls.isEmpty)
        withExtendedLifetime(observer) {}
    }
    func testDeniedPhysicalSaveDoesNotReleaseSlotBeforeCallbackOrSendFCM() async {
        let h = Harness(); defer { h.close() }; await load(h); h.fcm.removeAll()
        h.coordinator.save(profile(name: "Første")); await h.writes.waitForStarts(1)
        h.permits = false; XCTAssertFalse(h.writes.calls[0].guardOriginal()); h.permits = true
        h.coordinator.save(profile(name: "Ny"))
        XCTAssertEqual(h.writes.calls.count, 1); XCTAssertTrue(h.coordinator.activity.saving)
        h.writes.finish(0, .failure(Failure.offline)); await h.writes.waitForStarts(2)
        XCTAssertEqual(h.writes.calls[1].profile.displayName, "Ny"); XCTAssertNil(h.state.snapshot.errorMessage)
        XCTAssertTrue(h.fcm.isEmpty)
        h.writes.finish(1, .success(())); await h.writes.waitForReturns(2)
        XCTAssertEqual(h.fcm, ["A"])
    }
    func testUnstartedPendingLoadDoesNotStartWhenItsOriginalPermissionWasDenied() {
        let h = Harness(started: false); defer { h.close() }
        h.coordinator.load(profile()); XCTAssertTrue(h.coordinator.activity.pendingLoad)
        h.permits = false; h.coordinator.start()
        XCTAssertTrue(h.reads.calls.isEmpty); XCTAssertFalse(h.state.snapshot.isLoading)
        h.permits = true; h.coordinator.start(); XCTAssertTrue(h.reads.calls.isEmpty)
    }
    func testCleanupCallbackRetainsOriginalCurrentContextAndNeverRecaptures() async {
        let h = Harness(); defer { h.close() }; await load(h)
        h.select("B"); h.coordinator.load(profile("B")); await h.reads.waitForStarts(2)
        XCTAssertEqual(h.unsubscribed, ["A"])
        guard let cleanup = h.unsubscribeCalls.first else { XCTFail("Expected cleanup admission"); return }
        XCTAssertTrue(cleanup.guardOriginal()); let captures = h.captures
        h.select("C"); XCTAssertFalse(cleanup.guardOriginal())
        h.select("B"); XCTAssertFalse(cleanup.guardOriginal())
        XCTAssertEqual(h.captures, captures)
    }
    func testCleanupHookChangingAccountCannotAdmitOldCleanupOrPendingRead() async {
        let h = Harness(); defer { h.close() }; await load(h)
        h.select("B")
        h.onUnsubscribe = { [unowned h] in h.onUnsubscribe = nil; h.select("C") }
        h.coordinator.load(profile("B"))
        XCTAssertTrue(h.unsubscribed.isEmpty); XCTAssertEqual(h.reads.calls.count, 1)
        XCTAssertEqual(h.state.snapshot.context, .account("C")); XCTAssertNil(h.state.snapshot.profile)
        XCTAssertFalse(h.unsubscribeCalls[0].guardOriginal())
    }
}
