import Combine
import XCTest
@testable import Apropos

@MainActor
final class RecommendationHistoryCoordinatorTests: XCTestCase {
    func testUnknownAndMismatchedCanonicalContextsCannotSelectAnyHistory() {
        let s = snapshot()
        XCTAssertNil(capture(.unresolved, s, uid: nil))
        XCTAssertNil(capture(.confirmed(userID: "A"), s, uid: "B"))
        XCTAssertNil(capture(.guest, s, uid: "A"))
    }

    func testOnlyMatchingCanonicalProfileIsUnionedWithOwnedHistory() throws {
        let s = snapshot(ids: ["local"])
        let context = ReadingHistoryContext.confirmed(userID: "A")
        let matching = try XCTUnwrap(capture(context, s, uid: "A", profile: "A", ids: ["profile"]))
        XCTAssertEqual(matching.readArticleIDs, ["local", "profile"])
        let other = try XCTUnwrap(capture(context, s, uid: "A", profile: "B", ids: ["private-B"]))
        XCTAssertEqual(other.readArticleIDs, ["local"])
    }

    func testGuestNeverAdoptsProfileOrLegacyFavoriteAuthority() throws {
        let s = snapshot(ids: ["guest"])
        let input = try XCTUnwrap(capture(.guest, s, uid: nil, profile: "A", ids: ["private-A"], favoritesGeneration: s.generation))
        XCTAssertEqual(input.readArticleIDs, ["guest"])
        XCTAssertTrue(input.favorites.isEmpty)
    }

    func testFavoritesRequireSameAccountEpochMarkerAndCannotReviveAfterRoundTrip() throws {
        let s = snapshot()
        let context = ReadingHistoryContext.confirmed(userID: "A")
        XCTAssertTrue(try XCTUnwrap(capture(context, s, uid: "A")).favorites.isEmpty)
        XCTAssertEqual(try XCTUnwrap(capture(context, s, uid: "A", favoritesGeneration: s.generation)).favorites.count, 1)
        let restored = snapshot()
        XCTAssertTrue(try XCTUnwrap(capture(context, restored, uid: "A", favoritesGeneration: s.generation)).favorites.isEmpty)
    }

