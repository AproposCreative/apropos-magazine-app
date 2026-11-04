import XCTest
@testable import Apropos

@MainActor
final class ReaderPreferencesModelTests: XCTestCase {
    func testInterestsAreDeduplicatedAndBoundedWithoutCompletingOnboarding() {
        let prefs = ReaderPreferences(interestTopicIDs: ["", "music", "music"] + (0..<25).map(String.init))
        XCTAssertEqual(prefs.interestTopicIDs.count, 20)
        XCTAssertEqual(Set(prefs.interestTopicIDs).count, 20)
        XCTAssertFalse(prefs.onboardingCompleted)
    }
    func testSuccessfulSaveUsesAccountAndKeepsPushPreferencesSeparate() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }
        await h.loaded("A")
        let request = h.model.captureSave(ids: ["music"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }
        await h.waitForWrites(1)
        h.finishWrite(0)
        let saved = await task.value
        XCTAssertTrue(saved)
        XCTAssertEqual(h.writes[0].request.userID, "A")
        XCTAssertEqual(h.model.preferences.interestTopicIDs, ["music"])
        XCTAssertTrue(h.model.preferences.onboardingCompleted)
    }
    func testReadFailureCannotOverwriteUnknownRemotePreferences() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }
        let ticket = h.select("A")
        let task = Task { await h.model.load(ticket) }
        await h.waitForReads(1); h.finishRead(0, error: URLError(.notConnectedToInternet)); await task.value
        XCTAssertNil(h.model.captureSave(ids: ["music"], context: ticket))
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertFalse(h.model.hasLoaded)
        XCTAssertNotNil(h.model.errorMessage)
    }
    func testSaveFailurePreservesLoadedInterests() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["old"])
        let request = h.model.captureSave(ids: ["new"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }
        await h.waitForWrites(1); h.finishWrite(0, error: URLError(.notConnectedToInternet))
        let saved = await task.value
        XCTAssertFalse(saved); XCTAssertEqual(h.model.preferences.interestTopicIDs, ["old"])
        XCTAssertFalse(h.model.isSaving); XCTAssertNotNil(h.model.errorMessage)
    }
    func testLogoutClearsAccountPreferences() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A", ids: ["private"])
        _ = h.select(nil)
        XCTAssertNil(h.model.userID); XCTAssertTrue(h.model.preferences.interestTopicIDs.isEmpty)
        XCTAssertFalse(h.model.hasLoaded)
    }
    func testLateAccountLoadCannotReplaceNewAccount() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }
        let a = h.select("A"), old = Task { await h.model.load(a) }; await h.waitForReads(1)
        let b = h.select("B"), new = Task { await h.model.load(b) }; await h.waitForReads(2)
        h.finishRead(1, ids: ["B"]); await new.value
        h.finishRead(0, ids: ["A"]); await old.value
        XCTAssertEqual(h.model.userID, "B"); XCTAssertEqual(h.model.preferences.interestTopicIDs, ["B"])
    }
    func testLateSaveCannotReplaceNewAccountsPreferences() async {
        let h = ReaderPreferencesHarness(); defer { h.close() }; await h.loaded("A")
        let request = h.model.captureSave(ids: ["new-A"], context: h.model.contextTicket())!
        let task = Task { await h.model.saveInterests(request) }; await h.waitForWrites(1)
        await h.loaded("B"); h.finishWrite(0)
        let saved = await task.value
        XCTAssertFalse(saved); XCTAssertEqual(h.model.preferences.interestTopicIDs, ["B"])
        XCTAssertFalse(h.model.isSaving)
    }
}
