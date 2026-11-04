import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderRecommendationSelectionTests: XCTestCase {
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var actualUID: String?
        var loadFailure = false
        var saveFailure = false
        var onRead: (() async -> Void)?
        lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [unowned self] in
            .init(actualUID: self.actualUID, canonicalUID: self.canonical.snapshot.userID)
        }, load: { [unowned self] context, valid in
            guard valid() else { throw CancellationError() }
            await self.onRead?()
            if self.loadFailure { throw URLError(.notConnectedToInternet) }
            return .init(preferences: ReaderPreferences(interestTopicIDs: [context.userID! + "-interest"]), isFromCache: false)
        }, save: { [unowned self] _, _ in if self.saveFailure { throw URLError(.notConnectedToInternet) } }, schedule: { _ in {} })
        func account(_ uid: String, verified: Bool = false) -> ReaderAccountSession {
            ReaderAccountSession(uid: uid, email: uid + "@example.invalid", isEmailVerified: verified)
        }
        func select(_ uid: String?) async {
            actualUID = uid
            let context = preferences.changeContext(to: .confirmed(userID: uid))
            _ = canonical.adopt(uid.map { account($0) })
            preferences.start()
            if let context { await preferences.load(context) }
        }
        var input: ReaderRecommendationAccountInput {
            ReaderRecommendationSelection.capture(canonical: canonical.snapshot, preferences: preferences.snapshot)
        }
    }
    func testActualInitialCaptureOfUnresolvedModelsHasNoAccountOrPrivateInterests() {
        let fixture = Fixture(), initial = Fixture()
        XCTAssertNil(fixture.input.canonicalUserID); XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
        XCTAssertNil(fixture.input.preferencesGeneration)
        XCTAssertNotEqual(fixture.input.canonicalGeneration, initial.input.canonicalGeneration)
    }
    func testInitialCaptureOfAlreadyLoadedMatchingOwnerUsesItsAcceptedInterests() async {
        let fixture = Fixture(); await fixture.select("A")
        XCTAssertEqual(fixture.input.canonicalUserID, "A"); XCTAssertEqual(fixture.input.interestTopicIDs, ["A-interest"])
        XCTAssertEqual(fixture.input.preferencesGeneration, fixture.preferences.snapshot.generation)
    }
    func testActualMismatchedCommittedModelsCannotPairBUIDWithAInterests() async {
        let fixture = Fixture(); await fixture.select("A")
        _ = fixture.canonical.adopt(fixture.account("B"))
        XCTAssertEqual(fixture.preferences.preferences.interestTopicIDs, ["A-interest"])
        XCTAssertEqual(fixture.input.canonicalUserID, "B"); XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
        XCTAssertNil(fixture.input.preferencesGeneration)
    }
    func testGuestAndUnresolvedCanonicalCannotUseStillHeldPrivatePreferences() async {
        let fixture = Fixture(); await fixture.select("A")
        _ = fixture.canonical.adopt(nil)
        XCTAssertNil(fixture.input.canonicalUserID); XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
        _ = fixture.canonical.suspend()
        XCTAssertNil(fixture.input.canonicalUserID); XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
    }
    func testSameOwnerVerifiedRefreshPreservesAccountBindingAndLoadedInterests() async throws {
        let fixture = Fixture(); await fixture.select("A"); let before = fixture.input
        let ticket = try XCTUnwrap(fixture.canonical.beginRefresh(context: fixture.canonical.contextTicket()))
        XCTAssertEqual(fixture.input, before)
        XCTAssertTrue(fixture.canonical.acceptRefresh(fixture.account("A", verified: true), ticket: ticket))
        XCTAssertEqual(fixture.input, before)
    }
    func testSameOwnerReadFailureRetainsLastAcceptedInterestsButKeepsWritesBlocked() async {
        let fixture = Fixture(); await fixture.select("A"); fixture.loadFailure = true
        await fixture.preferences.retry(fixture.preferences.contextTicket())
        XCTAssertEqual(fixture.preferences.preferences.interestTopicIDs, ["A-interest"])
        XCTAssertFalse(fixture.preferences.snapshot.loaded); XCTAssertNotNil(fixture.preferences.snapshot.errorMessage)
        XCTAssertEqual(fixture.input.canonicalUserID, "A"); XCTAssertEqual(fixture.input.interestTopicIDs, ["A-interest"])
        XCTAssertNil(fixture.preferences.captureSave(ids: ["new"], context: fixture.preferences.contextTicket()))
    }
    func testSameOwnerHeldRetryKeepsLastAcceptedInterestsWhileInitialHeldReadUsesNone() async {
        let fixture = Fixture(); await fixture.select("A"); let held = RecommendationReadGate()
        fixture.onRead = { await held.hold() }
        let retry = Task { await fixture.preferences.retry(fixture.preferences.contextTicket()) }
        await held.waitUntilHeld()
        XCTAssertTrue(fixture.preferences.snapshot.isLoading); XCTAssertFalse(fixture.preferences.snapshot.loaded)
        XCTAssertEqual(fixture.input.interestTopicIDs, ["A-interest"])
        await held.release(); await retry.value
        let nextHeld = RecommendationReadGate(); fixture.onRead = { await nextHeld.hold() }
        let newOwner = Task { await fixture.select("B") }
        await nextHeld.waitUntilHeld()
        XCTAssertEqual(fixture.input.canonicalUserID, "B"); XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
        XCTAssertNil(fixture.preferences.snapshot.loadVersion)
        await nextHeld.release(); await newOwner.value
        XCTAssertEqual(fixture.input.interestTopicIDs, ["B-interest"])
    }
    func testInitialFailedReadHasNoAcceptedPreferencesToUseForRecommendations() async {
        let fixture = Fixture(); fixture.loadFailure = true; await fixture.select("A")
        XCTAssertNil(fixture.preferences.snapshot.loadVersion); XCTAssertFalse(fixture.preferences.snapshot.loaded)
        XCTAssertEqual(fixture.input.canonicalUserID, "A"); XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
    }
    func testFailedSaveKeepsActuallyLoadedInterestsAsRecommendationInput() async throws {
        let fixture = Fixture(); await fixture.select("A"); fixture.saveFailure = true
        let request = try XCTUnwrap(fixture.preferences.captureSave(ids: ["new"], context: fixture.preferences.contextTicket()))
        let saved = await fixture.preferences.saveInterests(request)
        XCTAssertFalse(saved); XCTAssertNotNil(fixture.preferences.snapshot.errorMessage)
        XCTAssertTrue(fixture.preferences.snapshot.loaded); XCTAssertEqual(fixture.input.interestTopicIDs, ["A-interest"])
    }
    func testSameUIDAfterGuestHasNewCanonicalAndPreferencesEpochBeforeInterestsReturn() async {
        let fixture = Fixture(); await fixture.select("A"); let first = fixture.input
        await fixture.select(nil)
        XCTAssertTrue(fixture.input.interestTopicIDs.isEmpty)
        await fixture.select("A"); let newer = fixture.input
        XCTAssertEqual(newer.interestTopicIDs, ["A-interest"])
        XCTAssertNotEqual(newer.canonicalGeneration, first.canonicalGeneration)
        XCTAssertNotEqual(newer.preferencesGeneration, first.preferencesGeneration)
    }
    func testActualPreferencesSubscriptionCapturesOnlyCoherentCurrentSnapshot() async {
        let fixture = Fixture(); await fixture.select("A")
        var inputs: [ReaderRecommendationAccountInput] = []
        let subscription = fixture.preferences.changes.sink { snapshot in
            XCTAssertEqual(snapshot, fixture.preferences.snapshot); inputs.append(fixture.input)
        }
        await fixture.select("B")
        XCTAssertTrue(inputs.allSatisfy { $0.canonicalUserID != "B" || !$0.interestTopicIDs.contains("A-interest") })
        XCTAssertEqual(inputs.last?.interestTopicIDs, ["B-interest"])
        withExtendedLifetime(subscription) {}
    }
    func testConfirmedGuestPreferencesReachActualRecommendationSelection() async {
        let fixture = Fixture(); await fixture.select(nil)
        let input = ReaderRecommendationSelection.capture(canonical: fixture.canonical.snapshot,
            preferences: fixture.preferences.snapshot, guestInterestTopicIDs: ["music", "culture"])
        XCTAssertNil(input.canonicalUserID)
        XCTAssertNil(input.preferencesGeneration)
        XCTAssertEqual(input.interestTopicIDs, ["culture", "music"])
        XCTAssertEqual(input.canonicalGeneration, fixture.canonical.snapshot.generation)
    }

    func testGuestInterestsRequireBothCommittedContextsAndNeverFillUnresolvedState() async {
        let fixture = Fixture()
        func input() -> ReaderRecommendationAccountInput {
            ReaderRecommendationSelection.capture(canonical: fixture.canonical.snapshot,
                preferences: fixture.preferences.snapshot, guestInterestTopicIDs: ["guest-only"])
        }
        XCTAssertTrue(input().interestTopicIDs.isEmpty)
        fixture.canonical.adopt(nil)
        XCTAssertTrue(input().interestTopicIDs.isEmpty, "Unresolved preferences must not look like confirmed guest")
        await fixture.select(nil)
        XCTAssertEqual(input().interestTopicIDs, ["guest-only"])
        fixture.canonical.suspend()
        XCTAssertTrue(input().interestTopicIDs.isEmpty)
        await fixture.select("A")
        fixture.canonical.adopt(nil)
        XCTAssertTrue(input().interestTopicIDs.isEmpty, "Held account preferences prevent a mixed guest capture")
    }

    func testGuestInterestsNeverLeakToLoadedOrMismatchedAccounts() async {
        let fixture = Fixture()
        func input() -> ReaderRecommendationAccountInput {
            ReaderRecommendationSelection.capture(canonical: fixture.canonical.snapshot,
                preferences: fixture.preferences.snapshot, guestInterestTopicIDs: ["guest-only"])
        }
        await fixture.select("A")
        XCTAssertEqual(input().interestTopicIDs, ["A-interest"])
        fixture.canonical.adopt(fixture.account("B"))
        XCTAssertTrue(input().interestTopicIDs.isEmpty)
        await fixture.select("B")
        XCTAssertEqual(input().interestTopicIDs, ["B-interest"])
        XCTAssertFalse(input().interestTopicIDs.contains("guest-only"))
    }

    func testGuestInterestSelectionNormalizesDeduplicatesAndBoundsTwenty() async {
        let fixture = Fixture(); await fixture.select(nil)
        let input = ReaderRecommendationSelection.capture(canonical: fixture.canonical.snapshot,
            preferences: fixture.preferences.snapshot,
            guestInterestTopicIDs: [" music ", "music", "", "../bad", "bad/path", "bad\u{0001}", String(repeating: "x", count: 129)]
                + (0..<30).map { "topic-\($0)" })
        XCTAssertEqual(input.interestTopicIDs.count, 20)
        XCTAssertEqual(input.interestTopicIDs, Array(Set(["music"] + (0..<30).map { "topic-\($0)" }).sorted().prefix(20)))
    }

    func testActualGuestStorePublicationUpdatesSelectionWithoutAccountTransfer() async {
        let fixture = Fixture(); await fixture.select(nil)
        var data: Data?
        let store = GuestReaderInterestsModel(storage: .init(read: { data }, write: { data = $0 }))
        store.start()
        var selections: [ReaderRecommendationAccountInput] = []
        let subscription = store.changes.sink { snapshot in
            XCTAssertEqual(snapshot, store.snapshot)
            selections.append(ReaderRecommendationSelection.capture(canonical: fixture.canonical.snapshot,
                preferences: fixture.preferences.snapshot, guestInterestTopicIDs: snapshot.selectedTopicIDs))
        }
        XCTAssertTrue(store.save(["music"], context: fixture.canonical.contextTicket(), isCurrent: fixture.canonical.isCurrent))
        XCTAssertEqual(selections.last?.interestTopicIDs, ["music"])
        await fixture.select("A")
        let account = ReaderRecommendationSelection.capture(canonical: fixture.canonical.snapshot,
            preferences: fixture.preferences.snapshot, guestInterestTopicIDs: store.selectedTopicIDs)
        XCTAssertEqual(store.selectedTopicIDs, ["music"])
        XCTAssertEqual(account.interestTopicIDs, ["A-interest"])
        withExtendedLifetime(subscription) {}
    }

}

private actor RecommendationReadGate {
    private var held: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation; let waiting = observer; observer = nil; waiting?.resume()
        }
    }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { let value = held; held = nil; value?.resume() }
}