    func testScrollOnlyRevisionDoesNotInvalidateRelevantInput() throws {
        let generation = UUID()
        let a = try XCTUnwrap(capture(.guest, snapshot(generation: generation, revision: 1, ids: ["read"]), uid: nil))
        let b = try XCTUnwrap(capture(.guest, snapshot(generation: generation, revision: 2, ids: ["read"], progress: 0.8), uid: nil))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.sourceRevision, b.sourceRevision)
    }

    func testSameUserProfileHistoryChangesAreRelevantWithoutUIDChange() throws {
        let s = snapshot()
        let context = ReadingHistoryContext.confirmed(userID: "A")
        XCTAssertNotEqual(capture(context, s, uid: "A", profile: "A", ids: []),
                          capture(context, s, uid: "A", profile: "A", ids: ["article"]))
    }

    func testProfileInputIsBoundedToNewestValidRecordIdentifiers() {
        let ids = (0..<205).map { "article-\($0)" } + [" bad", "bad\n", String(repeating: "ø", count: 257)]
        let selected = RecommendationHistorySelection.validatedProfileIDs(ids)
        XCTAssertLessThanOrEqual(selected.count, 200)
        XCTAssertFalse(selected.contains("article-0"))
        XCTAssertTrue(selected.contains("article-204"))
        XCTAssertTrue(selected.allSatisfy(ReadingHistoryRecordCodec.isValidID))
    }

    func testFavoriteCallbackFenceRequiresOriginalCanonicalAccountAndEpoch() {
        let generation = UUID()
        XCTAssertTrue(RecommendationHistorySelection.ownsFavorites(context: .confirmed(userID: "A"), generation: generation,
            canonicalUserID: "A", expectedUserID: "A", expectedGeneration: generation))
        for context in [ReadingHistoryContext.guest, .unresolved, .confirmed(userID: "B")] {
            XCTAssertFalse(RecommendationHistorySelection.ownsFavorites(context: context, generation: generation,
                canonicalUserID: "A", expectedUserID: "A", expectedGeneration: generation))
        }
        XCTAssertFalse(RecommendationHistorySelection.ownsFavorites(context: .confirmed(userID: "A"), generation: UUID(),
            canonicalUserID: "A", expectedUserID: "A", expectedGeneration: generation))
    }

    func testReentrantModelDeliveryCannotReapplyAnOlderEpochSnapshot() {
        let model = ReadingHistoryModel(storage: .init(read: { _ in nil }, write: { _, _ in }), schedule: { _, _ in {} })
        var captured: [UUID] = []
        var shouldSwitch = true
        var original: ReadingHistorySnapshot?
        let first = model.changes.sink { snapshot in
            if shouldSwitch {
                shouldSwitch = false
                original = snapshot
                model.changeContext(to: .confirmed(userID: "B"))
            }
        }
        func accept(_ snapshot: ReadingHistorySnapshot) {
            guard RecommendationHistorySelection.isCurrent(snapshot, comparedTo: model.snapshot) else { return }
            captured.append(snapshot.generation)
        }
        let second = model.changes.sink { accept($0) }
        model.changeContext(to: .confirmed(userID: "A"))
        XCTAssertEqual(captured.last, model.snapshot.generation)
        XCTAssertFalse(captured.isEmpty)
        let count = captured.count
        if let original { accept(original) } else { XCTFail("Expected original delivery") }
        XCTAssertEqual(captured.count, count, "Late A delivery cannot invalidate B regardless of Combine subscriber order")
        withExtendedLifetime((first, second)) {}
    }

    func testAuthorityChangeRecalculatesEvenWhenFavoriteArticleArrayIsIdentical() async throws {
        let f = RecommendationFixture(), s = snapshot()
        let context = ReadingHistoryContext.confirmed(userID: "A")
        let unowned = try XCTUnwrap(capture(context, s, uid: "A"))
        let accepted = try XCTUnwrap(capture(context, s, uid: "A", favoritesGeneration: s.generation))
        XCTAssertNotEqual(unowned, accepted)
        f.coordinator.update(unowned)
        await wait { f.inputs.count == 1 }
        // The production server callback explicitly refreshes on this authority
        // edge even when the observable Article array did not change.
        f.coordinator.update(accepted)
        f.finish(0)
        await wait { f.inputs.count == 2 }
        XCTAssertEqual(f.inputs[1].favorites.map(\.id), ["favorite"])
        f.finish(1)
        await wait { f.states.last?.isLoading == false }
    }

    func testInterestsAreOwnedAtCaptureAndNormalizedWithoutLaterLookup() throws {
        let s = snapshot()
        let input = try XCTUnwrap(RecommendationHistorySelection.capture(context: .guest, snapshot: s,
            canonicalUserID: nil, profileUserID: nil, profileReadIDs: [], articles: [], favorites: [],
            favoritesGeneration: nil, interestTopicIDs: ["b", "a", "b"]))
        XCTAssertEqual(input.interestTopicIDs, ["a", "b"])
    }

    func testOldAResultCannotCommitAfterGuestAndRestoredAWithSameUID() async throws {
        let f = RecommendationFixture()
        let old = try XCTUnwrap(capture(.confirmed(userID: "A"), snapshot(), uid: "A"))
        f.coordinator.update(old)
        await wait { f.inputs.count == 1 }
        f.coordinator.invalidate()
        f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(), uid: nil)))
        let current = try XCTUnwrap(capture(.confirmed(userID: "A"), snapshot(ids: ["new-read"]), uid: "A"))
        f.coordinator.update(current)
        f.finish(0, articles: [article("old-result")])
        await wait { f.inputs.count == 2 }
        XCTAssertEqual(f.inputs[1], current)
        XCTAssertFalse(f.states.contains { $0.recommendations.first?.0.id == "old-result" })
        f.finish(1, articles: [article("current-result")])
        await wait { f.states.last?.isLoading == false }
        XCTAssertEqual(f.states.last?.recommendations.first?.0.id, "current-result")
    }

    func testIgnoredCancellationKeepsOnlyOneRunningAndLatestPendingCalculation() async throws {
        let f = RecommendationFixture()
        let generation = UUID()
        f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(generation: generation), uid: nil)))
        await wait { f.inputs.count == 1 }
        for index in 0..<100 {
            f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(generation: generation, ids: ["read-\(index)"]), uid: nil)))
        }
        XCTAssertEqual(f.inputs.count, 1)
        f.finish(0)
        await wait { f.inputs.count == 2 }
        XCTAssertEqual(f.inputs[1].readArticleIDs, ["read-99"])
        f.finish(1)
        await wait { f.states.last?.isLoading == false }
    }

    func testEqualProgressOnlyInputDoesNotRestartRunningCalculation() async throws {
        let f = RecommendationFixture(), generation = UUID()
        f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(generation: generation, revision: 1), uid: nil)))
        await wait { f.inputs.count == 1 }
        f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(generation: generation, revision: 2, progress: 0.8), uid: nil)))
        f.finish(0, articles: [article("valid")])
        await wait { f.states.last?.isLoading == false }
        XCTAssertEqual(f.inputs.count, 1)
        XCTAssertEqual(f.states.last?.recommendations.first?.0.id, "valid")
    }

    func testInvalidationClearsOutputAndLateCompletionCannotRestoreIt() async throws {
        let f = RecommendationFixture()
        f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(), uid: nil)))
        await wait { f.inputs.count == 1 }
        f.coordinator.invalidate()
        f.finish(0, articles: [article("old")])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(f.states.last?.input)
        XCTAssertTrue(f.states.last?.recommendations.isEmpty == true)
        XCTAssertFalse(f.states.last?.isLoading ?? true)
    }

    func testSameUserProfileUpdateDuringWorkUsesOriginalInputsAndRejectsEarlierResult() async throws {
        let f = RecommendationFixture(), s = snapshot()
        let context = ReadingHistoryContext.confirmed(userID: "A")
        f.coordinator.update(try XCTUnwrap(capture(context, s, uid: "A", profile: "A")))
        await wait { f.inputs.count == 1 }
        f.coordinator.update(try XCTUnwrap(capture(context, s, uid: "A", profile: "A", ids: ["article"])))
        XCTAssertTrue(f.inputs[0].readArticleIDs.isEmpty)
        f.finish(0, articles: [article("article")])
        await wait { f.inputs.count == 2 }
        XCTAssertEqual(f.inputs[1].readArticleIDs, ["article"])
        XCTAssertTrue(f.states.last?.recommendations.isEmpty == true)
        f.finish(1)
        await wait { f.states.last?.isLoading == false }
    }

    func testActualModelLocalAndExternalHistoryChangesRecomputePolicyWithoutServices() async throws {
        var records: [ReadingHistoryNamespace: Data] = [:]
        let model = ReadingHistoryModel(storage: .init(read: { records[$0] }, write: { records[$0] = $1 }), schedule: { _, _ in {} })
        model.changeContext(to: .guest)
        let f = RecommendationFixture()
        let candidates = [article("one"), article("two")]
        func update(_ snapshot: ReadingHistorySnapshot) {
            f.coordinator.update(RecommendationHistorySelection.capture(context: model.context, snapshot: snapshot,
                canonicalUserID: nil, profileUserID: "other", profileReadIDs: ["one"], articles: candidates,
                favorites: [], favoritesGeneration: nil, interestTopicIDs: []))
        }
        let observation = model.changes.sink { update($0) }
        update(model.snapshot)
        await wait { f.inputs.count == 1 }
        let articleTicket = try XCTUnwrap(model.beginArticle(articleID: "one"))
        model.markRead(articleTicket)
        f.finishPolicy(0)
        await wait { f.inputs.count == 2 }
        XCTAssertEqual(f.inputs[1].readArticleIDs, ["one"])
        f.finishPolicy(1)
        await wait { f.states.last?.isLoading == false }
        XCTAssertEqual(f.states.last?.recommendations.map { $0.0.id }, ["two"])
        records[.guest] = try ReadingHistoryRecordCodec.encode(.init(entries: [
            .init(articleID: "two", read: true, progress: nil)
        ]), namespace: .guest)
        let external = try XCTUnwrap(model.externalTicket())
        _ = model.reloadExternal(ticket: external)
        await wait { f.inputs.count == 3 }
        XCTAssertEqual(f.inputs[2].readArticleIDs, ["two"])
        f.finishPolicy(2)
        await wait { f.states.last?.isLoading == false }
        XCTAssertEqual(f.states.last?.recommendations.map { $0.0.id }, ["one"])
        withExtendedLifetime(observation) {}
    }

    func testReentrantOutputInvalidationCannotStartOrCommitObsoleteWork() async throws {
        let f = RecommendationFixture()
        f.onState = { state in if !state.isLoading && state.input != nil { f.coordinator.invalidate() } }
        f.coordinator.update(try XCTUnwrap(capture(.guest, snapshot(), uid: nil)))
        await wait { f.inputs.count == 1 }
        f.finish(0, articles: [article("result")])
        await wait { f.states.last?.input == nil }
        XCTAssertTrue(f.states.last?.recommendations.isEmpty == true)
    }

    private func snapshot(generation: UUID = UUID(), revision: UInt64 = 1, ids: [String] = [], progress: Double? = nil) -> ReadingHistorySnapshot {
        let entries = ids.map { ReadingHistoryRecord.Entry(articleID: $0, read: true, progress: progress) }
        return ReadingHistorySnapshot(generation: generation, revision: revision, state: .ready,
            record: .init(entries: entries.isEmpty && progress != nil ? [.init(articleID: "scroll", read: false, progress: progress)] : entries))
    }
    private func capture(_ context: ReadingHistoryContext, _ snapshot: ReadingHistorySnapshot, uid: String?, profile: String? = nil,
                         ids: [String] = [], favoritesGeneration: UUID? = nil) -> RecommendationHistoryInput? {
        RecommendationHistorySelection.capture(context: context, snapshot: snapshot, canonicalUserID: uid,
            profileUserID: profile, profileReadIDs: ids, articles: [], favorites: [article("favorite")],
            favoritesGeneration: favoritesGeneration, interestTopicIDs: [])
    }
    private func article(_ id: String) -> Article {
        Article(id: id, name: id, slug: id, content: "", intro: "", topicID: "topic",
                isDraft: false, createdOn: "2026-10-20T12:00:00Z", lastPublished: "2026-10-20T12:00:00Z")
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 { if condition() { return };await Task.yield() }
        XCTFail("Recommendation work did not reach expected state", file: file, line: line)
    }
}

@MainActor
private final class RecommendationFixture {
    var inputs: [RecommendationHistoryInput] = []
    var states: [RecommendationHistoryCoordinator.State] = []
    var onState: ((RecommendationHistoryCoordinator.State) -> Void)?
    private var continuations: [Int: CheckedContinuation<[(Article, String)], Never>] = [:]
    lazy var coordinator = RecommendationHistoryCoordinator(calculate: { [unowned self] input in
        let index = self.inputs.count
        self.inputs.append(input)
        return await withCheckedContinuation { self.continuations[index] = $0 }
    }, onChange: { [unowned self] state in self.states.append(state);self.onState?(state) })
    func finish(_ index: Int, articles: [Article] = []) {
        continuations.removeValue(forKey: index)?.resume(returning: articles.map { ($0, "Nyt fra Apropos Magazine") })
    }
    func finishPolicy(_ index: Int) {
        let input = inputs[index]
        let result = ReaderRecommendationPolicy.recommendations(articles: input.articles, favorites: input.favorites,
            interestTopicIDs: input.interestTopicIDs, readArticleIDs: input.readArticleIDs)
        continuations.removeValue(forKey: index)?.resume(returning: result)
    }
}
