import Combine
import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class UserProfileCanonicalBridgeTests: XCTestCase {
    private func profile(_ uid: String) -> UserProfile {
        UserProfile(uid: uid, email: uid + "@example.invalid", displayName: uid, photoURL: nil,
                    createdAt: Date(timeIntervalSince1970: 100), lastLoginAt: Date(timeIntervalSince1970: 200),
                    favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
                    readArticles: [uid + "-read"], bookmarkedArticles: [], readingProgress: [:])
    }
    @discardableResult private func loadedA(_ state: UserProfileState) throws -> UserProfileState.LoadTicket {
        _ = state.changeContext(to: .confirmed(userID: "A"))
        let ticket = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertTrue(state.acceptLoad(profile("A"), ticket: ticket)); return ticket
    }
    /// Merely supplies injected production effects to the ACTUAL bridge. This
    /// fixture does not reproduce its ordering or revision/identity decisions.
    private func transition(_ bridge: CanonicalAccountPublication, _ state: UserProfileState,
                            uid: String?, actual: () -> String?, started: (UserProfileState.LoadTicket) -> Void,
                            dependencies: [() -> Void] = []) -> Bool {
        bridge.performProfileTransition(expectedUserID: uid, currentUserID: actual,
            revokeProfile: { _ = state.changeContext(to: .confirmed(userID: uid)) },
            dependentSteps: dependencies, startProfile: {
                if let uid, let ticket = state.beginLoad(userID: uid) { started(ticket) }
            })
    }
    func testActualCanonicalBRevokesAProfileBeforeDependentUIAndOnlyThenStartsBLoad() throws {
        let state = UserProfileState(); let old = try loadedA(state); let bridge = CanonicalAccountPublication()
        var actualUID: String? = "B"; var started: [UserProfileState.LoadTicket] = []; var observed = false
        let accepted = transition(bridge, state, uid: "B", actual: { actualUID }, started: { started.append($0) }, dependencies: [{
            observed = true
            XCTAssertEqual(state.snapshot.context, .account("B")); XCTAssertNil(state.snapshot.profile)
            XCTAssertFalse(state.snapshot.loaded); XCTAssertFalse(state.snapshot.writeReady)
            XCTAssertFalse(state.isCurrent(old)); XCTAssertTrue(started.isEmpty)
        }])
        XCTAssertTrue(accepted); XCTAssertTrue(observed); XCTAssertEqual(started.map(\.userID), ["B"])
        XCTAssertTrue(state.snapshot.isLoading); XCTAssertNil(state.snapshot.profile)
        actualUID = nil
    }
    func testWrongActualIdentityCannotClearProfileOrBeginLoad() throws {
        let state = UserProfileState(); try loadedA(state); let before = state.snapshot
        let bridge = CanonicalAccountPublication(); var started = 0; var dependent = 0
        let accepted = transition(bridge, state, uid: "B", actual: { "A" }, started: { _ in started += 1 },
                                  dependencies: [{ dependent += 1 }])
        XCTAssertFalse(accepted); XCTAssertEqual(started, 0); XCTAssertEqual(dependent, 0); XCTAssertEqual(state.snapshot, before)
    }
    func testWillChangeNewLoginRevokesOuterBStartAcrossGuestAndOriginalA() throws {
        let state = UserProfileState(); let old = try loadedA(state); let bridge = CanonicalAccountPublication()
        var actualUID: String? = "B"; var started: [UserProfileState.LoadTicket] = []; var once = true; var outerDependent = 0
        let subscription = state.objectWillChange.sink {
            guard once else { return }; once = false
            actualUID = nil
            _ = self.transition(bridge, state, uid: nil, actual: { actualUID }, started: { started.append($0) })
            actualUID = "A"
            _ = self.transition(bridge, state, uid: "A", actual: { actualUID }, started: { started.append($0) })
        }
        let accepted = transition(bridge, state, uid: "B", actual: { actualUID }, started: { started.append($0) },
                                  dependencies: [{ outerDependent += 1 }])
        XCTAssertFalse(accepted); XCTAssertEqual(outerDependent, 0); XCTAssertEqual(started.map(\.userID), ["A"])
        XCTAssertEqual(state.snapshot.context, .account("A")); XCTAssertNil(state.snapshot.profile); XCTAssertFalse(state.isCurrent(old))
        withExtendedLifetime(subscription) {}
    }
    func testPostStateNestedGuestAStopsOuterBAndLaterSubscribersSeeOnlyCurrentSnapshots() throws {
        let state = UserProfileState(); try loadedA(state); let bridge = CanonicalAccountPublication()
        var actualUID: String? = "B"; var once = true; var started: [UserProfileState.LoadTicket] = []
        let first = state.changes.sink { value in
            if once, value.context == .account("B") {
                once = false; actualUID = nil
                _ = self.transition(bridge, state, uid: nil, actual: { actualUID }, started: { started.append($0) })
                actualUID = "A"
                _ = self.transition(bridge, state, uid: "A", actual: { actualUID }, started: { started.append($0) })
            }
        }
        let second = state.changes.sink { value in XCTAssertEqual(value, state.snapshot) }
        XCTAssertFalse(transition(bridge, state, uid: "B", actual: { actualUID }, started: { started.append($0) }))
        XCTAssertEqual(started.map(\.userID), ["A"]); XCTAssertEqual(state.snapshot.context, .account("A"))
        withExtendedLifetime((first, second)) {}
    }
    func testDependencyStartingNewSameUIDTransitionInvalidatesOuterStart() throws {
        let state = UserProfileState(); try loadedA(state); let bridge = CanonicalAccountPublication()
        var started: [UserProfileState.LoadTicket] = []; var secondOuterStep = 0
        let accepted = transition(bridge, state, uid: "B", actual: { "B" }, started: { started.append($0) }, dependencies: [{
            _ = self.transition(bridge, state, uid: "B", actual: { "B" }, started: { started.append($0) })
        }, { secondOuterStep += 1 }])
        XCTAssertFalse(accepted); XCTAssertEqual(secondOuterStep, 0); XCTAssertEqual(started.map(\.userID), ["B"])
        XCTAssertTrue(state.isCurrent(try XCTUnwrap(started.first)))
    }
    func testReentryDuringInitialIdentityReadCannotOverwriteNewerSameUIDTransition() throws {
        let state = UserProfileState(); try loadedA(state); let bridge = CanonicalAccountPublication()
        var reads = 0; var started: [UserProfileState.LoadTicket] = []
        let accepted = transition(bridge, state, uid: "B", actual: {
            reads += 1
            if reads == 1 { _ = self.transition(bridge, state, uid: "B", actual: { "B" }, started: { started.append($0) }) }
            return "B"
        }, started: { started.append($0) })
        XCTAssertFalse(accepted); XCTAssertEqual(started.count, 1)
        XCTAssertTrue(state.isCurrent(try XCTUnwrap(started.first)))
    }
    func testReentryDuringEachIdentityGuardCannotExecuteStaleRevokeDependencyOrStart() throws {
        // Initial read=1; revoke guard=2; dependency guard=3; start guard=4.
        for reentryRead in [2, 3, 4] {
            let state = UserProfileState(); try loadedA(state); let bridge = CanonicalAccountPublication()
            var reads = 0; var staleEffects: [String] = []; var newestStarts: [UserProfileState.LoadTicket] = []
            let accepted = bridge.performProfileTransition(expectedUserID: "B", currentUserID: {
                reads += 1
                if reads == reentryRead {
                    _ = self.transition(bridge, state, uid: "B", actual: { "B" }, started: { newestStarts.append($0) })
                }
                return "B"
            }, revokeProfile: { staleEffects.append("revoke"); _ = state.changeContext(to: .confirmed(userID: "B")) },
                dependentSteps: [{ staleEffects.append("dependent") }],
                startProfile: { staleEffects.append("start"); _ = state.beginLoad(userID: "B") })
            XCTAssertFalse(accepted)
            let expected: [String] = reentryRead == 2 ? [] : reentryRead == 3 ? ["revoke"] : ["revoke", "dependent"]
            XCTAssertEqual(staleEffects, expected, "Identity read \(reentryRead) must be followed by a revision recheck")
            XCTAssertTrue(state.isCurrent(try XCTUnwrap(newestStarts.first)))
        }
    }
    func testFinalIdentityReadReentryCannotReportSupersededTransitionAsAccepted() throws {
        let state = UserProfileState(); try loadedA(state); let bridge = CanonicalAccountPublication()
        var reads = 0; var started: [UserProfileState.LoadTicket] = []
        // With revoke+start and no dependencies: initial, revoke, start, final.
        let accepted = transition(bridge, state, uid: "B", actual: {
            reads += 1
            if reads == 4 { _ = self.transition(bridge, state, uid: "B", actual: { "B" }, started: { started.append($0) }) }
            return "B"
        }, started: { started.append($0) })
        XCTAssertFalse(accepted); XCTAssertEqual(started.count, 2)
        XCTAssertFalse(state.isCurrent(started[0])); XCTAssertTrue(state.isCurrent(started[1]))
    }
    /// The real Auth ingress invalidates old parent permission; the same value
    /// admissions used by production then drive actual manager/service pipelines.
    @MainActor private final class IngressFixture {
        struct ProfileRead {
            let seed: UserProfile
            let current: UserProfileCoordinator.Guard
            let continuation: CheckedContinuation<UserProfileCoordinator.ReadResult, Error>
        }
        struct PreferenceRead {
            let current: ReaderPreferencesModel.Guard
            let continuation: CheckedContinuation<ReaderPreferencesModel.ReadResult, Error>
        }
        enum Failure: Error { case offline }
        let auth = AuthService(startup: .application)
        let profile = UserProfileState()
        let events = PassthroughSubject<Void, Never>()
        var uid: String?
        var profileReads: [ProfileRead] = [], preferenceReads: [PreferenceRead] = []
        var profilePending = Set<Int>(), preferencePending = Set<Int>()
        var preferenceTasks: [Task<Void, Never>] = []
        var profileWrites = 0, preferenceWrites = 0
        lazy var manager = UserManager(state: profile, effects: .init(capturePermission: { [weak self] in
            guard let self else { return nil }
            let context = self.auth.state.contextTicket()
            return { [weak self] in self?.auth.state.isCurrent(context) == true && self?.uid == context.userID }
        }, identity: { [weak self] in .init(actualUID: self?.uid, canonicalUID: self?.auth.state.snapshot.userID) },
        read: { [weak self] seed, _, _, current in
            guard let self, current() else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                self.profilePending.insert(self.profileReads.count)
                self.profileReads.append(.init(seed: seed, current: current, continuation: continuation))
                self.events.send()
            }
        }, write: { [weak self] _, _, current in
            guard current() else { throw CancellationError() }; self?.profileWrites += 1
        }, subscribe: { _, _ in }, unsubscribe: { _, _ in }, updateFCM: { _, _ in }),
        currentProfileSeed: { [weak self] in self?.uid.map { Self.seed($0) } })
        lazy var preferences = ReaderPreferencesService(effects: .init(capturePermission: { [weak self] in
            guard let self else { return nil }
            let context = self.auth.state.contextTicket()
            return { [weak self] in self?.auth.state.isCurrent(context) == true && self?.uid == context.userID }
        }, identity: { [weak self] in .init(actualUID: self?.uid, canonicalUID: self?.auth.state.snapshot.userID) },
        load: { [weak self] _, current in
            guard let self, current() else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                self.preferencePending.insert(self.preferenceReads.count)
                self.preferenceReads.append(.init(current: current, continuation: continuation))
                self.events.send()
            }
        }, save: { [weak self] _, current in
            guard current() else { throw CancellationError() }; self?.preferenceWrites += 1
        }))
        init() {
            XCTAssertNil(FirebaseApp.allApps)
            manager.startObservingSession(); preferences.start()
        }
        static func seed(_ uid: String, name: String? = nil) -> UserProfile {
            UserProfile(uid: uid, email: uid.lowercased() + "@example.invalid", displayName: name ?? "", photoURL: nil,
                createdAt: Date(timeIntervalSince1970: 100), lastLoginAt: Date(timeIntervalSince1970: 200),
                favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
                readArticles: [], bookmarkedArticles: [], readingProgress: [:])
        }
        @discardableResult func observe(_ userID: String?) -> CanonicalSessionState.ContextTicket? {
            uid = userID
            let session = userID.map { ReaderAccountSession(uid: $0, email: $0.lowercased() + "@example.invalid", isEmailVerified: true) }
            return auth.observeIdentity(session, currentUserID: { [unowned self] in uid }, revokeReader: { [unowned self] current in
                manager.suspendForAccountChange()
                _ = preferences.model.changeContext(to: .unresolved)
                return auth.state.suspend(stillPermitted: current) != nil
            }, publishReader: { [unowned self] current in
                manager.changeAccountContext(userID: userID)
                guard let context = preferences.changeAccountContext(userID: userID),
                      let accepted = auth.state.adopt(session, stillPermitted: current), current() else { return nil }
                if let userID { manager.loadUserProfileIfNeeded(Self.seed(userID), stillCurrent: current) }
                else { manager.clearIfConfirmedGuest() }
                preferenceTasks.append(Task { [preferences] in
                    await preferences.loadCurrentContextIfNeeded(context, stillCurrent: current)
                })
                return accepted
            })
        }
        func wait(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
            if condition() { return }
            let expectation = XCTestExpectation(description: "Actual profile/preferences ingress effect")
            let observation = events.sink { if condition() { expectation.fulfill() } }
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
            withExtendedLifetime(observation) {}
        }
        func replyProfile(_ index: Int, name: String? = nil, fail: Bool = false) {
            guard profilePending.remove(index) != nil else { return }
            let read = profileReads[index]
            if fail { read.continuation.resume(throwing: Failure.offline) }
            else {
                let value = Self.seed(read.seed.uid, name: name ?? "Confirmed " + read.seed.uid)
                read.continuation.resume(returning: .init(profile: value, isFromCache: false))
            }
        }
        func replyPreferences(_ index: Int, topic: String) {
            guard preferencePending.remove(index) != nil else { return }
            preferenceReads[index].continuation.resume(returning: .init(preferences: .init(interestTopicIDs: [topic]), isFromCache: false))
        }
        func close() {
            uid = nil; _ = auth.state.suspend(); manager.suspendForAccountChange()
            _ = preferences.model.changeContext(to: .unresolved)
            for index in Array(profilePending) { replyProfile(index, fail: true) }
            for index in Array(preferencePending) {
                preferencePending.remove(index); preferenceReads[index].continuation.resume(throwing: Failure.offline)
            }
            preferenceTasks.forEach { $0.cancel() }
            XCTAssertNil(FirebaseApp.allApps)
        }
    }

    func testSameUIDAuthIngressReplacesBothHeldReadsWithoutBorrowingOldPermission() async throws {
        let f = IngressFixture(); defer { f.close() }
        XCTAssertNotNil(f.observe("A")); await f.wait { f.profileReads.count == 1 && f.preferenceReads.count == 1 }
        XCTAssertTrue(f.profileReads[0].current()); XCTAssertTrue(f.preferenceReads[0].current())
        XCTAssertNotNil(f.observe("A")); await f.wait { f.profileReads.count == 2 && f.preferenceReads.count == 2 }
        XCTAssertFalse(f.profileReads[0].current()); XCTAssertFalse(f.preferenceReads[0].current())
        XCTAssertTrue(f.profileReads[1].current()); XCTAssertTrue(f.preferenceReads[1].current())
        f.replyProfile(0, name: "Stale"); f.replyPreferences(0, topic: "stale")
        await f.preferenceTasks[0].value
        XCTAssertNil(f.profile.snapshot.profile); XCTAssertTrue(f.profile.snapshot.isLoading)
        XCTAssertFalse(f.preferences.model.hasLoaded); XCTAssertTrue(f.preferences.model.isLoading)
        let loaded = XCTestExpectation(description: "Fresh profile accepted")
        let observation = f.profile.changes.sink { if $0.loaded { loaded.fulfill() } }
        f.replyProfile(1, name: "Fresh"); f.replyPreferences(1, topic: "fresh")
        await f.preferenceTasks[1].value
        let loadedResult = await XCTWaiter.fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(loadedResult, .completed)
        XCTAssertEqual(f.profile.snapshot.profile?.displayName, "Fresh")
        XCTAssertEqual(f.preferences.model.preferences.interestTopicIDs, ["fresh"])
        XCTAssertEqual(f.profileWrites, 0); XCTAssertEqual(f.preferenceWrites, 0)
        withExtendedLifetime(observation) {}
    }

    func testFreshProfileFailureRetainsExplicitRetryAndIdleCancellationIsRetryable() async throws {
        let f = IngressFixture(); defer { f.close() }
        XCTAssertNotNil(f.observe("A")); await f.wait { f.profileReads.count == 1 && f.preferenceReads.count == 1 }
        let failed = XCTestExpectation(description: "Actual profile failure")
        let observation = f.profile.changes.sink { if $0.errorMessage != nil { failed.fulfill() } }
        f.replyProfile(0, fail: true)
        let failedResult = await XCTWaiter.fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(failedResult, .completed)
        XCTAssertTrue(SettingsAccountSection(snapshot: f.profile.snapshot, onLogin: {}, onRetry: {}).canRetryProfile)
        f.manager.retryProfileLoad(); await f.wait { f.profileReads.count == 2 }
        XCTAssertFalse(SettingsAccountSection(snapshot: f.profile.snapshot, onLogin: {}, onRetry: {}).canRetryProfile)
        let loaded = XCTestExpectation(description: "Retry confirms actual profile")
        let second = f.profile.changes.sink { if $0.loaded { loaded.fulfill() } }
        f.replyProfile(1, name: "Retry confirmed")
        let loadedResult = await XCTWaiter.fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(loadedResult, .completed)
        XCTAssertEqual(f.profile.snapshot.profile?.displayName, "Retry confirmed")
        XCTAssertFalse(SettingsAccountSection(snapshot: f.profile.snapshot, onLogin: {}, onRetry: {}).canRetryProfile)
        let idle = UserProfileState(); _ = idle.changeContext(to: .account("A"))
        let ticket = try XCTUnwrap(idle.beginLoad(userID: "A")); XCTAssertTrue(idle.cancelLoad(ticket: ticket))
        XCTAssertNil(idle.snapshot.errorMessage); XCTAssertFalse(idle.snapshot.isLoading)
        XCTAssertTrue(SettingsAccountSection(snapshot: idle.snapshot, onLogin: {}, onRetry: {}).canRetryProfile)
        _ = idle.changeContext(to: .guest)
        XCTAssertFalse(SettingsAccountSection(snapshot: idle.snapshot, onLogin: {}, onRetry: {}).canRetryProfile)
        _ = idle.changeContext(to: .unresolved)
        XCTAssertFalse(SettingsAccountSection(snapshot: idle.snapshot, onLogin: {}, onRetry: {}).canRetryProfile)
        withExtendedLifetime((observation, second)) {}
    }

    func testAccountChangeAndSuspensionRejectHeldProfileAndPreferencesWithoutPublishingSeed() async throws {
        let f = IngressFixture(); defer { f.close() }
        XCTAssertNotNil(f.observe("A")); await f.wait { f.profileReads.count == 1 && f.preferenceReads.count == 1 }
        XCTAssertNotNil(f.observe("B")); await f.wait { f.profileReads.count == 2 && f.preferenceReads.count == 2 }
        XCTAssertFalse(f.profileReads[0].current()); XCTAssertFalse(f.preferenceReads[0].current())
        f.replyProfile(0); f.replyPreferences(0, topic: "A")
        await f.preferenceTasks[0].value
        XCTAssertEqual(f.profile.snapshot.context, .account("B")); XCTAssertNil(f.profile.snapshot.profile)
        f.manager.suspendForAccountChange()
        _ = f.preferences.model.changeContext(to: .unresolved)
        _ = f.auth.state.suspend()
        XCTAssertFalse(f.profileReads[1].current()); XCTAssertFalse(f.preferenceReads[1].current())
        f.replyProfile(1); f.replyPreferences(1, topic: "B")
        await f.preferenceTasks[1].value
        XCTAssertEqual(f.profile.snapshot.context, .unresolved); XCTAssertNil(f.profile.snapshot.profile)
        XCTAssertEqual(f.preferences.model.snapshot.context, .unresolved)
        XCTAssertNotNil(f.observe(nil)); await f.preferenceTasks.last?.value
        XCTAssertEqual(f.profile.snapshot.context, .guest); XCTAssertNil(f.profile.snapshot.profile)
        XCTAssertEqual(f.preferences.model.snapshot.context, .guest); XCTAssertFalse(f.preferences.model.hasLoaded)
        XCTAssertEqual(f.profileWrites, 0); XCTAssertEqual(f.preferenceWrites, 0)
    }
    func testIfNeededParentReentryKeepsConfirmedProfileAndRejectsNewOwnerBeforeAnyProviderRead() async throws {
        let f = IngressFixture(); defer { f.close() }
        f.uid = "A"
        let session = ReaderAccountSession(uid: "A", email: "a@example.invalid", isEmailVerified: true)
        let canonical = try XCTUnwrap(f.auth.state.adopt(session))
        f.manager.changeAccountContext(userID: "A")
        let pending = try XCTUnwrap(f.profile.beginLoad(userID: "A"))
        let confirmed = IngressFixture.seed("A", name: "Already confirmed by current read")
        var once = true
        f.manager.loadUserProfileIfNeeded(IngressFixture.seed("A"), stillCurrent: {
            if once {
                once = false
                XCTAssertTrue(f.profile.acceptLoad(confirmed, ticket: pending))
            }
            return f.auth.state.isCurrent(canonical)
        })
        XCTAssertTrue(f.profileReads.isEmpty)
        XCTAssertTrue(f.profile.snapshot.loaded)
        XCTAssertEqual(f.profile.snapshot.profile?.displayName, confirmed.displayName)
        XCTAssertEqual(f.profileWrites, 0)

        let changed = IngressFixture(); defer { changed.close() }
        changed.uid = "A"
        let oldCanonical = try XCTUnwrap(changed.auth.state.adopt(session))
        changed.manager.changeAccountContext(userID: "A")
        var replaceOwner = true
        changed.manager.loadUserProfileIfNeeded(IngressFixture.seed("A"), stillCurrent: {
            if replaceOwner {
                replaceOwner = false; changed.uid = "B"
                changed.manager.changeAccountContext(userID: "B")
                _ = changed.auth.state.adopt(.init(uid: "B", email: "b@example.invalid", isEmailVerified: true))
            }
            return changed.auth.state.isCurrent(oldCanonical)
        })
        XCTAssertTrue(changed.profileReads.isEmpty)
        XCTAssertEqual(changed.profile.snapshot.context, .account("B"))
        XCTAssertNil(changed.profile.snapshot.profile)

        // The preferences helper must recheck the original ticket after its
        // parent callback too, rather than accidentally loading the new owner.
        changed.uid = "A"; _ = changed.auth.state.adopt(session)
        let oldPreferences = try XCTUnwrap(changed.preferences.changeAccountContext(userID: "A"))
        var preferenceReentry = true
        await changed.preferences.loadCurrentContextIfNeeded(oldPreferences, stillCurrent: {
            if preferenceReentry {
                preferenceReentry = false; changed.uid = "B"
                _ = changed.auth.state.adopt(.init(uid: "B", email: "b@example.invalid", isEmailVerified: true))
                _ = changed.preferences.changeAccountContext(userID: "B")
            }
            return true // Ticket/identity checks must reject even this permissive caller.
        })
        XCTAssertTrue(changed.preferenceReads.isEmpty)
        XCTAssertEqual(changed.preferences.model.snapshot.context, .account("B"))
        XCTAssertFalse(changed.preferences.model.hasLoaded)
    }
}
