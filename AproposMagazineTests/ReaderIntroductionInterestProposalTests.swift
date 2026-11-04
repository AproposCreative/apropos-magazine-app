import XCTest
@testable import Apropos

@MainActor
final class ReaderIntroductionInterestProposalTests: XCTestCase {
    private let topics = [Topic(id: "music", name: "Musik"), Topic(id: "film", name: "Film")]

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var actualUID: String?
        var writes: [(String, [String])] = []
        lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [unowned self] in
            .init(actualUID: actualUID, canonicalUID: canonical.snapshot.userID)
        }, load: { _, _ in
            .init(preferences: ReaderPreferences(interestTopicIDs: ["existing"]), isFromCache: false)
        }, save: { [unowned self] request, guardOperation in
            guard guardOperation() else { throw CancellationError() }
            writes.append((request.userID, request.preferences.interestTopicIDs))
        }, schedule: { _ in {} })
        lazy var actions = ReaderAccountActions(canonical: canonical, preferences: preferences,
            verify: { _ in }, refresh: { _ in })

        func select(_ uid: String?, forceNewGeneration: Bool = false) {
            actualUID = uid
            _ = canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: false) },
                                forceNewGeneration: forceNewGeneration)
        }
        func load(_ uid: String) async {
            select(uid)
            let ticket = preferences.changeContext(to: .account(uid))
            preferences.start()
            if let ticket { await preferences.load(ticket) }
        }
        func draft(_ proposal: ReaderIntroductionInterestProposal, topics: [Topic]) -> Set<String>? {
            let snapshot = preferences.snapshot
            return proposal.draftTopicIDs(context: canonical.contextTicket(), topics: topics, preferences: snapshot,
                adoptedGeneration: snapshot.generation, adoptedLoadVersion: snapshot.loadVersion)
        }
    }

    func testGuestToFirstAccountOffersOnlyFreshIntroductionSelection() async {
        let f = Fixture(); f.select(nil)
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        XCTAssertTrue(proposal.topicIDs(context: f.canonical.contextTicket(), topics: topics).isEmpty)
        await f.load("A")
        XCTAssertEqual(f.draft(proposal, topics: topics), ["music"])
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, ["existing"])
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testOpeningForAlreadySignedInAccountBindsThatExactEpoch() async {
        let f = Fixture(); await f.load("A")
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["film"])
        XCTAssertEqual(f.draft(proposal, topics: topics), ["film"])
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testGuestAToBBeforeFirstFormRenderCannotReassignProposal() async {
        let f = Fixture(); f.select(nil)
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        // The sheet's observer is active, but no signed-in form has read it.
        f.select("A")
        await f.load("B")
        XCTAssertTrue(proposal.topicIDs(context: f.canonical.contextTicket(), topics: topics).isEmpty)
        XCTAssertNil(f.draft(proposal, topics: topics))
        await f.load("A")
        XCTAssertNil(f.draft(proposal, topics: topics), "Returning to A cannot revive the old sheet's proposal")
    }

    func testAccountGuestThenNewAccountPermanentlyRevokesProposal() async {
        let f = Fixture(); await f.load("A")
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        f.select(nil)
        await f.load("B")
        XCTAssertNil(f.draft(proposal, topics: topics))
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testInitialUnresolvedWaitsButSuspensionAfterAccountRevokes() async {
        let f = Fixture()
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        XCTAssertTrue(proposal.topicIDs(context: f.canonical.contextTicket(), topics: topics).isEmpty)
        await f.load("A")
        XCTAssertEqual(f.draft(proposal, topics: topics), ["music"])
        _ = f.canonical.suspend()
        f.select("A")
        XCTAssertNil(f.draft(proposal, topics: topics))
    }

    func testRefreshedSameOwnerEpochCannotReuseOldSuggestion() async {
        let f = Fixture(); await f.load("A")
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        let original = f.canonical.contextTicket()
        f.select("A", forceNewGeneration: true)
        XCTAssertTrue(proposal.topicIDs(context: original, topics: topics).isEmpty)
        XCTAssertNil(f.draft(proposal, topics: topics))
    }

    func testVerificationWithinSameCanonicalGenerationDoesNotRevokeProposal() async {
        let f = Fixture(); await f.load("A")
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        let generation = f.canonical.snapshot.generation
        _ = f.canonical.adopt(ReaderAccountSession(uid: "A", email: "A@example.invalid", isEmailVerified: true))
        XCTAssertEqual(f.canonical.snapshot.generation, generation)
        XCTAssertEqual(f.draft(proposal, topics: topics), ["music"])
    }

    func testOnlyActualActiveTopicsAreDeduplicatedAndLimitedToTwenty() {
        let f = Fixture(); f.select("A")
        let known = (0..<30).map { Topic(id: "topic-\($0)", name: "Emne \($0)") }
        let inactive = Topic(id: "inactive", name: "Inaktiv", isActive: false)
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical,
            suggestedInterestTopicIDs: ["", "unknown", "inactive", "topic-0"] + known.map(\.id))
        let ids = proposal.topicIDs(context: f.canonical.contextTicket(), topics: known + [inactive])
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(Set(ids).count, 20)
        XCTAssertTrue(Set(ids).isSubset(of: Set(known.map(\.id))))
        XCTAssertTrue(proposal.topicIDs(context: f.canonical.contextTicket(), topics: []).isEmpty)
    }

    func testPendingPreferencesAndUnadoptedOrNewerLoadsCannotChangeDraft() async throws {
        let f = Fixture(); f.select("A")
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        XCTAssertNil(f.draft(proposal, topics: topics))
        await f.load("A")
        let original = f.preferences.snapshot
        XCTAssertNil(proposal.draftTopicIDs(context: f.canonical.contextTicket(), topics: topics, preferences: original,
            adoptedGeneration: nil, adoptedLoadVersion: original.loadVersion))
        XCTAssertNil(proposal.draftTopicIDs(context: f.canonical.contextTicket(), topics: topics, preferences: original,
            adoptedGeneration: original.generation, adoptedLoadVersion: nil))
        await f.preferences.retry(f.preferences.contextTicket())
        XCTAssertNil(proposal.draftTopicIDs(context: f.canonical.contextTicket(), topics: topics, preferences: f.preferences.snapshot,
            adoptedGeneration: original.generation, adoptedLoadVersion: original.loadVersion))
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testProposalOnlyChangesDraftAndExistingExplicitSaveOwnsTheWrite() async throws {
        let f = Fixture(); await f.load("A")
        let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ["music"])
        var draft = Set(f.preferences.preferences.interestTopicIDs)
        XCTAssertEqual(draft, ["existing"])
        XCTAssertTrue(f.writes.isEmpty)
        draft = try XCTUnwrap(f.draft(proposal, topics: topics))
        XCTAssertEqual(draft, ["music"])
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, ["existing"])
        XCTAssertTrue(f.writes.isEmpty, "Neither observing nor using the suggestion may save preferences")
        let original = try XCTUnwrap(f.actions.captureSave(ids: Array(draft), userID: "A", context: f.canonical.contextTicket()))
        let saved = await f.actions.save(original)
        XCTAssertTrue(saved)
        XCTAssertTrue(f.actions.isCurrentReceipt(original))
        XCTAssertEqual(f.writes.count, 1)
        XCTAssertEqual(f.writes.first?.0, "A")
        XCTAssertEqual(f.writes.first?.1, ["music"])
    }

    func testMissingOrEmptySuggestionLeavesExistingCallersUnchanged() async {
        let f = Fixture(); await f.load("A")
        for ids in [nil, [], [""]] as [[String]?] {
            let proposal = ReaderIntroductionInterestProposal(canonical: f.canonical, suggestedInterestTopicIDs: ids)
            XCTAssertNil(f.draft(proposal, topics: topics))
        }
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, ["existing"])
        XCTAssertTrue(f.writes.isEmpty)
    }
}
