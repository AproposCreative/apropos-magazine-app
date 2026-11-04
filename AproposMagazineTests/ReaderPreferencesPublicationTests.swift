import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderPreferencesPublicationTests: XCTestCase {
    func testContextRevocationPublishesOneCoherentOwnerAndEmptyValue() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["private-A"])
        var snapshots: [ReaderPreferencesModel.Snapshot] = []
        let subscription = h.model.changes.sink { snapshots.append($0) }
        _ = h.select("B")
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.userID, "B")
        XCTAssertTrue(snapshots.first?.preferences.interestTopicIDs.isEmpty == true)
        XCTAssertFalse(snapshots.first?.loaded ?? true)
        withExtendedLifetime(subscription) {}
    }
    func testWillChangeReentryCannotOverwriteNewerContextWithOldProposal() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        var reentered = false
        let subscription = h.model.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.select("C") }
        }
        let rejected = h.model.changeContext(to: .account("B"))
        XCTAssertNil(rejected); XCTAssertEqual(h.model.userID, "C")
        XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty)
        withExtendedLifetime(subscription) {}
    }
    func testWillChangeSameCommittedOwnerRequestCancelsOuterOwnerChange() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        var reentered = false
        let subscription = h.model.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.model.changeContext(to: .account("A")) }
        }
        let rejected = h.model.changeContext(to: .account("B"))
        XCTAssertNil(rejected); XCTAssertEqual(h.model.userID, "A")
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["A"])
        withExtendedLifetime(subscription) {}
    }
    func testEveryPostStateSubscriberFiltersStaleOuterDeliveryAfterNestedOwnerChange() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        var first: [ReaderPreferencesModel.Snapshot] = [], second: [ReaderPreferencesModel.Snapshot] = []
        var nested = false
        func receive(_ value: ReaderPreferencesModel.Snapshot, append: (ReaderPreferencesModel.Snapshot) -> Void) {
            append(value)
            if value.userID == "B", !nested { nested = true; _ = h.select("C") }
        }
        let a = h.model.changes.sink { value in receive(value) { first.append($0) } }
        let b = h.model.changes.sink { value in receive(value) { second.append($0) } }
        _ = h.select("B")
        for values in [first, second] {
            XCTAssertEqual(values.last?.userID, "C")
            XCTAssertEqual(values.map(\.revision), values.map(\.revision).sorted())
            XCTAssertTrue(values.allSatisfy { $0.preferences.interestTopicIDs.isEmpty })
        }
        withExtendedLifetime((a, b)) {}
    }
    func testLoadWillChangeSwitchCannotPublishOldInterestsUnderNewOwner() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; let context = h.select("A")
        let task = Task { await h.model.load(context) }; await h.waitForReads(1)
        var reentered = false
        let subscription = h.model.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.select("B") }
        }
        h.finishRead(0, ids: ["private-A"]); await task.value
        XCTAssertEqual(h.model.userID, "B"); XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty)
        XCTAssertFalse(h.model.hasLoaded)
        withExtendedLifetime(subscription) {}
    }
    func testSaveAcknowledgementWillChangeSwitchCannotGiveOldFormSuccess() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["private-A"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        var reentered = false
        let subscription = h.model.objectWillChange.sink {
            if !reentered { reentered = true; _ = h.select("B") }
        }
        h.finishWrite(0); let saved = await task.value
        XCTAssertFalse(saved); XCTAssertEqual(h.model.userID, "B"); XCTAssertNil(h.model.errorMessage)
        XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty)
        withExtendedLifetime(subscription) {}
    }
    func testCaptureIdentityReentryCannotBorrowAnotherEpochLoadOrValue() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let original = h.model.contextTicket()
        h.onIdentityRead = {
            h.onIdentityRead = nil
            _ = h.select(nil); _ = h.select("A")
        }
        XCTAssertNil(h.model.captureSave(ids: ["old-form"], context: original))
        XCTAssertNotEqual(h.model.snapshot.generation, original.generation)
        XCTAssertTrue(h.writes.isEmpty)
    }
    func testInvalidUserIDCannotBecomeAnAccountOrStartProviderWork() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }
        for invalid in ["", " A", "A/B", "..", "__reserved__", "A\nB"] {
            h.actualUID = invalid; h.canonicalUID = invalid
            let ticket = h.model.changeContext(to: .account(invalid))!
            XCTAssertEqual(h.model.snapshot.context, .unresolved)
            await h.model.load(ticket)
        }
        XCTAssertTrue(h.reads.isEmpty); XCTAssertNil(h.model.userID)
        _ = h.select(nil); XCTAssertEqual(h.model.snapshot.context, .guest)
    }
}
