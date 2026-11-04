import Combine
import XCTest
@testable import Apropos

@MainActor
final class UserProfileStateTests: XCTestCase {
    private func profile(_ uid: String = "A", name: String = "Navn") -> UserProfile {
        UserProfile(uid: uid, email: uid + "@example.invalid", displayName: name, photoURL: nil,
                    createdAt: Date(timeIntervalSince1970: 100), lastLoginAt: Date(timeIntervalSince1970: 200),
                    favoriteCategories: ["culture"], favoriteAuthors: ["author"], notificationPreferences: .init(),
                    readingPreferences: .init(), readArticles: ["read"], bookmarkedArticles: ["favorite"], readingProgress: ["read": 0.5])
    }
    @discardableResult private func load(_ state: UserProfileState, uid: String = "A", name: String = "Navn") throws -> UserProfileState.LoadTicket {
        _ = state.changeContext(to: .confirmed(userID: uid))
        let ticket = try XCTUnwrap(state.beginLoad(userID: uid))
        XCTAssertTrue(state.acceptLoad(profile(uid, name: name), ticket: ticket))
        return ticket
    }
    func testConstructionIsUnknownEmptyAndCannotLoadOrWrite() {
        let state = UserProfileState()
        XCTAssertEqual(state.snapshot.context, .unresolved); XCTAssertNil(state.snapshot.profile)
        XCTAssertFalse(state.snapshot.isLoading); XCTAssertFalse(state.snapshot.loaded); XCTAssertFalse(state.snapshot.writeReady)
        XCTAssertNil(state.beginLoad(userID: "A")); XCTAssertNil(state.beginSave(profile()))
        XCTAssertTrue(state.isCurrent(state.contextTicket()))
    }
    func testGuestAndInvalidOwnersRemainEmptyAndDoNotGrantTickets() {
        let state = UserProfileState(); _ = state.changeContext(to: .confirmed(userID: nil))
        XCTAssertEqual(state.snapshot.context, .guest); XCTAssertNil(state.beginLoad(userID: "A"))
        for invalid in ["", " A", "A\n", ".", "..", "a/b", "__reserved__", String(repeating: "a", count: 513)] {
            _ = state.changeContext(to: .account(invalid)); XCTAssertEqual(state.snapshot.context, .unresolved)
            XCTAssertNil(state.beginLoad(userID: invalid)); XCTAssertNil(state.snapshot.profile)
        }
    }
    func testAcceptedLoadCommitsOneConsistentSnapshotAndKeepsOriginalEffectTicket() throws {
        let state = UserProfileState(); _ = state.changeContext(to: .confirmed(userID: "A"))
        let ticket = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertTrue(state.snapshot.isLoading); XCTAssertFalse(state.snapshot.loaded)
        XCTAssertTrue(state.acceptLoad(profile(), ticket: ticket)); XCTAssertTrue(state.isCurrent(ticket))
        XCTAssertEqual(state.snapshot.profile, profile()); XCTAssertTrue(state.snapshot.writeReady)
        XCTAssertFalse(state.snapshot.isLoading); XCTAssertNil(state.snapshot.errorMessage)
        XCTAssertFalse(state.acceptLoad(profile(name: "duplicate"), ticket: ticket))
        XCTAssertFalse(state.failLoad(ticket: ticket, message: "late error"))
    }
    func testUIDMismatchCannotAdoptProfileOrCreateSaveAuthority() throws {
        let state = UserProfileState(); _ = state.changeContext(to: .confirmed(userID: "A"))
        XCTAssertNil(state.beginLoad(userID: "B")); let ticket = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertFalse(state.acceptLoad(profile("B"), ticket: ticket)); XCTAssertNil(state.snapshot.profile)
        XCTAssertTrue(state.acceptLoad(profile(), ticket: ticket)); XCTAssertNil(state.beginSave(profile("B")))
    }
    func testNewLoadRevokesPriorSameOwnerLoadAndSave() throws {
        let state = UserProfileState(); let first = try load(state)
        let save = try XCTUnwrap(state.beginSave(profile(name: "edit")))
        XCTAssertFalse(state.isCurrent(first)); XCTAssertTrue(state.isCurrent(save))
        let newer = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertFalse(state.isCurrent(save)); XCTAssertFalse(state.snapshot.writeReady)
        XCTAssertFalse(state.finishSave(ticket: save, message: "old error"))
        XCTAssertTrue(state.acceptLoad(profile(name: "loaded"), ticket: newer))
        XCTAssertEqual(state.snapshot.profile?.displayName, "loaded")
    }
    func testSameOwnerReadFailureRetainsProfileButBlocksWritesUntilSuccessfulFreshLoad() throws {
        let state = UserProfileState(); try load(state)
        let ticket = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertEqual(state.snapshot.profile, profile()); XCTAssertFalse(state.snapshot.loaded)
        XCTAssertTrue(state.failLoad(ticket: ticket, message: "Prøv igen"))
        XCTAssertEqual(state.snapshot.profile, profile()); XCTAssertEqual(state.snapshot.errorMessage, "Prøv igen")
        XCTAssertFalse(state.snapshot.loaded); XCTAssertFalse(state.snapshot.writeReady); XCTAssertNil(state.beginSave(profile()))
        let fresh = try XCTUnwrap(state.beginLoad(userID: "A")); XCTAssertTrue(state.acceptLoad(profile(), ticket: fresh))
        XCTAssertTrue(state.snapshot.writeReady)
    }
    func testOldLoadFailureCannotChangeNewOwnerOrNewerSameOwnerLoad() throws {
        let state = UserProfileState(); _ = state.changeContext(to: .confirmed(userID: "A"))
        let old = try XCTUnwrap(state.beginLoad(userID: "A")); let newer = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertFalse(state.failLoad(ticket: old, message: "old")); XCTAssertTrue(state.snapshot.isLoading)
        XCTAssertTrue(state.acceptLoad(profile(), ticket: newer)); try load(state, uid: "B")
        XCTAssertFalse(state.failLoad(ticket: old, message: "old")); XCTAssertEqual(state.snapshot.profile?.uid, "B")
        XCTAssertNil(state.snapshot.errorMessage)
    }
    func testAccountGuestAccountCreatesNewEpochAndNeverRevivesOldTickets() throws {
        let state = UserProfileState(); let oldLoad = try load(state)
        let oldContext = state.contextTicket(); let oldSave = try XCTUnwrap(state.beginSave(profile()))
        _ = state.changeContext(to: .guest); XCTAssertNil(state.snapshot.profile)
        try load(state); XCTAssertNotEqual(oldContext.generation, state.snapshot.generation)
        XCTAssertFalse(state.isCurrent(oldContext)); XCTAssertFalse(state.isCurrent(oldLoad)); XCTAssertFalse(state.isCurrent(oldSave))
        XCTAssertFalse(state.finishSave(ticket: oldSave, message: "old"))
    }
    func testWillChangeReentryCannotAssignOldLoadOverNewOwner() throws {
        let state = UserProfileState(); _ = state.changeContext(to: .confirmed(userID: "A"))
        let ticket = try XCTUnwrap(state.beginLoad(userID: "A")); var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.changeContext(to: .confirmed(userID: "B")) }
        }
        XCTAssertFalse(state.acceptLoad(profile(), ticket: ticket)); XCTAssertEqual(state.snapshot.context, .account("B"))
        XCTAssertNil(state.snapshot.profile); withExtendedLifetime(subscription) {}
    }
    func testNestedWillChangeReturnToStillCommittedOwnerCancelsOuterTransition() throws {
        let state = UserProfileState(); try load(state); let original = state.snapshot
        var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.changeContext(to: .confirmed(userID: "A")) }
        }
        XCTAssertNil(state.changeContext(to: .confirmed(userID: "B")))
        XCTAssertEqual(state.snapshot, original); withExtendedLifetime(subscription) {}
    }
    func testReentrantWillChangeNewLoadPreventsOuterOptimisticSaveAssignment() throws {
        let state = UserProfileState(); try load(state); var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.beginLoad(userID: "A") }
        }
        XCTAssertNil(state.beginSave(profile(name: "stale edit")))
        XCTAssertEqual(state.snapshot.profile?.displayName, "Navn"); XCTAssertTrue(state.snapshot.isLoading)
        XCTAssertFalse(state.snapshot.writeReady); withExtendedLifetime(subscription) {}
    }
    func testEachSubscriberRejectsOuterOwnerAfterNestedOwnerDelivery() throws {
        let state = UserProfileState(); _ = state.changeContext(to: .confirmed(userID: "A"))
        let ticket = try XCTUnwrap(state.beginLoad(userID: "A")); var transitioned = false
        var second: [UserProfileState.Snapshot] = []
        let firstSubscription = state.changes.sink { candidate in
            XCTAssertEqual(candidate, state.snapshot)
            if !transitioned, candidate.profile?.uid == "A" {
                transitioned = true; _ = state.changeContext(to: .confirmed(userID: "B"))
                if let load = state.beginLoad(userID: "B") { _ = state.acceptLoad(self.profile("B"), ticket: load) }
            }
        }
        let secondSubscription = state.changes.sink { candidate in
            XCTAssertEqual(candidate, state.snapshot); second.append(candidate)
        }
        XCTAssertFalse(state.acceptLoad(profile(), ticket: ticket)); XCTAssertEqual(state.snapshot.profile?.uid, "B")
        if let b = second.firstIndex(where: { $0.context == .account("B") }) {
            XCTAssertFalse(second[b...].contains(where: { $0.context == .account("A") }))
        } else { XCTFail("Replacement owner should be delivered") }
        withExtendedLifetime((firstSubscription, secondSubscription)) {}
    }
    func testEachSubscriberRejectsStaleSameGenerationRevisionAfterNestedSave() throws {
        let state = UserProfileState(); try load(state); var replaced = false
        let first = state.changes.sink { candidate in
            if !replaced, candidate.profile?.displayName == "outer" {
                replaced = true; _ = state.beginSave(self.profile(name: "inner"))
            }
        }
        let second = state.changes.sink { candidate in XCTAssertEqual(candidate, state.snapshot) }
        XCTAssertNil(state.beginSave(profile(name: "outer"))); XCTAssertEqual(state.snapshot.profile?.displayName, "inner")
        withExtendedLifetime((first, second)) {}
    }
    func testNewerSaveKeepsItsProfileAndRejectsOlderReceipt() throws {
        let state = UserProfileState(); try load(state)
        let first = try XCTUnwrap(state.beginSave(profile(name: "first")))
        let second = try XCTUnwrap(state.beginSave(profile(name: "second")))
        XCTAssertFalse(state.finishSave(ticket: first, message: "old error")); XCTAssertNil(state.snapshot.errorMessage)
        XCTAssertTrue(state.finishSave(ticket: second, message: nil)); XCTAssertTrue(state.isCurrent(second))
        XCTAssertEqual(state.snapshot.profile?.displayName, "second")
        XCTAssertFalse(state.finishSave(ticket: second, message: "duplicate")); XCTAssertNil(state.snapshot.errorMessage)
    }
    func testSaveFailureIsScopedAndPreservesMatchingLoadedProfile() throws {
        let state = UserProfileState(); try load(state)
        let save = try XCTUnwrap(state.beginSave(profile(name: "edit")))
        XCTAssertTrue(state.finishSave(ticket: save, message: "Kunne ikke gemme"))
        XCTAssertEqual(state.snapshot.profile?.displayName, "edit"); XCTAssertTrue(state.snapshot.writeReady)
        XCTAssertEqual(state.snapshot.errorMessage, "Kunne ikke gemme")
        _ = state.changeContext(to: .guest); XCTAssertNil(state.snapshot.errorMessage); XCTAssertNil(state.snapshot.profile)
    }
    func testFailedSignoutRestoresConfirmedProfileWithFreshEpochAndNoOldTickets() throws {
        let state = UserProfileState(); let load = try self.load(state)
        let context = state.contextTicket(); let save = try XCTUnwrap(state.beginSave(profile(name: "edit")))
        let suspended = try XCTUnwrap(state.suspend(ticket: context))
        XCTAssertEqual(state.snapshot.context, .unresolved); XCTAssertNil(state.snapshot.profile)
        XCTAssertFalse(state.isCurrent(context)); XCTAssertFalse(state.isCurrent(load)); XCTAssertFalse(state.isCurrent(save))
        let restored = try XCTUnwrap(state.restore(suspended, confirmedUserID: "A"))
        XCTAssertTrue(state.isCurrent(restored)); XCTAssertEqual(state.snapshot.profile?.displayName, "edit")
        XCTAssertTrue(state.snapshot.writeReady); XCTAssertNotEqual(restored.generation, context.generation)
        XCTAssertFalse(state.isCurrent(save)); XCTAssertNil(state.restore(suspended, confirmedUserID: "A"))
    }
    func testStaleSuspensionOrClearCannotEraseOrRestoreIntoReplacementAccount() throws {
        let state = UserProfileState(); try load(state); let old = state.contextTicket()
        let suspended = try XCTUnwrap(state.suspend(ticket: old)); try load(state, uid: "B")
        XCTAssertNil(state.restore(suspended, confirmedUserID: "A")); XCTAssertFalse(state.clearForSignOut(ticket: old))
        XCTAssertEqual(state.snapshot.profile?.uid, "B")
        let other = UserProfileState(); XCTAssertNil(other.restore(suspended, confirmedUserID: "A"))
    }
    func testWrongRestoreUIDAndOldClearAfterNewSameUIDCannotAcquireAuthority() throws {
        let state = UserProfileState(); try load(state); let original = state.contextTicket()
        let suspended = try XCTUnwrap(state.suspend(ticket: original))
        XCTAssertNil(state.restore(suspended, confirmedUserID: "B")); XCTAssertNil(state.snapshot.profile)
        _ = state.changeContext(to: .guest); try load(state)
        XCTAssertFalse(state.clearForSignOut(ticket: original)); XCTAssertNil(state.restore(suspended, confirmedUserID: "A"))
        XCTAssertEqual(state.snapshot.profile?.uid, "A")
    }
    func testContextTicketReadAndRepeatedCanonicalContextAreIdempotent() throws {
        let state = UserProfileState(); try load(state); let before = state.snapshot; let ticket = state.contextTicket()
        XCTAssertTrue(state.isCurrent(ticket)); XCTAssertEqual(state.changeContext(to: .confirmed(userID: "A")), ticket)
        XCTAssertEqual(state.snapshot, before); XCTAssertTrue(state.isCurrent(ticket))
    }
    func testActualSDKFreeProfileRoundTripPreservesAllExistingFields() throws {
        var value = profile(); value.notificationPreferences.weeklyDigest = true
        value.readingPreferences.fontSize = .extraLarge
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
    }
}
