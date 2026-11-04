import Combine
import XCTest
@testable import Apropos

@MainActor
final class HomeFeedPreparationModelTests: XCTestCase {
    private final class AuthorityBox { var value: HomeFeedAuthority?; init(_ value: HomeFeedAuthority?) { self.value = value } }
    private final class HeldWorker {
        var inputs: [HomeFeedInput] = []
        var replies: [CheckedContinuation<HomeFeedSnapshot, Error>] = []
        let builder = HomeFeedBuilder()
        func prepare(_ input: HomeFeedInput) async throws -> HomeFeedSnapshot {
            inputs.append(input)
            return try await withCheckedThrowingContinuation { replies.append($0) }
        }
        func succeed(_ index: Int) { replies[index].resume(returning: builder.build(inputs[index])) }
        func fail(_ index: Int) { replies[index].resume(throwing: Failure.failed) }
    }
    private enum Failure: Error { case failed }
    private func article(_ id: String, revision: String = "r1", content: String = "Body", day: Int = 1) -> Article {
        Article(id: id, name: id, slug: id, content: content, intro: "Intro", topicID: "other",
            createdOn: String(format: "2026-01-%02dT10:00:00Z", day), lastPublished: "2026-01-01T10:00:00Z", contentRevision: revision)
    }
    private func input(_ authority: HomeFeedAuthority, _ articles: [Article], recommendations: [HomeRecommendation] = [],
                       episodes: [PodcastEpisode] = [], now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> HomeFeedInput {
        HomeFeedInput(authority: authority, articles: articles, topics: [], sections: [], authors: [], episodes: episodes,
            recommendations: recommendations, now: now)
    }
    private func model(_ box: AuthorityBox, _ worker: HeldWorker) -> HomeFeedPreparationModel {
        HomeFeedPreparationModel(prepare: { value in try await worker.prepare(value) }, currentAuthority: { box.value },
                                 now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
    private func waitForStarts(_ count: Int, _ worker: HeldWorker, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 where worker.inputs.count < count { await Task.yield() }
        XCTAssertEqual(worker.inputs.count, count, file: file, line: line)
    }
    private func initial(_ input: HomeFeedInput, _ model: HomeFeedPreparationModel, _ worker: HeldWorker) async {
        model.update(input); await waitForStarts(1, worker); worker.succeed(0); await model.waitForCurrentWork()
    }
    func testConstructionStartsNoTaskOrPreparationOrIdentityRead() async {
        var reads = 0
        let worker = HeldWorker()
        let model = HomeFeedPreparationModel(prepare: { value in try await worker.prepare(value) },
            currentAuthority: { reads += 1; return nil })
        await Task.yield()
        XCTAssertEqual(reads, 0); XCTAssertEqual(worker.inputs.count, 0); XCTAssertNil(model.snapshot); XCTAssertFalse(model.state.isPreparing)
    }
    func testActualWorkerInitialPrepareAndIdenticalRenderInputsDoNoFurtherWork() async {
        let authority = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(authority)
        let model = model(box, worker), value = input(authority, [article("a")])
        await initial(value, model, worker)
        let accepted = model.snapshot
        for _ in 0..<30 { model.update(value); model.sceneBecameActive() }
        await Task.yield()
        XCTAssertEqual(worker.inputs.count, 1); XCTAssertEqual(model.snapshot, accepted)
    }
    func testOneActualWorkerAndOnlyLatestPendingInput() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), c = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker)
        model.update(input(a, [article("a")])); await waitForStarts(1, worker)
        box.value = b; model.update(input(b, [article("b")]))
        box.value = c; model.update(input(c, [article("c")]))
        await Task.yield(); XCTAssertEqual(worker.inputs.count, 1)
        worker.succeed(0); await waitForStarts(2, worker)
        XCTAssertEqual(worker.inputs[1].authority, c); XCTAssertNotEqual(model.snapshot?.authority, a)
        worker.succeed(1); await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.hero.map(\.id), ["c"]); XCTAssertFalse(model.state.isPreparing)
    }
    func testWithdrawalRevokesVisibleArticleAndAudioBeforeHeldEffectReturns() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker)
        let episode = PodcastEpisode(id: "e", articleId: "a", articleSlug: nil, title: "a", subtitle: nil,
            audioURL: URL(string: "https://example.invalid/e.mp3"), productionSourceURL: nil,
            duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
        await initial(input(a, [article("a")], episodes: [episode]), model, worker)
        XCTAssertEqual(model.snapshot?.podcastPairs.count, 1)
        box.value = b; model.update(input(b, [], episodes: []))
        XCTAssertTrue(model.snapshot?.hero.isEmpty == true); XCTAssertTrue(model.snapshot?.podcastPairs.isEmpty == true)
        XCTAssertTrue(model.snapshot?.resumeIndex.playableEpisodesByID.isEmpty == true)
        XCTAssertFalse(model.isCurrent(a)); await waitForStarts(2, worker)
        worker.succeed(1); await model.waitForCurrentWork(); XCTAssertTrue(model.snapshot?.hero.isEmpty == true)
    }
    func testChangedSourceRevisionDropsOldBindingSynchronouslyAndReturnsCurrentValue() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker)
        await initial(input(a, [article("same")]), model, worker)
        box.value = b; model.update(input(b, [article("same", revision: "r2", content: "New")]))
        XCTAssertTrue(model.snapshot?.hero.isEmpty == true)
        await waitForStarts(2, worker); worker.succeed(1); await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.hero.first?.content, "New"); XCTAssertEqual(model.snapshot?.hero.first?.contentRevision, "r2")
    }
    func testOwnerSwitchImmediatelyRemovesPersonalReasonAndOldActionAuthority() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker)
        await initial(input(a, [article("a"), article("b")], recommendations: [.init(articleID: "a", reason: "A interest")]), model, worker)
        box.value = b; model.update(input(b, [article("a"), article("b")], recommendations: [.init(articleID: "b", reason: "B interest")]))
        XCTAssertTrue(model.snapshot?.rail(.recommended).visible.isEmpty == true)
        XCTAssertTrue(model.snapshot?.rail(.recommended).reasonsByID.isEmpty == true); XCTAssertFalse(model.isCurrent(a))
        await waitForStarts(2, worker); worker.succeed(1); await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.rail(.recommended).visible.map(\.id), ["b"])
        XCTAssertEqual(model.snapshot?.rail(.recommended).reasonsByID, ["b": "B interest"])
    }
    func testOwnerGuestOwnerReturnCannotAcceptOriginalHeldResult() async {
        let a = HomeFeedAuthority(), guest = HomeFeedAuthority(), returned = HomeFeedAuthority()
        let worker = HeldWorker(), box = AuthorityBox(a), model = model(AuthorityBox(nil), HeldWorker())
        _ = model // A separate inert instance also starts no work.
        let actual = self.model(box, worker)
        actual.update(input(a, [article("old")])); await waitForStarts(1, worker)
        box.value = guest; actual.update(input(guest, []))
        box.value = returned; actual.update(input(returned, [article("new")]))
        worker.succeed(0); await waitForStarts(2, worker)
        XCTAssertNil(actual.snapshot?.hero.first); XCTAssertFalse(actual.isCurrent(a))
        worker.succeed(1); await actual.waitForCurrentWork(); XCTAssertEqual(actual.snapshot?.hero.map(\.id), ["new"])
    }
    func testOldFailureDoesNotPublishErrorForNewOwnerAndSlotDrainsActually() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker)
        model.update(input(a, [article("a")])); await waitForStarts(1, worker)
        box.value = b; model.update(input(b, [article("b")]))
        worker.fail(0); await waitForStarts(2, worker)
        XCTAssertNil(model.state.errorMessage)
        worker.succeed(1); await model.waitForCurrentWork(); XCTAssertEqual(model.snapshot?.hero.map(\.id), ["b"])
    }
    func testCurrentFailureIsVisibleAndDoesNotInventContent() async {
        let a = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a), model = model(AuthorityBox(nil), HeldWorker())
        _ = model
        let actual = self.model(box, worker)
        actual.update(input(a, [])); await waitForStarts(1, worker); worker.fail(0); await actual.waitForCurrentWork()
        XCTAssertNotNil(actual.state.errorMessage); XCTAssertFalse(actual.state.isPreparing); XCTAssertNil(actual.snapshot)
    }
    func testIdentityGetterReentryCannotStartOuterWorker() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        var model: HomeFeedPreparationModel!, enter = false
        model = HomeFeedPreparationModel(prepare: { try await worker.prepare($0) }, currentAuthority: {
            if enter { enter = false; box.value = b; model.update(self.input(b, [self.article("b")])) }
            return box.value
        })
        enter = true; model.update(input(a, [article("a")]))
        await waitForStarts(1, worker); XCTAssertEqual(worker.inputs[0].authority, b)
        worker.succeed(0); await model.waitForCurrentWork(); XCTAssertEqual(model.snapshot?.hero.map(\.id), ["b"])
    }
    func testWillChangeReentryCancelsOuterPublicationAndOnlyNewInputPrepares() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker); var enter = true
        let observation = model.objectWillChange.sink {
            if enter { enter = false; box.value = b; model.update(self.input(b, [self.article("b")])) }
        }
        model.update(input(a, [article("a")]))
        await waitForStarts(1, worker); XCTAssertEqual(worker.inputs[0].authority, b)
        worker.succeed(0); await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.hero.map(\.id), ["b"]); withExtendedLifetime(observation) {}
    }
    func testPostStateSubscribersOnlyReceiveCurrentlyCommittedRevisionUnderReentry() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker); var entered = false, received = 0
        let observers = (0..<2).map { _ in model.changes.sink { state in
            XCTAssertEqual(state.revision, model.state.revision); XCTAssertEqual(state.generation, model.state.generation)
            received += 1
            if state.snapshot?.hero.first?.id == "a", !entered {
                entered = true; box.value = b; model.update(self.input(b, [self.article("b")]))
            }
        } }
        model.update(input(a, [article("a")])); await waitForStarts(1, worker)
        worker.succeed(0); await waitForStarts(2, worker); worker.succeed(1); await model.waitForCurrentWork()
        XCTAssertTrue(entered); XCTAssertGreaterThan(received, 1); XCTAssertEqual(model.snapshot?.hero.map(\.id), ["b"])
        withExtendedLifetime(observers) {}
    }
    func testClockBeforeBoundaryDoesNoWorkerAndSceneActiveAtDeadlinePreparesOnce() async throws {
        let a = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let future = article("future", day: 20), boundary = try XCTUnwrap(ArticlePresentationDateParser().dates(for: future).created)
        var clock = boundary.addingTimeInterval(-20), scheduled: [(@MainActor () -> Void)] = []
        let model = HomeFeedPreparationModel(prepare: { try await worker.prepare($0) }, currentAuthority: { box.value },
            now: { clock }, scheduleBoundary: { _, callback in scheduled.append(callback) })
        await initial(input(a, [future], now: clock), model, worker)
        XCTAssertEqual(scheduled.count, 1)
        clock = boundary.addingTimeInterval(-1); model.sceneBecameActive(); await Task.yield(); XCTAssertEqual(worker.inputs.count, 1)
        clock = boundary; scheduled[0](); await waitForStarts(2, worker)
        worker.succeed(1); await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.hero.map(\.id), ["future"]); XCTAssertNil(model.snapshot?.nextBoundary)
        scheduled[0](); await Task.yield(); XCTAssertEqual(worker.inputs.count, 2)
    }
    func testAuthorityChangingWithoutUpdateRejectsHeldCommitAndTap() async {
        let a = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a), model = model(AuthorityBox(nil), HeldWorker())
        _ = model
        let actual = self.model(box, worker)
        actual.update(input(a, [article("a")])); await waitForStarts(1, worker)
        box.value = HomeFeedAuthority(); worker.succeed(0); await actual.waitForCurrentWork()
        XCTAssertNil(actual.snapshot); XCTAssertFalse(actual.isCurrent(a))
    }
    func testEpisodeRemovalRevokesResumeAndPairsWhileArticleRemains() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker), episode = PodcastEpisode(id: "e", articleId: "a", articleSlug: nil, title: "a", subtitle: nil,
            audioURL: URL(string: "https://example.invalid/e.mp3"), productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
        await initial(input(a, [article("a")], episodes: [episode]), model, worker)
        box.value = b; model.update(input(b, [article("a")], episodes: []))
        XCTAssertEqual(model.snapshot?.hero.map(\.id), ["a"]); XCTAssertTrue(model.snapshot?.podcastPairs.isEmpty == true)
        XCTAssertNil(model.snapshot?.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
        await waitForStarts(2, worker); worker.succeed(1); await model.waitForCurrentWork()
    }
    func testNewPlayableDuplicateDeniesResumeBeforeHeldPreparationReturns() async {
        let a = HomeFeedAuthority(), b = HomeFeedAuthority(), worker = HeldWorker(), box = AuthorityBox(a)
        let model = model(box, worker), episode = PodcastEpisode(id: "e", articleId: "a", articleSlug: nil, title: "a", subtitle: nil,
            audioURL: URL(string: "https://example.invalid/e.mp3"), productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
        await initial(input(a, [article("a")], episodes: [episode]), model, worker)
        XCTAssertNotNil(model.snapshot?.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
        box.value = b; model.update(input(b, [article("a")], episodes: [episode, episode]))
        XCTAssertNil(model.snapshot?.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
        await waitForStarts(2, worker)
        XCTAssertNil(model.snapshot?.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
        worker.succeed(1); await model.waitForCurrentWork()
        XCTAssertNil(model.snapshot?.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
    }
}
