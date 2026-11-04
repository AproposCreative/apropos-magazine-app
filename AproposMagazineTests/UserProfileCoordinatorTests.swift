import Combine
import XCTest
@testable import Apropos

/// The production state/coordinator and actual UserProfile values. All provider
/// results are held in private lanes; no SDK, auth listener or notification runs.
@MainActor
final class UserProfileCoordinatorTests: XCTestCase {
    private func profile(_ uid: String, name: String? = nil) -> UserProfile {
        UserProfile(uid: uid, email: uid.lowercased() + "@example.test", displayName: name ?? "Læser " + uid,
            photoURL: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
            favoriteCategories: ["culture"], favoriteAuthors: ["author"], notificationPreferences: .init(), readingPreferences: .init(),
            readArticles: ["read-" + uid], bookmarkedArticles: ["saved-" + uid], readingProgress: ["read-" + uid: 0.5])
    }
    private func wait(_ state: UserProfileState, file: StaticString = #filePath, line: UInt = #line,
                      _ predicate: @escaping (UserProfileState.Snapshot) -> Bool) async {
        if predicate(state.snapshot) { return }
        let expectation = XCTestExpectation(description: "Accepted coherent profile state")
        var fulfilled = false
        let subscription = state.changes.sink { snapshot in
            if !fulfilled && predicate(snapshot) { fulfilled = true;expectation.fulfill() }
        }
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
    private func loaded(_ h: ProfileCoordinatorHarness, uid: String = "A", name: String? = nil) async {
        let count = h.reads.calls.count + 1, value = profile(uid, name: name)
        h.select(uid);h.coordinator.load(value);await h.reads.waitForStarts(count)
        h.reads.finish(count - 1, .success(.init(profile: value, isFromCache: false)))
        await wait(h.state) { $0.loaded && $0.profile?.uid == uid }
    }

    func testConstructorAndUnstartedUnknownContextNeverRunProviderEffects() {
        let h = ProfileCoordinatorHarness(started: false);defer { h.close() }
        XCTAssertEqual(h.identityReads, 0);XCTAssertTrue(h.reads.calls.isEmpty)
        h.coordinator.load(profile("A"));h.coordinator.save(profile("A"))
        XCTAssertTrue(h.reads.calls.isEmpty);XCTAssertTrue(h.writes.calls.isEmpty)
        h.coordinator.start();h.coordinator.load(profile("A"))
        XCTAssertEqual(h.state.snapshot.context, .unresolved)
        XCTAssertTrue(h.reads.calls.isEmpty);XCTAssertTrue(h.subscriptions.isEmpty);XCTAssertTrue(h.fcm.isEmpty)
    }
    func testCanonicalOwnerSwitchHidesOldProfileBeforeNewLoadListenerRuns() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        h.select("B")
        XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertNil(h.state.snapshot.profile)
        XCTAssertFalse(h.state.snapshot.loaded);XCTAssertFalse(h.state.snapshot.writeReady)
        XCTAssertEqual(h.reads.calls.count, 1, "Canonical invalidation needs no new read to hide old settings/history")
        h.coordinator.load(profile("B"));await h.reads.waitForStarts(2)
        XCTAssertNil(h.state.snapshot.profile);XCTAssertTrue(h.state.snapshot.isLoading)
        h.reads.finish(1, .success(.init(profile: profile("B"), isFromCache: false)))
        await wait(h.state) { $0.profile?.uid == "B" && $0.loaded }
        XCTAssertEqual(h.state.snapshot.profile?.readArticles, ["read-B"])
    }
    func testNewOwnerLoadsBeforeOldActualReadReturnsAndOldCallbackCannotReplaceIt() async {
        let h = ProfileCoordinatorHarness();defer { h.close() }
        h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        h.select("B");h.coordinator.load(profile("B"));await h.reads.waitForStarts(2)
        XCTAssertEqual(h.reads.activeCount, 2)
        h.reads.finish(1, .success(.init(profile: profile("B"), isFromCache: false)))
        await wait(h.state) { $0.loaded && $0.profile?.uid == "B" }
        XCTAssertEqual(h.reads.activeCount, 1, "A's real SDK read remains occupied while B is usable")
        h.reads.finish(0, .success(.init(profile: profile("A"), isFromCache: false)));await h.reads.waitForReturns(2)
        XCTAssertEqual(h.state.snapshot.profile?.uid, "B");XCTAssertEqual(h.subscriptions, ["B"])
        XCTAssertEqual(h.fcm, ["B"]);XCTAssertTrue(h.writes.calls.isEmpty)
    }
    func testSameUIDNewerLoadCanFinishFirstAndOldResultCannotReplaceItsProfile() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A")
        h.coordinator.load(profile("A", name: "Gammel"));await h.reads.waitForStarts(1)
        h.coordinator.load(profile("A", name: "Ny"));await h.reads.waitForStarts(2)
        h.reads.finish(1, .success(.init(profile: profile("A", name: "Ny"), isFromCache: false)))
        await wait(h.state) { $0.profile?.displayName == "Ny" && $0.loaded }
        h.reads.finish(0, .success(.init(profile: profile("A", name: "Gammel"), isFromCache: false)));await h.reads.waitForReturns(2)
        XCTAssertEqual(h.state.snapshot.profile?.displayName, "Ny");XCTAssertEqual(h.subscribedNames, ["Ny"])
    }
    func testFourActualReadsRemainBoundedAndOnlyLatestWaitingLoadStartsAfterSlotReturns() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A")
        for index in 0..<4 {
            h.coordinator.load(profile("A", name: "Startet \(index)"));await h.reads.waitForStarts(index + 1)
        }
        h.coordinator.load(profile("A", name: "Sprunget over"));h.coordinator.load(profile("A", name: "Seneste"))
        XCTAssertEqual(h.reads.calls.count, 4);XCTAssertEqual(h.coordinator.activity.activeLoadCount, 4)
        h.reads.finish(0, .success(.init(profile: profile("A", name: "Startet 0"), isFromCache: false)))
        await h.reads.waitForStarts(5)
        XCTAssertEqual(h.reads.calls[4].seed.displayName, "Seneste");XCTAssertEqual(h.coordinator.activity.activeLoadCount, 4)
        h.reads.finish(4, .success(.init(profile: profile("A", name: "Seneste"), isFromCache: false)))
        await wait(h.state) { $0.loaded && $0.profile?.displayName == "Seneste" }
        XCTAssertEqual(h.reads.activeCount, 3);XCTAssertEqual(h.subscribedNames, ["Seneste"])
    }
    func testHeldOldSaveCannotChangeNewOwnerErrorOrBypassActualWriteBarrier() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        h.coordinator.save(profile("A", name: "A ændret"));await h.writes.waitForStarts(1)
        await loaded(h, uid: "B")
        h.coordinator.save(profile("B", name: "B ændret"));XCTAssertEqual(h.writes.calls.count, 1)
        h.writes.finish(0, .failure(ProfileCoordinatorFailure.provider));await h.writes.waitForStarts(2)
        XCTAssertEqual(h.writes.calls[1].profile.uid, "B");XCTAssertNil(h.state.snapshot.errorMessage)
        h.writes.finish(1, .success(()))
        await wait(h.state) { $0.profile?.displayName == "B ændret" && $0.errorMessage == nil }
        XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertEqual(h.fcm.filter { $0 == "A" }.count, 1, "Only the original successful A load may emit A FCM")
    }
    func testNewerSaveCoalescesPendingAndOldFailureCannotOverwriteLatestProfile() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        h.coordinator.save(profile("A", name: "Første"));await h.writes.waitForStarts(1)
        h.coordinator.save(profile("A", name: "Mellem"));h.coordinator.save(profile("A", name: "Seneste"))
        XCTAssertEqual(h.writes.calls.count, 1);XCTAssertEqual(h.state.snapshot.profile?.displayName, "Seneste")
        h.writes.finish(0, .failure(ProfileCoordinatorFailure.provider));await h.writes.waitForStarts(2)
        XCTAssertEqual(h.writes.calls[1].profile.displayName, "Seneste");XCTAssertNil(h.state.snapshot.errorMessage)
        h.writes.finish(1, .success(()));XCTAssertEqual(h.state.snapshot.profile?.displayName, "Seneste")
    }
    func testWillChangeReentryCannotCommitOldLoadAssignmentOrStartItsEffects() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        var changed = false
        let subscription = h.state.objectWillChange.sink {
            if !changed { changed = true;h.select("B");h.coordinator.load(self.profile("B")) }
        }
        h.reads.finish(0, .success(.init(profile: profile("A"), isFromCache: false)));await h.reads.waitForStarts(2)
        XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertNil(h.state.snapshot.profile)
        XCTAssertTrue(h.subscriptions.isEmpty);XCTAssertTrue(h.fcm.isEmpty)
        h.reads.finish(1, .success(.init(profile: profile("B"), isFromCache: false)))
        await wait(h.state) { $0.loaded && $0.profile?.uid == "B" };withExtendedLifetime(subscription) {}
    }
    func testMultiplePostStateSubscribersNeverReceiveStaleOuterSnapshotAfterNestedOwnerChange() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        var stale: [UInt64] = [], changed = false, received = 0
        let first = h.state.changes.sink { snapshot in
            if snapshot != h.state.snapshot { stale.append(snapshot.revision) }
            if !changed && snapshot.profile?.uid == "A" {
                changed = true;h.select("B");h.coordinator.load(self.profile("B"))
            }
        }
        let second = h.state.changes.sink { snapshot in
            received += 1
            if snapshot != h.state.snapshot { stale.append(snapshot.revision) }
        }
        h.reads.finish(0, .success(.init(profile: profile("A"), isFromCache: false)));await h.reads.waitForStarts(2)
        XCTAssertTrue(stale.isEmpty);XCTAssertGreaterThan(received, 0);XCTAssertTrue(h.subscriptions.isEmpty)
        h.reads.finish(1, .success(.init(profile: profile("B"), isFromCache: false)));await wait(h.state) { $0.loaded && $0.profile?.uid == "B" }
        XCTAssertTrue(stale.isEmpty);withExtendedLifetime([first, second]) {}
    }
    func testIdentityGetterReentryWithStaleIdentityCannotAuthorizeOldLoadEffects() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        h.onIdentity = {
            h.onIdentity = nil;h.select("B");h.coordinator.load(self.profile("B"))
            return .init(actualUID: "A", canonicalUID: "A")
        }
        h.reads.finish(0, .success(.init(profile: profile("A"), isFromCache: false)));await h.reads.waitForStarts(2)
        XCTAssertTrue(h.subscriptions.isEmpty);XCTAssertTrue(h.fcm.isEmpty);XCTAssertTrue(h.writes.calls.isEmpty)
        XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertNil(h.state.snapshot.profile)
    }
    func testEntryIdentityReentryCannotMakeOuterLoadSupersedeNewerNestedLoad() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A")
        h.onIdentity = {
            h.onIdentity = nil;h.coordinator.load(self.profile("A", name: "Ny indlejret profil"))
            return .init(actualUID: "A", canonicalUID: "A")
        }
        h.coordinator.load(profile("A", name: "Gammel ydre profil"));await h.reads.waitForStarts(1)
        XCTAssertEqual(h.reads.calls[0].seed.displayName, "Ny indlejret profil")
        let accepted = profile("A", name: h.reads.calls[0].seed.displayName)
        h.reads.finish(0, .success(.init(profile: accepted, isFromCache: false)))
        await wait(h.state) { $0.loaded }
        XCTAssertEqual(h.state.snapshot.profile?.displayName, "Ny indlejret profil")
    }
    func testEntryIdentityReentryCannotMakeOuterSaveOverwriteNewerNestedEdit() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        h.onIdentity = {
            h.onIdentity = nil;h.coordinator.save(self.profile("A", name: "Ny indlejret ændring"))
            return .init(actualUID: "A", canonicalUID: "A")
        }
        h.coordinator.save(profile("A", name: "Gammel ydre ændring"));await h.writes.waitForStarts(1)
        XCTAssertEqual(h.writes.calls[0].profile.displayName, "Ny indlejret ændring")
        XCTAssertEqual(h.state.snapshot.profile?.displayName, "Ny indlejret ændring")
    }
    func testEntryIdentityEpochRoundTripCannotAdmitOriginalLoad() {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A")
        let original = h.state.snapshot.generation
        h.onIdentity = {
            h.onIdentity = nil;h.select(nil);h.select("A")
            return .init(actualUID: "A", canonicalUID: "A")
        }
        h.coordinator.load(profile("A", name: "Gammel epoch"))
        XCTAssertNotEqual(h.state.snapshot.generation, original);XCTAssertNil(h.state.snapshot.profile)
        XCTAssertFalse(h.state.snapshot.isLoading);XCTAssertFalse(h.coordinator.activity.loading)
        XCTAssertTrue(h.reads.calls.isEmpty)
    }
    func testEntryIdentityEpochRoundTripCannotOverwriteAlreadyAcceptedNewLoginProfile() async throws {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        h.onIdentity = {
            h.onIdentity = nil;h.select(nil);h.select("A")
            if let ticket = h.state.beginLoad(userID: "A") { h.state.acceptLoad(self.profile("A", name: "Ny loginprofil"), ticket: ticket) }
            return .init(actualUID: "A", canonicalUID: "A")
        }
        h.coordinator.save(profile("A", name: "Gammel ændring"))
        XCTAssertEqual(h.state.snapshot.profile?.displayName, "Ny loginprofil")
        XCTAssertFalse(h.coordinator.activity.saving);XCTAssertTrue(h.writes.calls.isEmpty)
    }
    func testTopicEffectReentryRevokesDefaultWriteAndFCMAtTheirActualBoundaries() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        h.onSubscribe = { h.onSubscribe = nil;h.select("B");h.coordinator.load(self.profile("B")) }
        h.reads.finish(0, .success(.init(profile: nil, isFromCache: false)));await h.reads.waitForStarts(2)
        XCTAssertTrue(h.subscriptions.isEmpty);XCTAssertTrue(h.writes.calls.isEmpty);XCTAssertTrue(h.fcm.isEmpty)
        XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertNil(h.state.snapshot.profile)
    }
    func testFCMEffectValidatorRejectsReentrantOwnerAndDoesNotChangeNewProfile() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        h.onFCM = { h.onFCM = nil;h.select("B");h.coordinator.load(self.profile("B")) }
        h.reads.finish(0, .success(.init(profile: profile("A"), isFromCache: false)));await h.reads.waitForStarts(2)
        XCTAssertTrue(h.fcm.isEmpty);XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertNil(h.state.snapshot.profile)
    }
    func testCacheMissRequiresServerProofAndServerFailureCannotCreateDefaults() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };h.select("A");h.coordinator.load(profile("A"));await h.reads.waitForStarts(1)
        h.reads.finish(0, .success(.init(profile: nil, isFromCache: true)));await h.reads.waitForStarts(2)
        if case .server = h.reads.calls[1].source {} else { XCTFail("Cache miss must use explicit server read") }
        XCTAssertTrue(h.writes.calls.isEmpty);XCTAssertNil(h.state.snapshot.profile)
        h.reads.finish(1, .failure(ProfileCoordinatorFailure.provider));await wait(h.state) { !$0.isLoading && $0.errorMessage != nil }
        XCTAssertTrue(h.writes.calls.isEmpty);XCTAssertTrue(h.subscriptions.isEmpty)
        h.coordinator.load(profile("A"));await h.reads.waitForStarts(3)
        h.reads.finish(2, .success(.init(profile: nil, isFromCache: false)));await h.writes.waitForStarts(1)
        XCTAssertEqual(h.writes.calls[0].profile, profile("A"), "Only confirmed server absence may create the complete original-owner profile")
        h.writes.finish(0, .success(()))
    }
    func testReadFailurePreservesSameOwnerProfileButBlocksWritesAndForeignReadCannotAdopt() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        h.coordinator.load(profile("A"));await h.reads.waitForStarts(2)
        h.reads.finish(1, .failure(ProfileCoordinatorFailure.provider));await wait(h.state) { !$0.isLoading && $0.errorMessage != nil }
        XCTAssertEqual(h.state.snapshot.profile, profile("A"));XCTAssertFalse(h.state.snapshot.writeReady)
        h.coordinator.save(profile("A", name: "Not admitted"));XCTAssertTrue(h.writes.calls.isEmpty)
        h.coordinator.load(profile("A"));await h.reads.waitForStarts(3)
        h.reads.finish(2, .success(.init(profile: profile("B"), isFromCache: false)))
        await wait(h.state) { !$0.isLoading }
        XCTAssertEqual(h.state.snapshot.profile?.uid, "A");XCTAssertFalse(h.subscriptions.contains("B"))
    }
    func testFailedSignOutRestoresConfirmedProfileInFreshEpochWithoutRevivingOldTickets() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h)
        let original = h.state.contextTicket(), saved = h.state.snapshot.profile
        h.coordinator.suspendForAccountChange()
        XCTAssertEqual(h.state.snapshot.context, .unresolved);XCTAssertNil(h.state.snapshot.profile)
        XCTAssertTrue(h.coordinator.restoreAfterFailedSignOut())
        XCTAssertEqual(h.state.snapshot.profile, saved);XCTAssertEqual(h.state.snapshot.context, .account("A"))
        XCTAssertNotEqual(h.state.snapshot.generation, original.generation);XCTAssertFalse(h.state.isCurrent(original))
        XCTAssertTrue(h.state.snapshot.writeReady);XCTAssertTrue(h.writes.calls.isEmpty)
    }
    func testNestedNewLoginDuringGuestClearCannotClearNewOwner() async {
        let h = ProfileCoordinatorHarness();defer { h.close() };await loaded(h);h.coordinator.suspendForAccountChange()
        h.actualUID = nil;h.canonicalUID = nil
        h.onIdentity = {
            h.onIdentity = nil;h.select("B");h.coordinator.load(self.profile("B"))
            return .init(actualUID: nil, canonicalUID: nil)
        }
        h.coordinator.clearIfConfirmedGuest();await h.reads.waitForStarts(2)
        XCTAssertEqual(h.state.snapshot.context, .account("B"));XCTAssertNil(h.state.snapshot.profile)
        h.reads.finish(1, .success(.init(profile: profile("B"), isFromCache: false)));await wait(h.state) { $0.loaded && $0.profile?.uid == "B" }
    }
}

