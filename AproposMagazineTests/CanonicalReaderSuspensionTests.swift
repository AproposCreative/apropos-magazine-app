import Combine
import XCTest
@testable import Apropos

@MainActor
final class CanonicalReaderSuspensionTests: XCTestCase {
    func testAcceptedPrivateRevocationsPrecedeCanonicalAndEveryDependent() async {
        let h = SuspensionHarness()
        await h.loadPreferences()
        XCTAssertEqual(h.preferences.preferences.interestTopicIDs, ["private-A"])
        var order: [String] = []
        let profile = h.profile.changes.sink { if $0.context == .unresolved { order.append("profile") } }
        let preferences = h.preferences.changes.sink { if $0.context == .unresolved { order.append("preferences") } }
        let canonical = h.canonical.changes.sink { value in
            if value.context == .unresolved {
                XCTAssertEqual(h.profile.snapshot.context, .unresolved)
                XCTAssertEqual(h.preferences.snapshot.context, .unresolved)
                XCTAssertNil(h.profile.snapshot.profile)
                XCTAssertTrue(h.preferences.snapshot.preferences.interestTopicIDs.isEmpty)
                XCTAssertFalse(h.preferences.snapshot.loaded)
                order.append("canonical")
            }
        }
        let ticket = h.perform(dependents: [{ order.append("first") }, { order.append("second") }])
        XCTAssertNotNil(ticket); XCTAssertTrue(ticket.map { h.canonical.isCurrent($0.canonical) } ?? false)
        XCTAssertEqual(order, ["profile", "preferences", "canonical", "first", "second"])
        XCTAssertEqual(h.actualUID, "A", "The helper suspends local authority before the actual provider signout")
        withExtendedLifetime((profile, preferences, canonical)) {}
    }
    func testRejectedProfileSuspensionCannotSuspendPreferencesCanonicalOrDependents() {
        let h = SuspensionHarness(); var reentered = false, dependent = 0
        let originalPreferences = h.preferences.snapshot
        let originalCanonical = h.canonical.snapshot
        let subscription = h.profile.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.profile.changeContext(to: .account("A")) }
        }
        XCTAssertNil(h.perform(dependents: [{ dependent += 1 }]))
        XCTAssertEqual(h.profile.snapshot.profile?.uid, "A")
        XCTAssertEqual(h.preferences.snapshot, originalPreferences)
        XCTAssertEqual(h.canonical.snapshot, originalCanonical); XCTAssertEqual(dependent, 0)
        withExtendedLifetime(subscription) {}
    }
    func testRejectedPreferencesSuspensionCannotPublishCanonicalOrDependents() async {
        let h = SuspensionHarness(); await h.loadPreferences(); var reentered = false, dependent = 0
        let originalCanonical = h.canonical.snapshot
        let subscription = h.preferences.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.preferences.changeContext(to: .account("A")) }
        }
        XCTAssertNil(h.perform(dependents: [{ dependent += 1 }]))
        XCTAssertEqual(h.profile.snapshot.context, .unresolved)
        XCTAssertEqual(h.preferences.snapshot.context, .account("A"))
        XCTAssertEqual(h.preferences.preferences.interestTopicIDs, ["private-A"])
        XCTAssertTrue(h.preferences.hasLoaded)
        XCTAssertEqual(h.canonical.snapshot, originalCanonical); XCTAssertEqual(dependent, 0)
        withExtendedLifetime(subscription) {}
    }
    func testCanonicalWillChangeRestoringProfileRejectsTheCanonicalAssignment() {
        let h = SuspensionHarness(); var reentered = false, dependent = 0
        let originalCanonical = h.canonical.snapshot
        let subscription = h.canonical.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.profile.changeContext(to: .account("A")) }
        }
        XCTAssertNil(h.perform(dependents: [{ dependent += 1 }]))
        XCTAssertEqual(h.canonical.snapshot, originalCanonical)
        XCTAssertEqual(h.profile.snapshot.context, .account("A")); XCTAssertEqual(dependent, 0)
        withExtendedLifetime(subscription) {}
    }
    func testCanonicalWillChangeCannotBorrowAReplacementUnresolvedProfileTicket() {
        let h = SuspensionHarness(); var reentered = false, dependent = 0
        let originalCanonical = h.canonical.snapshot
        let subscription = h.canonical.objectWillChange.sink {
            if !reentered {
                reentered = true
                _ = h.profile.changeContext(to: .account("A"))
                _ = h.profile.changeContext(to: .unresolved)
            }
        }
        XCTAssertNil(h.perform(dependents: [{ dependent += 1 }]))
        XCTAssertEqual(h.profile.snapshot.context, .unresolved)
        XCTAssertEqual(h.canonical.snapshot, originalCanonical); XCTAssertEqual(dependent, 0)
        withExtendedLifetime(subscription) {}
    }
    func testCanonicalWillChangeCannotBorrowAReplacementUnresolvedPreferencesTicket() {
        let h = SuspensionHarness(); var reentered = false, dependent = 0
        let originalCanonical = h.canonical.snapshot
        let subscription = h.canonical.objectWillChange.sink {
            if !reentered {
                reentered = true
                _ = h.preferences.changeContext(to: .account("A"))
                _ = h.preferences.changeContext(to: .unresolved)
            }
        }
        XCTAssertNil(h.perform(dependents: [{ dependent += 1 }]))
        XCTAssertEqual(h.preferences.snapshot.context, .unresolved)
        XCTAssertEqual(h.canonical.snapshot, originalCanonical); XCTAssertEqual(dependent, 0)
        withExtendedLifetime(subscription) {}
    }
    func testNewAccountDuringFirstDependentStopsAllLaterEffects() {
        let h = SuspensionHarness(); var first = 0, later = 0
        XCTAssertNil(h.perform(dependents: [{ first += 1; h.select("B") }, { later += 1 }]))
        XCTAssertEqual(first, 1); XCTAssertEqual(later, 0)
        XCTAssertEqual(h.canonical.snapshot.userID, "B")
        XCTAssertEqual(h.profile.snapshot.context, .account("B"))
        XCTAssertEqual(h.preferences.snapshot.userID, "B")
    }
    func testSameUIDReturnDuringFirstDependentDoesNotReviveOriginalSuspension() {
        let h = SuspensionHarness(); var first = 0, later = 0
        XCTAssertNil(h.perform(dependents: [{ first += 1; h.select(nil); h.select("A") }, { later += 1 }]))
        XCTAssertEqual(first, 1); XCTAssertEqual(later, 0); XCTAssertEqual(h.canonical.snapshot.userID, "A")
    }
    func testInitialIdentityGetterReentryCannotRevokeTheNewerOwner() {
        let h = SuspensionHarness(); let original = h.context
        h.onIdentityRead = { h.onIdentityRead = nil; h.select("B") }
        XCTAssertNil(h.perform(context: original))
        XCTAssertEqual(h.canonical.snapshot.userID, "B")
        XCTAssertEqual(h.profile.snapshot.context, .account("B"))
        XCTAssertEqual(h.preferences.snapshot.userID, "B")
        XCTAssertEqual(h.profileSuspensions, 0)
    }
    func testIdentityGetterAfterCanonicalCommitCannotBorrowReplacementPrivateTickets() {
        let h = SuspensionHarness(); var dependent = 0
        h.onIdentityRead = {
            if h.canonical.snapshot.context == .unresolved {
                h.onIdentityRead = nil
                _ = h.preferences.changeContext(to: .account("A"))
                _ = h.preferences.changeContext(to: .unresolved)
            }
        }
        XCTAssertNil(h.perform(dependents: [{ dependent += 1 }]))
        XCTAssertEqual(dependent, 0)
        XCTAssertEqual(h.canonical.snapshot.context, .unresolved)
        XCTAssertEqual(h.preferences.snapshot.context, .unresolved)
    }
    func testFinalSDKBoundaryIdentityReadCannotRestoreProfileUnderOriginalCanonicalSuspension() throws {
        let h = SuspensionHarness()
        let ticket = try XCTUnwrap(h.perform())
        let valid = CanonicalReaderSuspension.isCurrent(ticket, canonical: h.canonical, profile: h.profile,
            preferences: h.preferences, currentUserID: {
                _ = h.profile.changeContext(to: .account("A"))
                return "A"
            })
        XCTAssertFalse(valid)
        XCTAssertTrue(h.canonical.isCurrent(ticket.canonical))
        XCTAssertEqual(h.canonical.snapshot.context, .unresolved)
        XCTAssertEqual(h.profile.snapshot.context, .account("A"))
    }
    func testFinalSDKBoundaryIdentityReadCannotBorrowAReplacementUnresolvedPreferencesTicket() throws {
        let h = SuspensionHarness()
        let ticket = try XCTUnwrap(h.perform())
        let valid = CanonicalReaderSuspension.isCurrent(ticket, canonical: h.canonical, profile: h.profile,
            preferences: h.preferences, currentUserID: {
                _ = h.preferences.changeContext(to: .account("A"))
                _ = h.preferences.changeContext(to: .unresolved)
                return "A"
            })
        XCTAssertFalse(valid)
        XCTAssertTrue(h.canonical.isCurrent(ticket.canonical))
        XCTAssertEqual(h.preferences.snapshot.context, .unresolved)
    }
    func testGuestAndForeignModelTicketsCannotStartSuspension() {
        let h = SuspensionHarness(); let other = SuspensionHarness()
        XCTAssertNil(h.perform(context: other.context))
        h.select(nil)
        XCTAssertNil(h.perform(context: h.canonical.contextTicket()))
        XCTAssertEqual(h.profileSuspensions, 0)
    }
}

