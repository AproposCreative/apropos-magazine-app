import XCTest
@testable import Apropos

final class CanonicalAccountPublicationTests: XCTestCase {
    @MainActor func testStaleCanonicalCallbackCannotPublishAnyStep() {
        let publication = CanonicalAccountPublication()
        var calls = 0
        XCTAssertFalse(publication.perform(expectedUserID: "a", currentUserID: { "b" }, steps: [{ calls += 1 }]))
        XCTAssertEqual(calls, 0)
    }
    @MainActor func testNestedNewAccountCannotBeOverwrittenByOuterTail() {
        let publication = CanonicalAccountPublication()
        var uid: String? = "a", events: [String] = []
        let completed = publication.perform(expectedUserID: "a", currentUserID: { uid }, steps: [{
            events.append("a:private")
            uid = "b"
            publication.perform(expectedUserID: "b", currentUserID: { uid }, steps: [
                { events.append("b:private") }, { events.append("b:session") }
            ])
        }, { events.append("a:session") }])
        XCTAssertFalse(completed)
        XCTAssertEqual(events, ["a:private", "b:private", "b:session"])
    }
    @MainActor func testSameUIDReturnStillInvalidatesOldPublication() {
        let publication = CanonicalAccountPublication()
        var uid: String? = "a", events: [String] = []
        XCTAssertFalse(publication.perform(expectedUserID: "a", currentUserID: { uid }, steps: [{
            uid = nil
            publication.perform(expectedUserID: nil, currentUserID: { uid }, steps: [{ events.append("guest") }])
            uid = "a"
            publication.perform(expectedUserID: "a", currentUserID: { uid }, steps: [{ events.append("new-a") }])
        }, { events.append("old-a") }]))
        XCTAssertEqual(events, ["guest", "new-a"])
    }
    @MainActor func testUIDIsRecheckedBetweenEveryPublishingStep() {
        let publication = CanonicalAccountPublication()
        var uid: String? = "a", calls = 0
        XCTAssertFalse(publication.perform(expectedUserID: "a", currentUserID: { uid }, steps: [{
            calls += 1;uid = "b"
        }, { calls += 1 }]))
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testCanonicalGuestAndRepeatedAccountCompleteInOrder() {
        let publication = CanonicalAccountPublication()
        var events: [String] = []
        XCTAssertTrue(publication.perform(expectedUserID: nil, currentUserID: { nil }, steps: [
            { events.append("private") }, { events.append("history") }, { events.append("session") }
        ]))
        XCTAssertEqual(events, ["private", "history", "session"])
        XCTAssertTrue(publication.perform(expectedUserID: "a", currentUserID: { "a" }, steps: []))
        XCTAssertTrue(publication.perform(expectedUserID: "a", currentUserID: { "a" }, steps: []))
    }
}
