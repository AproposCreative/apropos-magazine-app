import XCTest
@testable import Apropos

@MainActor
private final class AvailabilityHarness {
    var handlers: [(Result<ArticleAvailabilityModel.Update, Error>) -> Void] = []
    var cancelled = Set<Int>()
    var deadlines: [() -> Void] = []
    var saved: [ArticleAvailabilityModel.Snapshot] = []
    var onCancel: (() -> Void)?
    lazy var model = ArticleAvailabilityModel(save: { [unowned self] in saved.append($0) }, schedule: { [unowned self] fire in
        deadlines.append(fire)
        return {}
    })
    func watch(_ id: String = "A") {
        model.observe(id: id) { [unowned self] _, callback in
            let index = handlers.count
            handlers.append(callback)
            return { [weak self] in self?.cancelled.insert(index); self?.onCancel?() }
        }
    }
    func send(_ index: Int = 0, withdrawn: Bool, cached: Bool = false, revision: String? = nil) {
        handlers[index](.success(.init(withdrawn: withdrawn, isFromCache: cached, revision: revision)))
    }
}

final class ArticleAvailabilityModelTests: XCTestCase {
    private func article(_ id: String = "A", revision: String = "v1") -> Article {
        Article(id: id, name: "Story", slug: id, content: "Previously downloaded body", intro: "", topicID: "music",
                isDraft: false, lastPublished: revision)
    }