@MainActor
private final class ProfileCoordinatorHarness {
    struct ReadCall { let seed: UserProfile;let source: UserProfileCoordinator.ReadSource;let ticket: UserProfileState.LoadTicket }
    struct WriteCall { let profile: UserProfile;let ticket: UserProfileState.SaveTicket }
    let state = UserProfileState()
    let reads = ProfileProviderLane<ReadCall, UserProfileCoordinator.ReadResult>()
    let writes = ProfileProviderLane<WriteCall, Void>()
    var actualUID: String?, canonicalUID: String?
    var identityReads = 0
    var onIdentity: (() -> UserProfileCoordinator.Identity?)?
    var onSubscribe: (() -> Void)?, onFCM: (() -> Void)?
    var subscriptions: [String] = [], subscribedNames: [String] = [], unsubscriptions: [String] = [], fcm: [String] = []
    lazy var coordinator = UserProfileCoordinator(state: state, effects: .init(capturePermission: { { true } }, identity: { [self] in
        identityReads += 1
        return onIdentity?() ?? .init(actualUID: actualUID, canonicalUID: canonicalUID)
    }, read: { [self] seed, source, ticket, stillCurrent in
        guard stillCurrent() else { throw CancellationError() }
        return try await reads.perform(.init(seed: seed, source: source, ticket: ticket))
    }, write: { [self] profile, ticket, stillCurrent in
        guard stillCurrent() else { throw CancellationError() }
        try await writes.perform(.init(profile: profile, ticket: ticket))
    }, subscribe: { [self] profile, owns in
        onSubscribe?()
        if owns() { subscriptions.append(profile.uid);subscribedNames.append(profile.displayName) }
    }, unsubscribe: { [self] profile, owns in
        if owns() { unsubscriptions.append(profile.uid) }
    }, updateFCM: { [self] uid, owns in
        onFCM?()
        if owns() { fcm.append(uid) }
    }))
    init(started: Bool = true) { if started { coordinator.start() } }
    func select(_ uid: String?) { actualUID = uid;canonicalUID = uid;coordinator.changeAccountContext(userID: uid) }
    func close() {
        onIdentity = nil;onSubscribe = nil;onFCM = nil
        coordinator.suspendForAccountChange();reads.failOutstanding();writes.failOutstanding()
    }
}
private enum ProfileCoordinatorFailure: Error { case provider }
@MainActor
private final class ProfileProviderLane<Input, Output> {
    private(set) var calls: [Input] = []
    private var continuations: [Int: CheckedContinuation<Output, Error>] = [:]
    private var waiters: [(Int, XCTestExpectation)] = []
    private var returnWaiters: [(Int, XCTestExpectation)] = []
    private var returns = 0
    var activeCount: Int { continuations.count }
    func perform(_ input: Input) async throws -> Output {
        defer {
            returns += 1
            let ready = returnWaiters.filter { $0.0 <= returns };returnWaiters.removeAll { $0.0 <= returns };ready.forEach { $0.1.fulfill() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let index = calls.count;calls.append(input);continuations[index] = continuation
            let ready = waiters.filter { $0.0 <= calls.count };waiters.removeAll { $0.0 <= calls.count };ready.forEach { $0.1.fulfill() }
        }
    }
    func waitForStarts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        if calls.count >= count { return }
        let expectation = XCTestExpectation(description: "Actual profile provider starts \(count)");waiters.append((count, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3);XCTAssertEqual(result, .completed, file: file, line: line)
    }
    func waitForReturns(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        if returns >= count { return }
        let expectation = XCTestExpectation(description: "Actual provider operation returned \(count)");returnWaiters.append((count, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3);XCTAssertEqual(result, .completed, file: file, line: line)
    }
    func finish(_ index: Int, _ result: Result<Output, Error>) { continuations.removeValue(forKey: index)?.resume(with: result) }
    func failOutstanding() {
        let previous = continuations.values;continuations = [:]
        previous.forEach { $0.resume(throwing: ProfileCoordinatorFailure.provider) }
    }
}
