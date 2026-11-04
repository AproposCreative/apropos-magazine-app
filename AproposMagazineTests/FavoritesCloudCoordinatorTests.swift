import Combine
import XCTest
@testable import Apropos

/// Actual typed model/coordinator pipeline; no SDK, defaults, files or network.
@MainActor
final class FavoritesCloudCoordinatorTests: XCTestCase {
    func testConstructionUnknownAndGuestDoNotDrainOrWrite() async {
        let f = Fixture(); defer { f.stop() }
        XCTAssertTrue(f.drains.isEmpty); XCTAssertTrue(f.calls.isEmpty)
        f.owner(nil)
        _ = f.model.setFavorite(article(), enabled: true)
        await settle()
        XCTAssertTrue(f.drains.isEmpty); XCTAssertTrue(f.calls.isEmpty)
        XCTAssertEqual(f.model.snapshot.articles.map(\.id), ["article"])
    }

    func testDrainMustActuallyReturnBeforeCommittedIntentCanDispatch() async throws {
        let f = Fixture(); defer { f.stop() }
        f.owner("a")
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        await wait { f.drains.count == 1 }
        for _ in 0..<20 { f.cloud.refresh() }
        XCTAssertEqual(f.drains.count, 1); XCTAssertTrue(f.calls.isEmpty)
        XCTAssertFalse(f.model.snapshot.recoveryReady)
        f.finishDrain(0)
        await wait { f.calls.count == 1 }
        XCTAssertTrue(f.model.snapshot.recoveryReady)
        XCTAssertEqual(f.calls[0].uid, "a")
        XCTAssertTrue(f.model.isCurrent(f.calls[0].ticket))
    }

    func testFailedDrainDoesNotSpinAndOnlyExplicitRetryStartsAnother() async {
        let f = Fixture(); defer { f.stop() }
        f.owner("a"); await wait { f.drains.count == 1 }
        f.finishDrain(0, fail: true)
        await wait { f.model.snapshot.state == .recoveryFailed }
        for _ in 0..<50 { f.cloud.refresh() }
        await settle()
        XCTAssertEqual(f.drains.count, 1); XCTAssertTrue(f.calls.isEmpty)
        f.cloud.retryRecovery(generation: f.model.snapshot.generation)
        await wait { f.drains.count == 2 }
        for _ in 0..<20 { f.cloud.retryRecovery(generation: f.model.snapshot.generation) }
        await settle(); XCTAssertEqual(f.drains.count, 2)
        f.finishDrain(1); await wait { f.model.snapshot.recoveryReady }
    }

    func testHeldOldDrainRetainsOneGlobalSlotAndCannotApproveSameUIDNewEpoch() async {
        let f = Fixture(); defer { f.stop() }
        f.owner("a"); await wait { f.drains.count == 1 }
        let old = f.model.snapshot.generation
        f.owner("b"); f.owner(nil); f.owner("a")
        XCTAssertNotEqual(old, f.model.snapshot.generation)
        for _ in 0..<20 { f.cloud.retryRecovery(generation: f.model.snapshot.generation) }
        await settle(); XCTAssertEqual(f.drains.count, 1)
        f.finishDrain(0)
        await wait { f.drains.count == 2 }
        XCTAssertFalse(f.model.snapshot.recoveryReady)
        XCTAssertEqual(f.drains.map(\.uid), ["a", "a"])
        f.finishDrain(1); await wait { f.model.snapshot.recoveryReady }
    }

