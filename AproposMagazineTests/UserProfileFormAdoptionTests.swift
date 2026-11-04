import Combine
import XCTest
@testable import Apropos

@MainActor
final class UserProfileFormAdoptionTests: XCTestCase {
    private func profile(_ uid: String, articles: Bool = true) -> UserProfile {
        UserProfile(uid: uid, email: uid + "@example.test", displayName: uid, photoURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
            favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(newArticles: articles),
            readingPreferences: .init(), readArticles: [], bookmarkedArticles: [], readingProgress: [:])
    }
    private func load(_ state: UserProfileState, uid: String = "A") throws {
        state.changeContext(to: .confirmed(userID: uid))
        let ticket = try XCTUnwrap(state.beginLoad(userID: uid))
        XCTAssertTrue(state.acceptLoad(profile(uid), ticket: ticket))
    }
    func testCategoryDraftSurvivesOwnSavePublicationBeforeDevicePersistenceAndSaveFailure() throws {
        let state = UserProfileState()
        // Use one actual state and its post-state subscriber throughout.
        let actual = ProfileFormHarness(state: state);actual.storedCategories = ["old-device-value"]
        actual.appear();try load(state)
        let accepted = actual.adoptions
        actual.selectedCategories = ["new-category"]
        let ticket = try XCTUnwrap(state.beginSave(profile("A", articles: false)))
        XCTAssertEqual(actual.selectedCategories, ["new-category"])
        XCTAssertEqual(actual.storedCategories, ["old-device-value"], "The old defaults still exist during synchronous save publication")
        XCTAssertTrue(state.finishSave(ticket: ticket, message: "Gemning fejlede"))
        XCTAssertEqual(actual.selectedCategories, ["new-category"]);XCTAssertEqual(actual.adoptions, accepted)
        actual.storedCategories = ["new-category"]
        let retry = try XCTUnwrap(state.beginSave(profile("A", articles: false)))
        XCTAssertTrue(state.finishSave(ticket: retry, message: nil))
        XCTAssertEqual(actual.selectedCategories, ["new-category"]);XCTAssertEqual(actual.adoptions, accepted)
    }
    func testReloadStartAndFailurePreserveDraftWhileAcceptedNewLoadAdoptsOnce() throws {
        let state = UserProfileState()
        let actual = ProfileFormHarness(state: state);actual.storedCategories = ["old-device-value"]
        actual.appear();try load(state);let accepted = actual.adoptions
        actual.selectedCategories = ["unsaved-category"]
        let failed = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertNil(state.acceptedLoadVersion);XCTAssertEqual(actual.selectedCategories, ["unsaved-category"])
        XCTAssertTrue(state.failLoad(ticket: failed, message: "Offline"))
        XCTAssertEqual(actual.selectedCategories, ["unsaved-category"]);XCTAssertEqual(actual.adoptions, accepted)
        let retry = try XCTUnwrap(state.beginLoad(userID: "A"))
        actual.storedCategories = ["new-confirmed-value"]
        XCTAssertTrue(state.acceptLoad(profile("A"), ticket: retry))
        XCTAssertEqual(actual.selectedCategories, ["new-confirmed-value"]);XCTAssertEqual(actual.adoptions, accepted + 1)
        actual.selectedCategories = ["later-draft"];actual.appear()
        XCTAssertEqual(actual.selectedCategories, ["later-draft"]);XCTAssertEqual(actual.adoptions, accepted + 1)
    }
    func testOwnerGuestAndUnresolvedEpochsAdoptAndOldLoadCannotRestorePreviousDraft() throws {
        let state = UserProfileState()
        let actual = ProfileFormHarness(state: state);actual.appear();try load(state)
        actual.selectedCategories = ["A-draft"]
        let old = try XCTUnwrap(state.beginLoad(userID: "A"))
        actual.storedCategories = ["B-device-value"];state.changeContext(to: .account("B"))
        XCTAssertNil(state.snapshot.profile);XCTAssertEqual(actual.selectedCategories, ["B-device-value"])
        actual.storedCategories = ["guest-device-value"];state.changeContext(to: .guest)
        XCTAssertEqual(actual.selectedCategories, ["guest-device-value"])
        actual.selectedCategories = ["guest-draft"];actual.appear()
        XCTAssertEqual(actual.selectedCategories, ["guest-draft"])
        actual.storedCategories = [];state.changeContext(to: .unresolved)
        XCTAssertTrue(actual.selectedCategories.isEmpty)
        XCTAssertFalse(state.acceptLoad(profile("A"), ticket: old));XCTAssertTrue(actual.selectedCategories.isEmpty)
    }
    func testNilVersionsAndRepeatedAcceptedSnapshotDoNotForgetLastAcceptedLoad() throws {
        let state = UserProfileState();var adoption = UserProfileFormAdoption()
        XCTAssertTrue(adoption.shouldAdopt(state.snapshot, acceptedLoadVersion: state.acceptedLoadVersion))
        XCTAssertFalse(adoption.shouldAdopt(state.snapshot, acceptedLoadVersion: nil))
        state.changeContext(to: .account("A"))
        XCTAssertTrue(adoption.shouldAdopt(state.snapshot, acceptedLoadVersion: nil))
        let first = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertFalse(adoption.shouldAdopt(state.snapshot, acceptedLoadVersion: nil))
        XCTAssertTrue(state.acceptLoad(profile("A"), ticket: first))
        let acceptedSnapshot = state.snapshot, version = try XCTUnwrap(state.acceptedLoadVersion)
        XCTAssertTrue(adoption.shouldAdopt(acceptedSnapshot, acceptedLoadVersion: version))
        let next = try XCTUnwrap(state.beginLoad(userID: "A"))
        XCTAssertFalse(adoption.shouldAdopt(state.snapshot, acceptedLoadVersion: state.acceptedLoadVersion))
        XCTAssertTrue(state.failLoad(ticket: next, message: "Offline"))
        XCTAssertFalse(adoption.shouldAdopt(state.snapshot, acceptedLoadVersion: state.acceptedLoadVersion))
        XCTAssertFalse(adoption.shouldAdopt(acceptedSnapshot, acceptedLoadVersion: version), "Transient nil versions must not erase the remembered accepted load")
    }
}

@MainActor
private final class ProfileFormHarness {
    let state: UserProfileState
    var storedCategories: Set<String> = []
    var selectedCategories: Set<String> = []
    private(set) var adoptions = 0
    private var policy = UserProfileFormAdoption()
    private var subscription: AnyCancellable?
    init(state: UserProfileState) {
        self.state = state
        subscription = state.changes.sink { [weak self] snapshot in self?.receive(snapshot) }
    }
    func appear() { receive(state.snapshot) }
    private func receive(_ snapshot: UserProfileState.Snapshot) {
        if policy.shouldAdopt(snapshot, acceptedLoadVersion: state.acceptedLoadVersion) {
            selectedCategories = storedCategories;adoptions += 1
        }
    }
}