    @MainActor
    func testServerWithdrawalBlocksContentAndPersistsAcrossModelRecreation() throws {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: true)
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
        XCTAssertNil(h.model.sanitized(article()))
        let data = try JSONEncoder().encode(h.saved.last!)
        let saved = try JSONDecoder().decode(ArticleAvailabilityModel.Snapshot.self, from: data)
        let restored = ArticleAvailabilityModel(snapshot: saved, schedule: { _ in {} })
        XCTAssertFalse(restored.permitsBody(article()))
        XCTAssertTrue(restored.withdrawnIDs.contains("A"))
    }

    @MainActor
    func testCachedPublicSnapshotAndConnectionFailureCannotRestoreWithdrawnArticle() {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: true)
        h.send(withdrawn: false, cached: true, revision: "v1")
        h.handlers[0](.failure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
        XCTAssertNotNil(h.model.errorMessage)
        XCTAssertNil(h.model.sanitized(article()))
    }

    @MainActor
    func testFreshRepublicationPermitsOnlyTheConfirmedRevisionIncludingAfterRestart() throws {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: true)
        h.send(withdrawn: false, revision: "v2")
        XCTAssertFalse(h.model.withdrawnIDs.contains("A"))
        XCTAssertFalse(h.model.permitsBody(article(revision: "v1")))
        XCTAssertEqual(h.model.sanitized(article(revision: "v1"))?.name, "Artiklen er opdateret")
        XCTAssertEqual(h.model.sanitized(article(revision: "v1"))?.intro, "")
        XCTAssertNil(h.model.sanitized(article(revision: "v1"))?.authorID)
        XCTAssertTrue(h.model.sanitized(article(revision: "v1"))?.content?.isEmpty != false)
        XCTAssertTrue(h.model.permitsBody(article(revision: "v2")))
        let saved = try JSONDecoder().decode(ArticleAvailabilityModel.Snapshot.self,
                                            from: JSONEncoder().encode(h.saved.last!))
        let restored = ArticleAvailabilityModel(snapshot: saved, schedule: { _ in {} })
        XCTAssertTrue(restored.permitsBody(article(revision: "v2")))
        XCTAssertFalse(restored.permitsBody(article(revision: "v1")))
    }

    @MainActor
    func testReadStartedBeforeFreshObserverCannotReblockNewPublication() {
        let h = AvailabilityHarness(); let old = h.model.beginRead()
        h.watch(); h.send(withdrawn: true); h.send(withdrawn: false, revision: "v2")
        h.model.recordWithdrawals(["A"], ticket: old)
        XCTAssertFalse(h.model.withdrawnIDs.contains("A"))
        let fresh = h.model.beginRead()
        h.model.recordWithdrawals(["A"], ticket: fresh)
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
    }

    @MainActor
    func testOldReaderCallbacksAndOldDisappearanceCannotAffectNewReader() {
        let h = AvailabilityHarness(); h.watch("A"); h.watch("B")
        h.model.stop(id: "A")
        h.send(0, withdrawn: true)
        h.send(1, withdrawn: true)
        XCTAssertEqual(h.model.withdrawnIDs, ["B"])
        XCTAssertEqual(h.cancelled, [0])
    }

    @MainActor
    func testLateDeadlineDoesNotEndNewObservationAndCurrentDeadlinePreservesWithdrawal() {
        let h = AvailabilityHarness(); h.watch("A"); h.watch("B")
        h.deadlines[0]()
        XCTAssertEqual(h.model.checkingID, "B")
        h.send(1, withdrawn: true, cached: true)
        h.deadlines[1]()
        XCTAssertNil(h.model.checkingID)
        XCTAssertTrue(h.model.withdrawnIDs.contains("B"))
        XCTAssertNotNil(h.model.errorMessage)
    }

    @MainActor
    func testUnversionedPublicStateCannotRestoreKnownWithdrawal() {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: true)
        h.send(withdrawn: false)
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
        XCTAssertNotNil(h.model.errorMessage)
    }

    @MainActor
    func testCachedWithdrawalAfterAuthoritativePublicationIsIgnoredForSameObserver() {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: true)
        h.send(withdrawn: false, revision: "v2")
        h.send(withdrawn: true, cached: true)
        XCTAssertFalse(h.model.withdrawnIDs.contains("A"))
        XCTAssertTrue(h.model.permitsBody(article(revision: "v2")))
    }

    @MainActor
    func testRetryRejectsOldCallbackAndCanRecoverAfterConnectionReturns() {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: true)
        h.handlers[0](.failure(URLError(.notConnectedToInternet)))
        h.watch()
        h.send(0, withdrawn: false, revision: "v1")
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
        h.send(1, withdrawn: false, revision: "v2")
        XCTAssertNil(h.model.errorMessage)
        XCTAssertFalse(h.model.withdrawnIDs.contains("A"))
    }

    @MainActor
    func testCancellationInvalidatesBeforeSynchronousTransportCallback() {
        let h = AvailabilityHarness(); h.watch()
        h.onCancel = { [unowned h] in h.send(withdrawn: true) }
        h.model.stop(id: "A")
        XCTAssertTrue(h.model.withdrawnIDs.isEmpty)
        XCTAssertEqual(h.cancelled, [0])
    }

    @MainActor
    func testUnrelatedFavoriteSurvivesInitialSanitizationAndLateCloudSnapshot() {
        let model = ArticleAvailabilityModel(snapshot: .init(withdrawnIDs: ["A"]), schedule: { _ in {} })
        let values = [article("A"), article("B")]
        XCTAssertEqual(values.compactMap { model.sanitized($0) }.map(\.id), ["B"])
        XCTAssertTrue(model.permitsBody(article("B")))
    }

    @MainActor
    func testConfirmedQueryStatesEndCheckingAndLateDeadlinesCannotReplaceThemWithTimeouts() {
        let h = AvailabilityHarness(); h.watch()
        h.model.recordWithdrawals(["A"], ticket: h.model.beginRead())
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
        XCTAssertNil(h.model.checkingID)
        h.deadlines[0]()
        XCTAssertNil(h.model.errorMessage)
        XCTAssertTrue(h.model.withdrawnIDs.contains("A"))
        h.watch()
        h.model.recordPublications([article(revision: "v2")], ticket: h.model.beginRead())
        XCTAssertNil(h.model.checkingID)
        h.deadlines[1]()
        XCTAssertNil(h.model.errorMessage)
        XCTAssertFalse(h.model.withdrawnIDs.contains("A"))
    }

    @MainActor
    func testSynchronousAvailabilityEventsFenceRealDetailLoaderAcrossImmediateRepublication() {
        let h = AvailabilityHarness()
        var requests: [(Result<Article, Error>) -> Void] = []
        var bodies: [Article] = []
        let loader = ArticleDetailLoader(scheduleDeadline: { _, _ in {} },
                                         fetchArticle: { _, completion in requests.append(completion) },
                                         fetchAuthor: { _, _ in }, permitsBody: { h.model.permitsBody($0) },
                                         onBody: { value, _ in bodies.append(value) }, onAuthor: { _, _, _ in })
        let observation = h.model.changes.sink { change in
            for id in change.invalidatedBodyIDs { loader.invalidate(id: id) }
        }
        loader.select(id: "A")
        h.watch(); h.send(withdrawn: true); h.send(withdrawn: false, revision: "v2")
        loader.select(id: "A")
        XCTAssertEqual(requests.count, 1)
        requests[0](.success(article(revision: "v1")))
        XCTAssertTrue(bodies.isEmpty)
        XCTAssertEqual(requests.count, 2)
        requests[1](.success(article(revision: "v2")))
        XCTAssertEqual(bodies.map(\.lastPublished), ["v2"])
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testAuthoritativeRevisionUpdateCannotLeaveAnOlderOpenArticleBodyVisible() {
        let h = AvailabilityHarness(); h.watch()
        XCTAssertTrue(h.model.permitsBody(article(revision: "v1")))
        h.send(withdrawn: false, revision: "v2")
        XCTAssertFalse(h.model.withdrawnIDs.contains("A"))
        XCTAssertFalse(h.model.permitsBody(article(revision: "v1")))
        XCTAssertEqual(h.model.sanitized(article(revision: "v1"))?.name, "Artiklen er opdateret")
        XCTAssertTrue(h.model.permitsBody(article(revision: "v2")))
    }

    @MainActor
    func testCachedPublicationCannotDowngradeAnApprovedCurrentRevision() {
        let h = AvailabilityHarness(); h.watch()
        h.send(withdrawn: false, revision: "v2")
        h.send(withdrawn: false, cached: true, revision: "v1")
        XCTAssertEqual(h.model.approvedRevision(for: "A"), "v2")
        XCTAssertFalse(h.model.permitsBody(article(revision: "v1")))
        XCTAssertTrue(h.model.permitsBody(article(revision: "v2")))
    }

    @MainActor
    func testFreshCatalogUpdatesAnEarlierReaderRevisionWhileReaderIsClosed() {
        let h = AvailabilityHarness(); h.watch(); h.send(withdrawn: false, revision: "v1"); h.model.stop()
        h.model.recordPublications([article(revision: "v2")], ticket: h.model.beginRead())
        XCTAssertTrue(h.model.permitsBody(article(revision: "v2")))
        XCTAssertFalse(h.model.permitsBody(article(revision: "v1")))
    }

    @MainActor
    func testCatalogBatchPersistsAndInvalidatesOnceInsteadOfOncePerArticle() {
        var saves = 0
        var events: [ArticleAvailabilityModel.Change] = []
        let ids = (0..<50).map(String.init)
        let model = ArticleAvailabilityModel(snapshot: .init(approvedRevisions: Dictionary(uniqueKeysWithValues: ids.map { ($0, "v1") })),
                                             save: { _ in saves += 1 }, schedule: { _ in {} })
        let observation = model.changes.sink { events.append($0) }
        model.recordPublications(ids.map { article($0, revision: "v2") }, ticket: model.beginRead())
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].invalidatedBodyIDs, Set(ids))
        XCTAssertFalse(events[0].refreshFeed) // This catalog is already being delivered.
        XCTAssertTrue(ids.allSatisfy { model.permitsBody(article($0, revision: "v2")) })
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testUnvisitedCatalogRowsDoNotCreateExtraPerReaderState() {
        var saves = 0
        let model = ArticleAvailabilityModel(save: { _ in saves += 1 }, schedule: { _ in {} })
        model.recordPublications([article()], ticket: model.beginRead())
        XCTAssertEqual(saves, 0)
        XCTAssertNil(model.approvedRevision(for: "A"))
    }

    @MainActor
    func testSynchronousInitialServerResultDoesNotLeaveCheckingOrCreateDeadline() {
        var schedules = 0
        let model = ArticleAvailabilityModel(schedule: { _ in schedules += 1; return {} })
        model.observe(id: "A") { _, completion in
            completion(.success(.init(withdrawn: true, isFromCache: false)))
            return {}
        }
        XCTAssertNil(model.checkingID)
        XCTAssertEqual(schedules, 0)
        XCTAssertTrue(model.withdrawnIDs.contains("A"))
    }
}