    func testGlobalFourSlotsIncludeOldOwnersAndAdmission() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a")
        for index in 0..<8 { _ = try XCTUnwrap(f.model.setFavorite(article("a\(index)"), enabled: true)) }
        await wait { f.calls.count == 4 }
        for _ in 0..<30 { f.cloud.refresh() }
        await settle(); XCTAssertEqual(f.calls.count, 4); XCTAssertEqual(f.peak, 4)
        f.owner("b"); await wait { f.drains.count == 2 }; f.finishDrain(1)
        await wait { f.model.snapshot.recoveryReady }
        _ = try XCTUnwrap(f.model.setFavorite(article("b"), enabled: true))
        await settle(); XCTAssertEqual(f.calls.count, 4)
        f.finishWrite(0)
        await wait { f.calls.count == 5 }
        XCTAssertEqual(f.calls[4].uid, "b"); XCTAssertEqual(f.peak, 4)
    }

    func testOneActivePerArticleCoalescesLatestAbsoluteDesiredState() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a")
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        await wait { f.calls.count == 1 }
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: false))
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: false))
        await settle(); XCTAssertEqual(f.calls.count, 1)
        f.finishWrite(0); await wait { f.calls.count == 2 }
        XCTAssertFalse(f.calls[1].ticket.mutation.enabled)
        XCTAssertEqual(f.peak, 1)
        f.finishWrite(1); await wait { f.cloud.activity.activeWrites == 0 }
        XCTAssertTrue(f.model.snapshot.articles.isEmpty)
    }

    func testAToGuestToARetainsActualSameKeyBarrierAfterNewDrain() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a")
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        await wait { f.calls.count == 1 }
        let original = f.calls[0].ticket
        f.owner(nil); f.owner("a")
        await wait { f.drains.count == 2 }; f.finishDrain(1)
        await wait { f.model.snapshot.recoveryReady }
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: false))
        await settle(); XCTAssertEqual(f.calls.count, 1)
        XCTAssertFalse(f.model.isCurrent(original))
        f.finishWrite(0); await wait { f.calls.count == 2 }
        XCTAssertFalse(f.calls[1].ticket.mutation.enabled)
        XCTAssertNotEqual(original.mutation.generation, f.calls[1].ticket.mutation.generation)
        XCTAssertEqual(f.peak, 1)
    }

    func testDuplicateSubmitNeverDuplicatesActualProviderWork() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a")
        let mutation = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        for _ in 0..<20 { f.cloud.submit(mutation, expectedUserID: "a") }
        await wait { f.calls.count == 1 }
        for _ in 0..<20 { f.cloud.submit(mutation, expectedUserID: "a") }
        f.finishWrite(0); await wait { f.cloud.activity.activeWrites == 0 }
        XCTAssertEqual(f.calls.count, 1)
        XCTAssertEqual(f.model.snapshot.pendingArticleIDs, ["article"])
    }

    func testTypedAdmissionAndStartedCommitMustBothFinishBeforeProvider() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a"); f.holdWrites = true
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        await wait { f.heldWrites.count == 1 }
        XCTAssertTrue(f.calls.isEmpty)
        f.releaseWrite()
        await wait { f.heldWrites.count == 1 && f.cloud.activity.activeWrites == 1 }
        XCTAssertTrue(f.calls.isEmpty)
        f.releaseWrite(); await wait { f.calls.count == 1 }
    }

    func testReceiptCommitRetainsSameKeyAndGlobalSlotUntilActualCommit() async throws {
        let f = Fixture(maximumConcurrentWrites: 1); defer { f.stop() }
        await f.ready("a")
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true)); await wait { f.calls.count == 1 }
        f.holdWrites = true; f.finishWrite(0)
        await wait { f.heldWrites.count == 1 }
        _ = try XCTUnwrap(f.model.setFavorite(article("other"), enabled: true))
        await settle()
        XCTAssertEqual(f.calls.count, 1); XCTAssertEqual(f.cloud.activity.activeWrites, 1)
        f.holdWrites = false
        while !f.heldWrites.isEmpty { f.releaseWrite() }
        await wait { f.calls.count == 2 }
        XCTAssertEqual(f.calls[1].ticket.mutation.articleID, "other")
    }

    func testFailedAdmissionStartsNoProviderUntilExplicitStorageRetry() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a"); f.failWrites = true
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true))
        await wait { f.model.snapshot.state == .writeFailed }
        for _ in 0..<20 { f.cloud.refresh() }
        await settle(); XCTAssertTrue(f.calls.isEmpty)
        f.failWrites = false; f.model.retryStorage()
        await wait { f.calls.count == 1 }
    }

    func testFailureNeedsExplicitRetryAndKeepsOriginalAbsolutePayload() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a")
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true)); await wait { f.calls.count == 1 }
        f.finishWrite(0, fail: true); await wait { f.model.snapshot.state == .cloudFailed }
        for _ in 0..<20 { f.cloud.refresh() }
        await settle(); XCTAssertEqual(f.calls.count, 1)
        _ = try XCTUnwrap(f.model.retryMutation(articleID: "article"))
        await wait { f.calls.count == 2 }
        XCTAssertTrue(f.calls[1].ticket.mutation.enabled)
        XCTAssertEqual(f.calls[1].ticket.mutation.article.content, "")
    }

    func testBoundedKeyQueueDoesNotDiscardDurableTail() async throws {
        let f = Fixture(maximumKeys: 1); defer { f.stop() }
        await f.ready("a")
        _ = try XCTUnwrap(f.model.setFavorite(article("first"), enabled: true)); await wait { f.calls.count == 1 }
        _ = try XCTUnwrap(f.model.setFavorite(article("second"), enabled: true))
        await settle(); XCTAssertEqual(f.calls.count, 1)
        f.finishWrite(0); await wait { f.calls.count == 2 }
        XCTAssertEqual(f.calls[1].ticket.mutation.articleID, "second")
    }

    func testNewHotArticleIntentCannotOvertakeAlreadyWaitingOtherArticle() async throws {
        let f = Fixture(maximumConcurrentWrites: 1); defer { f.stop() }
        await f.ready("a")
        _ = try XCTUnwrap(f.model.setFavorite(article("hot"), enabled: true)); await wait { f.calls.count == 1 }
        _ = try XCTUnwrap(f.model.setFavorite(article("waiting"), enabled: true))
        _ = try XCTUnwrap(f.model.setFavorite(article("hot"), enabled: false))
        f.finishWrite(0); await wait { f.calls.count == 2 }
        XCTAssertEqual(f.calls[1].ticket.mutation.articleID, "waiting")
        f.finishWrite(1); await wait { f.calls.count == 3 }
        XCTAssertEqual(f.calls[2].ticket.mutation.articleID, "hot")
        XCTAssertFalse(f.calls[2].ticket.mutation.enabled)
    }

    func testRecoveryProofAndRecommendationRequireFreshConfirmedOwner() async throws {
        let f = Fixture(); defer { f.stop() }
        f.owner("a"); await wait { f.drains.count == 1 }
        XCTAssertFalse(FavoritesCloudSelection.canObserve(context: f.model.context, snapshot: f.model.snapshot, expectedUserID: "a"))
        XCTAssertNil(f.model.observationTicket())
        f.finishDrain(0); await wait { f.model.snapshot.recoveryReady }
        let observer = try XCTUnwrap(f.model.observationTicket()), historyGeneration = UUID()
        func proof(_ uid: String? = "a", history: ReadingHistoryContext = .confirmed(userID: "a")) -> UUID? {
            FavoritesCloudSelection.recommendationGeneration(favoritesContext: f.model.context, favoritesSnapshot: f.model.snapshot,
                historyContext: history, historyGeneration: historyGeneration, canonicalUserID: uid)
        }
        _ = f.model.applyRemote(.init(articles: [article()], isFromCache: true, hasPendingWrites: false), ticket: observer)
        XCTAssertNil(proof())
        _ = f.model.applyRemote(.init(articles: [article()], isFromCache: false, hasPendingWrites: false), ticket: observer)
        XCTAssertEqual(proof(), historyGeneration)
        XCTAssertNil(proof("b")); XCTAssertNil(proof(nil, history: .guest)); XCTAssertNil(proof(history: .unresolved))
        _ = f.model.applyRemote(.init(articles: [article("changed")], isFromCache: true, hasPendingWrites: false), ticket: observer)
        XCTAssertNil(proof())
    }

    func testServerProofAndReceiptEitherOrderRetireOnlyAfterBoth() async throws {
        let f = Fixture(); defer { f.stop() }
        await f.ready("a")
        let observer = try XCTUnwrap(f.model.observationTicket())
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: true)); await wait { f.calls.count == 1 }
        _ = f.model.applyRemote(.init(articles: [article()], isFromCache: false, hasPendingWrites: false), ticket: observer)
        XCTAssertEqual(f.model.snapshot.pendingArticleIDs, ["article"])
        f.finishWrite(0); await wait { f.model.snapshot.pendingArticleIDs.isEmpty }
        _ = try XCTUnwrap(f.model.setFavorite(article(), enabled: false)); await wait { f.calls.count == 2 }
        f.finishWrite(1); await wait { f.cloud.activity.activeWrites == 0 }
        XCTAssertEqual(f.model.snapshot.pendingArticleIDs, ["article"])
        _ = f.model.applyRemote(.init(articles: [], isFromCache: false, hasPendingWrites: false), ticket: observer)
        await wait { f.model.snapshot.pendingArticleIDs.isEmpty }
    }

    func testAbsoluteTransportPolicyRejectsLateUIDAndUnsafePaths() {
        XCTAssertTrue(FavoritesCloudSelection.permitsWrite(expectedUserID: "a", actualUserID: "a", articleID: "article"))
        for uid in [nil, "b"] as [String?] {
            XCTAssertFalse(FavoritesCloudSelection.permitsWrite(expectedUserID: "a", actualUserID: uid, articleID: "article"))
        }
        for id in ["", "../article", "a/b", "..", "__reserved__", " article", "a\n", String(repeating: "a", count: 513)] {
            XCTAssertFalse(FavoritesCloudSelection.permitsWrite(expectedUserID: "a", actualUserID: "a", articleID: id))
            XCTAssertFalse(FavoritesCloudSelection.permitsWrite(expectedUserID: id, actualUserID: id, articleID: "article"))
        }
    }

    private func article(_ id: String = "article") -> Article {
        Article(id: id, name: "Article", slug: id, content: "<p>Body</p>", intro: "Intro", topicID: "topic",
                lastPublished: "2026-10-20T12:00:00Z", contentRevision: "r1")
    }
    private func settle() async { for _ in 0..<80 { await Task.yield() } }
    private func wait(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 { if predicate() { return }; await Task.yield() }
        XCTFail("Expected bounded local lifecycle transition", file: file, line: line)
    }

    @MainActor private final class Fixture {
        enum Failure: Error { case injected }
        struct DrainCall { let uid: String; let continuation: CheckedContinuation<Void, Error> }
        struct Call { let ticket: FavoritesModel.DispatchTicket; let uid: String; let continuation: CheckedContinuation<Void, Error> }
        struct HeldWrite {
            let namespace: FavoritesNamespace; let record: FavoritesRecord; let expected: UUID?
            let completion: @MainActor (Result<Void, Error>) -> Void
        }
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var drains: [DrainCall] = [], calls: [Call] = [], heldWrites: [HeldWrite] = []
        var holdWrites = false, failWrites = false
        var liveWrites = 0, peak = 0
        var uid: String?
        var model: FavoritesModel!
        var cloud: FavoritesCloudCoordinator!
        private var observation: AnyCancellable?
        private var liveDrainIDs = Set<Int>(), liveCallIDs = Set<Int>()
        init(maximumKeys: Int = 256, maximumConcurrentWrites: Int = 4) {
            model = FavoritesModel(storage: .init(read: { [weak self] namespace, completion in
                guard let self else { completion(.failure(FavoritesJournalFailure.readFailed)); return }
                completion(.success(self.records[namespace]))
            }, write: { [weak self] namespace, record, expected, completion in
                guard let self else { completion(.failure(FavoritesJournalFailure.writeFailed)); return }
                let work = HeldWrite(namespace: namespace, record: record, expected: expected, completion: completion)
                if self.holdWrites { self.heldWrites.append(work) } else { self.commit(work) }
            }))
            cloud = FavoritesCloudCoordinator(model: model, maximumKeys: maximumKeys, maximumConcurrentWrites: maximumConcurrentWrites,
                drainPendingWrites: { [weak self] uid in
                    guard let self else { throw Failure.injected }
                    let index = self.drains.count
                    try await withCheckedThrowingContinuation { continuation in
                        self.liveDrainIDs.insert(index); self.drains.append(.init(uid: uid, continuation: continuation))
                    }
                }, write: { [weak self] ticket, uid in
                    guard let self else { throw Failure.injected }
                    self.liveWrites += 1; self.peak = max(self.peak, self.liveWrites)
                    defer { self.liveWrites -= 1 }
                    let index = self.calls.count
                    try await withCheckedThrowingContinuation { continuation in
                        self.liveCallIDs.insert(index); self.calls.append(.init(ticket: ticket, uid: uid, continuation: continuation))
                    }
                })
            observation = model.changes.sink { [weak self] snapshot in
                guard let self else { return }
                guard snapshot.generation == self.model.snapshot.generation, snapshot.revision == self.model.snapshot.revision else { return }
                self.cloud.setOwner(expectedUserID: self.uid, generation: snapshot.generation)
            }
        }
        func owner(_ value: String?) {
            uid = value; model.changeContext(to: .confirmed(userID: value))
            cloud.setOwner(expectedUserID: value, generation: model.snapshot.generation)
        }
        func ready(_ uid: String) async {
            owner(uid)
            for _ in 0..<2000 { if !drains.isEmpty { break }; await Task.yield() }
            finishDrain(drains.count - 1)
            for _ in 0..<2000 { if model.snapshot.recoveryReady { return }; await Task.yield() }
            XCTFail("Expected recovery-ready fixture")
        }
        func finishDrain(_ index: Int, fail: Bool = false) {
            guard index >= 0, liveDrainIDs.remove(index) != nil else { return }
            if fail { drains[index].continuation.resume(throwing: Failure.injected) } else { drains[index].continuation.resume() }
        }
        func finishWrite(_ index: Int, fail: Bool = false) {
            guard liveCallIDs.remove(index) != nil else { return }
            if fail { calls[index].continuation.resume(throwing: Failure.injected) } else { calls[index].continuation.resume() }
        }
        func releaseWrite() {
            guard !heldWrites.isEmpty else { return }
            commit(heldWrites.removeFirst())
        }
        private func commit(_ work: HeldWrite) {
            if failWrites { work.completion(.failure(FavoritesJournalFailure.writeFailed)); return }
            guard records[work.namespace]?.recordRevision == work.expected else {
                work.completion(.failure(FavoritesJournalFailure.staleRevision)); return
            }
            records[work.namespace] = work.record; work.completion(.success(()))
        }
        func stop() {
            uid = nil; model.changeContext(to: .unresolved); cloud.setOwner(expectedUserID: nil, generation: model.snapshot.generation)
            holdWrites = false; failWrites = true
            while !heldWrites.isEmpty { releaseWrite() }
            for index in Array(liveDrainIDs) { finishDrain(index, fail: true) }
            for index in Array(liveCallIDs) { finishWrite(index, fail: true) }
        }
    }
}
