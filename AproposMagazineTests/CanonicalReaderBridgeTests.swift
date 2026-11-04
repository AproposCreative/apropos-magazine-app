import Combine
import XCTest
@testable import Apropos

@MainActor
final class CanonicalReaderBridgeTests: XCTestCase {
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let profile = UserProfileState()
        let bridge = CanonicalAccountPublication()
        var actualUID: String?
        var order: [String] = []
        var loads: [String?] = []
        var preferenceLoads: [Task<Void, Never>] = []
        var onIdentity: (() -> Void)?
        var onRevocationsValidation: (() -> Void)?
        lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [unowned self] in
            .init(actualUID: self.actualUID, canonicalUID: self.canonical.snapshot.userID)
        }, load: { context, valid in
            guard valid() else { throw CancellationError() }
            return .init(preferences: ReaderPreferences(interestTopicIDs: [context.userID! + "-private"]), isFromCache: false)
        }, save: { _, _ in }, schedule: { _ in {} })
        func account(_ uid: String) -> ReaderAccountSession {
            ReaderAccountSession(uid: uid, email: uid + "@example.invalid", isEmailVerified: false)
        }
        func userProfile(_ uid: String) -> UserProfile {
            UserProfile(uid: uid, email: uid + "@example.invalid", displayName: uid, photoURL: nil,
                createdAt: Date(timeIntervalSince1970: 100), lastLoginAt: Date(timeIntervalSince1970: 200),
                favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
                readArticles: [], bookmarkedArticles: [], readingProgress: [:])
        }
        func seedA() async throws {
            actualUID = "A"; _ = canonical.adopt(account("A"))
            _ = profile.changeContext(to: .account("A"))
            let profileTicket = try XCTUnwrap(profile.beginLoad(userID: "A"))
            XCTAssertTrue(profile.acceptLoad(userProfile("A"), ticket: profileTicket))
            preferences.start()
            let ticket = try XCTUnwrap(preferences.changeContext(to: .account("A")))
            await preferences.load(ticket)
            order = []; loads = []
        }
        @discardableResult
        func transition(_ uid: String?, dependent: (() -> Void)? = nil, start: (() -> Void)? = nil) -> Bool {
            actualUID = uid
            let label = uid ?? "guest"
            var profileContext: UserProfileState.ContextTicket?
            var preferencesContext: ReaderPreferencesModel.ContextTicket?
            var accepted: CanonicalSessionState.ContextTicket?
            let validRevocations: () -> Bool = { [self] in
                onRevocationsValidation?()
                guard let profileContext, let preferencesContext else { return false }
                return profile.isCurrent(profileContext) && profileContext.context == .confirmed(userID: uid)
                    && preferences.isCurrent(preferencesContext) && preferencesContext.context == .confirmed(userID: uid)
            }
            return bridge.performReaderTransition(expectedUserID: uid, currentUserID: { [self] in
                onIdentity?(); return actualUID
            }, revokeProfile: { [self] in
                order.append("profile." + label)
                profileContext = profile.changeContext(to: .confirmed(userID: uid))
                guard let profileContext else { return false }
                return profile.isCurrent(profileContext) && profileContext.context == .confirmed(userID: uid)
            }, revokePreferences: { [self] in
                order.append("preferences." + label)
                preferencesContext = preferences.changeContext(to: .confirmed(userID: uid))
                guard let preferencesContext else { return false }
                return preferences.isCurrent(preferencesContext) && preferencesContext.context == .confirmed(userID: uid)
            }, revocationsCurrent: validRevocations,
            dependentSteps: [{ [self] in order.append("dependent." + label); dependent?() }], commitCanonical: { [self] in
                order.append("canonical." + label)
                accepted = canonical.adopt(uid.map(account), stillPermitted: validRevocations)
                return accepted.map(canonical.isCurrent) ?? false
            }, startLoads: { [self] in
                guard let accepted, canonical.isCurrent(accepted) else { return }
                order.append("loads." + label); loads.append(uid); start?()
                guard canonical.isCurrent(accepted) else { return }
                if let uid, let ticket = profile.beginLoad(userID: uid) { _ = profile.acceptLoad(userProfile(uid), ticket: ticket) }
                guard canonical.isCurrent(accepted), let preferencesContext else { return }
                preferenceLoads.append(Task { [self] in
                    guard self.canonical.isCurrent(accepted) else { return }
                    await self.preferences.load(preferencesContext)
                })
            })
        }
        func finishLoads() async {
            let captured = preferenceLoads; preferenceLoads = []
            for task in captured { await task.value }
        }
        var recommendation: ReaderRecommendationAccountInput {
            ReaderRecommendationSelection.capture(canonical: canonical.snapshot, preferences: preferences.snapshot)
        }
    }

    func testActualBridgeRevokesBothPrivateProjectionsBeforeDependentThenCommitsAndLoadsB() async throws {
        let fixture = Fixture(); try await fixture.seedA()
        XCTAssertEqual(fixture.recommendation.interestTopicIDs, ["A-private"])
        let oldProfile = fixture.profile.contextTicket(), oldPreferences = fixture.preferences.contextTicket()
        let accepted = fixture.transition("B", dependent: {
            XCTAssertEqual(fixture.canonical.snapshot.userID, "A")
            XCTAssertEqual(fixture.profile.snapshot.context, .account("B")); XCTAssertNil(fixture.profile.snapshot.profile)
            XCTAssertEqual(fixture.preferences.snapshot.userID, "B"); XCTAssertFalse(fixture.preferences.snapshot.loaded)
            XCTAssertTrue(fixture.preferences.snapshot.preferences.interestTopicIDs.isEmpty)
            XCTAssertFalse(fixture.profile.isCurrent(oldProfile)); XCTAssertFalse(fixture.preferences.isCurrent(oldPreferences))
            XCTAssertTrue(fixture.recommendation.interestTopicIDs.isEmpty)
        }, start: {
            XCTAssertEqual(fixture.canonical.snapshot.userID, "B")
            XCTAssertTrue(fixture.recommendation.interestTopicIDs.isEmpty)
        })
        XCTAssertTrue(accepted)
        XCTAssertEqual(fixture.order, ["profile.B", "preferences.B", "dependent.B", "canonical.B", "loads.B"])
        await fixture.finishLoads()
        XCTAssertEqual(fixture.profile.snapshot.profile?.uid, "B")
        XCTAssertEqual(fixture.recommendation.interestTopicIDs, ["B-private"])
    }
    func testCanonicalBSubscriberCanNeverReadAInterestsFromActualCurrentModels() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var observations: [ReaderRecommendationAccountInput] = []
        let subscription = fixture.canonical.changes.sink { _ in observations.append(fixture.recommendation) }
        XCTAssertTrue(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(observations.first?.canonicalUserID, "B")
        XCTAssertTrue(observations.allSatisfy { !$0.interestTopicIDs.contains("A-private") })
        withExtendedLifetime(subscription) {}
    }
    func testGuestTransitionRevokesProfileInterestsAndOriginalActionEpochBeforePublication() async throws {
        let fixture = Fixture(); try await fixture.seedA(); let original = fixture.canonical.contextTicket()
        XCTAssertTrue(fixture.transition(nil, dependent: {
            XCTAssertEqual(fixture.profile.snapshot.context, .guest); XCTAssertNil(fixture.profile.snapshot.profile)
            XCTAssertEqual(fixture.preferences.snapshot.context, .guest)
            XCTAssertTrue(fixture.recommendation.interestTopicIDs.isEmpty)
        }))
        await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.context, .guest); XCTAssertFalse(fixture.canonical.isCurrent(original))
        XCTAssertNil(fixture.recommendation.canonicalUserID)
    }
    func testGuestAndSameUIDReturnDoNotReviveOldPreferencesDuringCanonicalCommit() async throws {
        let fixture = Fixture(); try await fixture.seedA()
        let original = fixture.canonical.contextTicket(), oldPreferences = fixture.preferences.contextTicket()
        XCTAssertTrue(fixture.transition(nil)); await fixture.finishLoads()
        XCTAssertTrue(fixture.transition("A", start: {
            XCTAssertFalse(fixture.canonical.isCurrent(original)); XCTAssertFalse(fixture.preferences.isCurrent(oldPreferences))
            XCTAssertTrue(fixture.recommendation.interestTopicIDs.isEmpty)
        }))
        await fixture.finishLoads()
        XCTAssertEqual(fixture.recommendation.interestTopicIDs, ["A-private"])
        XCTAssertNotEqual(fixture.recommendation.preferencesGeneration, oldPreferences.generation)
    }
    func testDependentReentryIntoCStopsOuterBCanonicalCommitAndLoads() async throws {
        let fixture = Fixture(); try await fixture.seedA()
        let accepted = fixture.transition("B", dependent: { XCTAssertTrue(fixture.transition("C")) })
        XCTAssertFalse(accepted); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "C"); XCTAssertEqual(fixture.profile.snapshot.profile?.uid, "C")
        XCTAssertEqual(fixture.preferences.snapshot.userID, "C"); XCTAssertEqual(fixture.loads.compactMap { $0 }, ["C"])
        XCTAssertFalse(fixture.order.contains("canonical.B")); XCTAssertFalse(fixture.order.contains("loads.B"))
    }
    func testProfileWillChangeReentryIntoCStopsOuterBeforePreferencesBPublication() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        let subscription = fixture.profile.objectWillChange.sink {
            if once { once = false; XCTAssertTrue(fixture.transition("C")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "C"); XCTAssertEqual(fixture.profile.snapshot.profile?.uid, "C")
        XCTAssertFalse(fixture.order.contains("preferences.B")); XCTAssertFalse(fixture.order.contains("loads.B"))
        withExtendedLifetime(subscription) {}
    }
    func testPreferencesWillChangeReentryIntoCStopsOuterDependentAndCanonicalB() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        let subscription = fixture.preferences.objectWillChange.sink {
            if once { once = false; XCTAssertTrue(fixture.transition("C")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "C"); XCTAssertEqual(fixture.preferences.snapshot.userID, "C")
        XCTAssertFalse(fixture.order.contains("dependent.B")); XCTAssertFalse(fixture.order.contains("loads.B"))
        withExtendedLifetime(subscription) {}
    }
    func testCanonicalWillChangeGuestThenReturnACancelsOuterBAndNeverStartsBLoads() async throws {
        let fixture = Fixture(); try await fixture.seedA(); let original = fixture.canonical.contextTicket(); var once = true
        let subscription = fixture.canonical.objectWillChange.sink {
            if once { once = false; XCTAssertTrue(fixture.transition(nil)); XCTAssertTrue(fixture.transition("A")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "A"); XCTAssertFalse(fixture.canonical.isCurrent(original))
        XCTAssertFalse(fixture.order.contains("loads.B")); XCTAssertEqual(fixture.preferences.preferences.interestTopicIDs, ["A-private"])
        withExtendedLifetime(subscription) {}
    }
    func testCanonicalPostStateReentryIntoCRejectsOuterBLoadsForBothSubscribers() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        var observations: [[String?]] = [[], []]
        func consume(_ value: CanonicalSessionState.Snapshot, index: Int) {
            XCTAssertEqual(value, fixture.canonical.snapshot); observations[index].append(value.userID)
            if once, value.userID == "B" { once = false; XCTAssertTrue(fixture.transition("C")) }
        }
        let first = fixture.canonical.changes.sink { consume($0, index: 0) }
        let second = fixture.canonical.changes.sink { consume($0, index: 1) }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "C"); XCTAssertFalse(fixture.order.contains("loads.B"))
        XCTAssertEqual(fixture.loads.compactMap { $0 }, ["C"])
        for received in observations {
            if let c = received.firstIndex(where: { $0 == "C" }) { XCTAssertFalse(received[c...].contains("B")) }
            else { XCTFail("Nested accepted C should reach both subscribers") }
        }
        withExtendedLifetime((first, second)) {}
    }
    func testIdentityGetterReentryBeforeFirstEffectInvalidatesOriginalTransition() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        fixture.onIdentity = {
            if once { once = false; XCTAssertTrue(fixture.transition("C")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "C")
        XCTAssertFalse(fixture.order.contains("profile.B")); XCTAssertFalse(fixture.order.contains("loads.B"))
    }
    func testIdentityGetterReentryAfterProfileRevocationStillStopsOuterPreferences() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var reads = 0
        fixture.onIdentity = {
            reads += 1
            if reads == 3 { XCTAssertTrue(fixture.transition("C")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertTrue(fixture.order.contains("profile.B")); XCTAssertFalse(fixture.order.contains("preferences.B"))
        XCTAssertEqual(fixture.canonical.snapshot.userID, "C")
    }
    func testFailedCanonicalCommitNeverStartsLoadsEvenWhenProviderUIDStillMatches() {
        let bridge = CanonicalAccountPublication(); var order: [String] = []
        let completed = bridge.performReaderTransition(expectedUserID: "A", currentUserID: { "A" },
            revokeProfile: { order.append("profile"); return true }, revokePreferences: { order.append("preferences"); return true },
            revocationsCurrent: { true },
            dependentSteps: [{ order.append("dependent") }], commitCanonical: { order.append("rejected"); return false },
            startLoads: { order.append("loads") })
        XCTAssertFalse(completed); XCTAssertEqual(order, ["profile", "preferences", "dependent", "rejected"])
    }
    func testRejectedProfileRevocationCannotAnnounceBOrEnterDependentStepsWithAProfile() async throws {
        let fixture = Fixture(); try await fixture.seedA(); let originalProfile = fixture.profile.snapshot; var once = true
        let subscription = fixture.profile.objectWillChange.sink {
            if once { once = false; _ = fixture.profile.changeContext(to: .account("A")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.profile.snapshot, originalProfile); XCTAssertEqual(fixture.canonical.snapshot.userID, "A")
        XCTAssertFalse(fixture.order.contains("preferences.B")); XCTAssertFalse(fixture.order.contains("dependent.B"))
        XCTAssertFalse(fixture.order.contains("canonical.B")); XCTAssertTrue(fixture.loads.isEmpty)
        withExtendedLifetime(subscription) {}
    }
    func testRejectedPreferencesRevocationCannotEnterDependentStepsOrAnnounceB() async throws {
        let fixture = Fixture(); try await fixture.seedA(); let originalPreferences = fixture.preferences.snapshot; var once = true
        let subscription = fixture.preferences.objectWillChange.sink {
            if once { once = false; _ = fixture.preferences.changeContext(to: .account("A")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.preferences.snapshot, originalPreferences); XCTAssertEqual(fixture.canonical.snapshot.userID, "A")
        XCTAssertFalse(fixture.order.contains("dependent.B")); XCTAssertFalse(fixture.order.contains("canonical.B"))
        XCTAssertTrue(fixture.loads.isEmpty)
        withExtendedLifetime(subscription) {}
    }
    func testNewSameUIDPreferenceEpochDuringDependentRevokesOriginalBeforeCanonicalCommit() async throws {
        let fixture = Fixture(); try await fixture.seedA()
        XCTAssertFalse(fixture.transition("B", dependent: {
            _ = fixture.preferences.changeContext(to: .guest)
            _ = fixture.preferences.changeContext(to: .account("B"))
        }))
        await fixture.finishLoads()
        XCTAssertEqual(fixture.preferences.snapshot.userID, "B"); XCTAssertEqual(fixture.canonical.snapshot.userID, "A")
        XCTAssertFalse(fixture.order.contains("canonical.B")); XCTAssertTrue(fixture.loads.isEmpty)
    }
    func testNewSameUIDProfileEpochDuringDependentRevokesOriginalBeforeCanonicalCommit() async throws {
        let fixture = Fixture(); try await fixture.seedA()
        XCTAssertFalse(fixture.transition("B", dependent: {
            _ = fixture.profile.changeContext(to: .guest)
            _ = fixture.profile.changeContext(to: .account("B"))
        }))
        await fixture.finishLoads()
        XCTAssertEqual(fixture.profile.snapshot.context, .account("B")); XCTAssertEqual(fixture.canonical.snapshot.userID, "A")
        XCTAssertFalse(fixture.order.contains("canonical.B")); XCTAssertTrue(fixture.loads.isEmpty)
    }
    func testRevocationGuardFailureStopsEachSubsequentDependentAndCannotRecoverLaterInSameTransition() {
        let bridge = CanonicalAccountPublication(); var authority = true; var order: [String] = []
        let completed = bridge.performReaderTransition(expectedUserID: "A", currentUserID: { "A" },
            revokeProfile: { true }, revokePreferences: { true }, revocationsCurrent: { authority },
            dependentSteps: [
                { order.append("first"); authority = false },
                { order.append("second"); authority = true }
            ], commitCanonical: { order.append("commit"); return true }, startLoads: { order.append("loads") })
        XCTAssertFalse(completed); XCTAssertEqual(order, ["first"])
    }
    func testCanonicalWillChangeCannotCommitBIfItsOriginalPreferencesRevocationWasReplaced() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        let subscription = fixture.canonical.objectWillChange.sink {
            if once {
                once = false
                _ = fixture.preferences.changeContext(to: .guest)
                _ = fixture.preferences.changeContext(to: .account("B"))
            }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "A"); XCTAssertTrue(fixture.loads.isEmpty)
        XCTAssertEqual(fixture.preferences.snapshot.userID, "B"); XCTAssertFalse(fixture.preferences.snapshot.loaded)
        withExtendedLifetime(subscription) {}
    }
    func testCanonicalWillChangeCannotCommitBIfItsOriginalProfileRevocationWasReplaced() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        let subscription = fixture.canonical.objectWillChange.sink {
            if once {
                once = false
                _ = fixture.profile.changeContext(to: .guest)
                _ = fixture.profile.changeContext(to: .account("B"))
            }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "A"); XCTAssertTrue(fixture.loads.isEmpty)
        XCTAssertEqual(fixture.profile.snapshot.context, .account("B")); XCTAssertNil(fixture.profile.snapshot.profile)
        withExtendedLifetime(subscription) {}
    }
    func testPermissionGetterReentryToSameUIDStopsOriginalDependentEvenWhenItsModelTicketsRemainCurrent() async throws {
        let fixture = Fixture(); try await fixture.seedA(); var once = true
        fixture.onRevocationsValidation = {
            if once { once = false; XCTAssertTrue(fixture.transition("B")) }
        }
        XCTAssertFalse(fixture.transition("B")); await fixture.finishLoads()
        XCTAssertEqual(fixture.canonical.snapshot.userID, "B")
        XCTAssertEqual(fixture.order.filter { $0 == "dependent.B" }.count, 1)
        XCTAssertEqual(fixture.order.filter { $0 == "canonical.B" }.count, 1)
        XCTAssertEqual(fixture.order.filter { $0 == "loads.B" }.count, 1)
    }
}
