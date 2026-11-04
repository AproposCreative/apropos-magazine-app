import XCTest
@testable import Apropos

@MainActor
final class ReaderInterestDraftTests: XCTestCase {
    private let generation = UUID()
    private let firstLoad = UUID()

    private func loaded(_ ids: [String]) -> ReaderInterestDraft {
        var draft = ReaderInterestDraft()
        draft.adopt(generation: generation, loadVersion: firstLoad, loaded: true, interestTopicIDs: ids)
        return draft
    }

    func testCleanDraftFollowsAcceptedServerRefresh() {
        var draft = loaded(["film", "music"])
        XCTAssertEqual(draft.selected, ["film", "music"])
        XCTAssertFalse(draft.isDirty)
        let nextLoad = UUID()
        draft.adopt(generation: generation, loadVersion: nextLoad, loaded: true, interestTopicIDs: ["culture"])
        XCTAssertEqual(draft.selected, ["culture"])
        XCTAssertEqual(draft.loadVersion, nextLoad)
        XCTAssertFalse(draft.isDirty)
    }

    func testRefreshPreservesLocalDeltaAndAdoptsIndependentRemoteDelta() {
        var draft = loaded(["film", "music", "gaming"])
        draft.toggle("film")
        draft.toggle("books")
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: ["film", "music", "culture"])
        XCTAssertEqual(draft.selected, ["music", "culture", "books"])
        XCTAssertTrue(draft.isDirty)
    }

    func testUntouchedTopicRemovedRemotelyIsNeverRestoredByLocalAddition() {
        var draft = loaded(["film", "music"])
        draft.toggle("books")
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true, interestTopicIDs: ["music"])
        XCTAssertEqual(draft.selected, ["music", "books"])
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true, interestTopicIDs: ["music"])
        XCTAssertFalse(draft.selected.contains("film"))
    }

    func testExplicitLocalRemovalSurvivesRepeatedRemoteRefreshes() {
        var draft = loaded(["film", "music"])
        draft.toggle("film")
        for _ in 0..<3 {
            draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                        interestTopicIDs: ["film", "music", "culture"])
            XCTAssertEqual(draft.selected, ["music", "culture"])
            XCTAssertTrue(draft.isDirty)
        }
    }

    func testRemoveThenReaddBaselineTopicHasNoDeltaAgainstRemoteRemoval() {
        var draft = loaded(["film", "music"])
        draft.toggle("film")
        draft.toggle("film")
        XCTAssertFalse(draft.isDirty)
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true, interestTopicIDs: ["music"])
        XCTAssertEqual(draft.selected, ["music"])
        XCTAssertFalse(draft.isDirty)
    }

    func testAddThenRemoveNewTopicHasNoDeltaAgainstRemoteAddition() {
        var draft = loaded(["music"])
        draft.toggle("film")
        draft.toggle("film")
        XCTAssertFalse(draft.isDirty)
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: ["music", "film"])
        XCTAssertEqual(draft.selected, ["music", "film"])
        XCTAssertFalse(draft.isDirty)
    }

    func testAcceptedSaveAtSameLoadVersionCleansDraftBeforeLaterRefresh() {
        var draft = loaded(["music", "film"])
        draft.toggle("film")
        draft.toggle("books")
        // An accepted save changes preferences without creating a new loadVersion.
        draft.adopt(generation: generation, loadVersion: firstLoad, loaded: true,
                    interestTopicIDs: ["music", "books"])
        XCTAssertFalse(draft.isDirty)
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true, interestTopicIDs: ["culture"])
        XCTAssertEqual(draft.selected, ["culture"])
        XCTAssertFalse(draft.isDirty)
    }

    func testPartialServerMatchAcknowledgesOnlyMatchedLocalChanges() {
        var draft = loaded(["music", "film"])
        draft.toggle("film")
        draft.toggle("books")
        draft.toggle("gaming")
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: ["music", "books"])
        XCTAssertEqual(draft.selected, ["music", "books", "gaming"])
        XCTAssertTrue(draft.isDirty)
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true, interestTopicIDs: ["music"])
        XCTAssertEqual(draft.selected, ["music", "gaming"], "The acknowledged books edit is no longer an unsaved addition")
    }

    func testWaitingAndRepeatedSnapshotsPreserveUnsavedDraft() {
        var draft = loaded(["music"])
        draft.toggle("books")
        draft.adopt(generation: generation, loadVersion: nil, loaded: false, interestTopicIDs: [])
        draft.adopt(generation: generation, loadVersion: firstLoad, loaded: true, interestTopicIDs: ["music"])
        draft.adopt(generation: generation, loadVersion: nil, loaded: true, interestTopicIDs: ["film"])
        XCTAssertEqual(draft.selected, ["music", "books"])
        XCTAssertEqual(draft.loadVersion, firstLoad)
        XCTAssertTrue(draft.isDirty)
    }

    func testNewGenerationClearsDraftBeforeLoadAndCannotRestorePreviousAccountEdits() {
        var draft = loaded(["music"])
        draft.toggle("books")
        let secondGeneration = UUID()
        draft.adopt(generation: secondGeneration, loadVersion: nil, loaded: false, interestTopicIDs: [])
        XCTAssertTrue(draft.selected.isEmpty)
        XCTAssertNil(draft.loadVersion)
        XCTAssertFalse(draft.isDirty)
        draft.toggle("ignored-before-load")
        draft.adopt(generation: secondGeneration, loadVersion: UUID(), loaded: true, interestTopicIDs: ["film"])
        draft.toggle("culture")
        // A returned account arrives under a fresh generation, not the old A ticket.
        draft.adopt(generation: UUID(), loadVersion: UUID(), loaded: true, interestTopicIDs: ["music"])
        XCTAssertEqual(draft.selected, ["music"])
        XCTAssertFalse(draft.isDirty)
    }

    func testTwentyTopicMergeRetainsAllLocalAndExistingSelectionsBeforeNewServerTopics() {
        let original = (0..<18).map { String(format: "topic-%02d", $0) }
        var draft = loaded(original)
        draft.toggle("z-local-one")
        draft.toggle("z-local-two")
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: original + ["a-remote-one", "a-remote-two"])
        XCTAssertEqual(draft.selected, Set(original + ["z-local-one", "z-local-two"]))
        XCTAssertEqual(draft.selected.count, 20)
        XCTAssertTrue(draft.isDirty, "This is a memory-only draft; no whole-document save is implied")
    }

    func testTwentyTopicMergeFillsOnlyRemainingCapacityDeterministically() {
        let original = (0..<19).map { String(format: "topic-%02d", $0) }
        var draft = loaded(original)
        draft.toggle("z-local")
        let remote = Array(original.dropFirst(2)) + ["a-remote", "b-remote", "c-remote"]
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true, interestTopicIDs: remote)
        XCTAssertEqual(draft.selected, Set(Array(original.dropFirst(2)) + ["z-local", "a-remote", "b-remote"]))
        XCTAssertFalse(draft.selected.contains("topic-00"))
        XCTAssertFalse(draft.selected.contains("topic-01"))
        XCTAssertEqual(draft.selected.count, 20)
    }

    func testOverflowedServerTopicsBecomeVisibleWhenLaterRemoteRemovalFreesCapacity() {
        let original = (0..<18).map { String(format: "topic-%02d", $0) }
        var draft = loaded(original)
        draft.toggle("z-local-one")
        draft.toggle("z-local-two")
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: original + ["a-remote-one", "a-remote-two"])
        XCTAssertEqual(draft.selected, Set(original + ["z-local-one", "z-local-two"]))
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: Array(original.dropFirst(2)) + ["a-remote-one", "a-remote-two"])
        XCTAssertEqual(draft.selected, Set(Array(original.dropFirst(2))
            + ["z-local-one", "z-local-two", "a-remote-one", "a-remote-two"]))
        XCTAssertEqual(draft.selected.count, 20)
        XCTAssertTrue(draft.isDirty)
    }

    func testTwentyTopicToggleRejectsOnlyNewChoiceUntilOneIsRemoved() {
        let original = (0..<20).map { "topic-\($0)" }
        var draft = loaded(original)
        draft.toggle("new")
        draft.toggle("")
        XCTAssertEqual(draft.selected, Set(original))
        draft.toggle("topic-0")
        draft.toggle("new")
        XCTAssertEqual(draft.selected.count, 20)
        XCTAssertTrue(draft.selected.contains("new"))
        XCTAssertFalse(draft.selected.contains("topic-0"))
    }

    func testIntroductionReplacementRemainsAnExplicitDraftRelativeToOriginalBaseline() {
        var draft = loaded(["music", "film"])
        draft.replaceSelection(with: ["books"])
        XCTAssertTrue(draft.isDirty)
        draft.adopt(generation: generation, loadVersion: UUID(), loaded: true,
                    interestTopicIDs: ["music", "film", "culture"])
        XCTAssertEqual(draft.selected, ["books", "culture"])
        XCTAssertTrue(draft.isDirty)
    }

    func testUnloadedDraftRejectsEditsAndAcceptedInputIsNormalized() {
        var draft = ReaderInterestDraft()
        draft.toggle("music")
        draft.replaceSelection(with: ["film"])
        XCTAssertTrue(draft.selected.isEmpty)
        draft.adopt(generation: generation, loadVersion: firstLoad, loaded: true,
                    interestTopicIDs: ["", "music", "music", "film"])
        XCTAssertEqual(draft.selected, ["music", "film"])
        XCTAssertFalse(draft.isDirty)
    }
}