@MainActor
private final class SuspensionHarness {
    let canonical = CanonicalSessionState()
    let profile = UserProfileState()
    lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [weak self] in
        .init(actualUID: self?.actualUID, canonicalUID: self?.canonical.snapshot.userID)
    }, load: { context, _ in
        .init(preferences: ReaderPreferences(interestTopicIDs: ["private-" + (context.userID ?? "unknown")]), isFromCache: false)
    }, save: { _, _ in })
    var actualUID: String? = "A"
    var onIdentityRead: (() -> Void)?
    var profileSuspensions = 0
    var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
    init() {
        select("A")
        let load = profile.beginLoad(userID: "A")!
        _ = profile.acceptLoad(UserProfile(uid: "A", email: "a@example.invalid", displayName: "A", photoURL: nil,
            createdAt: Date(timeIntervalSince1970: 100), lastLoginAt: Date(timeIntervalSince1970: 200),
            favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
            readArticles: ["private-A"], bookmarkedArticles: [], readingProgress: [:]), ticket: load)
    }
    func loadPreferences() async {
        preferences.start()
        await preferences.load(preferences.contextTicket())
    }
    func select(_ uid: String?) {
        actualUID = uid
        _ = profile.changeContext(to: .confirmed(userID: uid))
        _ = preferences.changeContext(to: .confirmed(userID: uid))
        _ = canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: false) })
    }
    func perform(context original: CanonicalSessionState.ContextTicket? = nil,
                 dependents: [() -> Void] = []) -> CanonicalReaderSuspension.Ticket? {
        CanonicalReaderSuspension.perform(canonical: canonical, profile: profile, preferences: preferences,
            context: original ?? context,
            currentUserID: { [self] in onIdentityRead?(); return actualUID },
            suspendProfile: { [self] in
                profileSuspensions += 1
                _ = profile.suspend(ticket: profile.contextTicket())
            }, dependentSteps: dependents)
    }
}
