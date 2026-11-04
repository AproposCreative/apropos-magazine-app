import XCTest
@testable import Apropos

/// Every transport completion and deadline is driven by the test. No service,
/// URLSession, Firebase, timer, or app startup is created.
@MainActor
private final class DetailLoaderHarness {
    var bodyRequests: [(String, (Result<Article, Error>) -> Void)] = []
    var authorRequests: [(String, (Result<Author, Error>) -> Void)] = []
    var deadlines: [() -> Void] = []
    var cancelledDeadlines: Set<Int> = []
    var bodies: [Article] = []
    var authorUpdates: [(String, String, Author)] = []
    var failures: [String] = []
    var loading: Set<String> = []
    var offline: [String: Article] = [:]

    lazy var loader = ArticleDetailLoader(
        scheduleDeadline: { [unowned self] _, fire in
            let index = deadlines.count
            deadlines.append(fire)
            return { [weak self] in self?.cancelledDeadlines.insert(index) }
        },
        fetchArticle: { [unowned self] in bodyRequests.append(($0, $1)) },
        fetchAuthor: { [unowned self] in authorRequests.append(($0, $1)) },
        offlineArticle: { [unowned self] in offline[$0] },
        onBody: { [unowned self] article, _ in bodies.append(article) },
        onAuthor: { [unowned self] in authorUpdates.append(($0, $1, $2)) },
        onFailure: { [unowned self] id, _ in failures.append(id) },
        onLoadingChange: { [unowned self] in loading = $0 }
    )
}

final class ArticleDetailLoaderTests: XCTestCase {
    private func article(
        _ id: String, body: String = "", authorID: String? = nil,
        revision: String = "2026-10-20T08:00:00Z"
    ) -> Article {
        Article(
            id: id, name: id, slug: id, content: body, intro: "", topicID: "music",
            authorID: authorID, createdOn: "2026-10-19T08:00:00Z", lastPublished: revision
        )
    }

    private var author: Author {
        Author(id: "writer", name: "Maja", bio: nil, imageURL: nil, position: "", photoURL: "")
    }

    @MainActor
    func testRapidSelectionKeepsOneTransportAndOnlyLatestPendingArticle() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A")
        h.loader.select(id: "B")
        h.loader.select(id: "C")
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A"])
        XCTAssertEqual(h.loading, ["C"])
        h.bodyRequests[0].1(.success(article("A", body: "obsolete", authorID: "writer")))
        XCTAssertTrue(h.bodies.isEmpty)
        XCTAssertTrue(h.authorRequests.isEmpty)
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A", "C"])
        h.bodyRequests[1].1(.success(article("C", body: "selected")))
        XCTAssertEqual(h.bodies.map(\.id), ["C"])
        XCTAssertTrue(h.loading.isEmpty)
    }

    @MainActor
    func testLateCallbackAndOldDeadlineCannotReleaseNewerRetry() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A")
        h.deadlines[0]()
        XCTAssertEqual(h.failures, ["A"])
        h.loader.select(id: "A")
        h.loader.select(id: "C")
        h.bodyRequests[0].1(.success(article("A", body: "old request")))
        h.deadlines[0]() // A cancelled timer may already have been enqueued.
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A", "A"])
        XCTAssertTrue(h.bodies.isEmpty)
        h.bodyRequests[1].1(.failure(URLError(.notConnectedToInternet)))
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A", "A", "C"])
        h.bodyRequests[2].1(.success(article("C", body: "current")))
        XCTAssertEqual(h.bodies.map(\.id), ["C"])
    }

    @MainActor
    func testRepeatedSelectionJoinsOneTransportAndDuplicateCompletionIsIgnored() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A")
        h.loader.select(id: "A")
        XCTAssertEqual(h.bodyRequests.count, 1)
        h.bodyRequests[0].1(.success(article("A", body: "body", authorID: "writer")))
        h.bodyRequests[0].1(.success(article("A", body: "duplicate", authorID: "writer")))
        XCTAssertEqual(h.bodies.map(\.content), ["body"])
        XCTAssertEqual(h.authorRequests.count, 1)
        h.authorRequests[0].1(.success(author))
        h.authorRequests[0].1(.success(author))
        XCTAssertEqual(h.authorUpdates.count, 1)
        XCTAssertTrue(h.cancelledDeadlines.contains(0))
        XCTAssertTrue(h.loading.isEmpty)
    }

    @MainActor
    func testBodyPublishesBeforeOptionalAuthorAndAuthorTimeoutKeepsFreshBody() {
        let h = DetailLoaderHarness()
        h.offline["A"] = article("A", body: "older offline")
        h.loader.select(id: "A")
        h.bodyRequests[0].1(.success(article("A", body: "fresh body", authorID: "writer")))
        XCTAssertEqual(h.bodies.map(\.content), ["fresh body"])
        XCTAssertEqual(h.authorRequests.map(\.0), ["writer"])
        h.deadlines[0]()
        h.authorRequests[0].1(.success(author))
        XCTAssertEqual(h.bodies.map(\.content), ["fresh body"])
        XCTAssertTrue(h.authorUpdates.isEmpty)
        XCTAssertTrue(h.loading.isEmpty)
    }

    @MainActor
    func testMetadataAuthorDoesNotSuppressBodyRequestAndEmptyFeedCanLoad() {
        let h = DetailLoaderHarness()
        var metadata = article("A", authorID: "writer")
        metadata.author = author
        h.loader.select(id: "A", cached: metadata)
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A"])
        var full = article("A", body: "body", authorID: "writer")
        full.author = author
        h.bodyRequests[0].1(.success(full))
        XCTAssertEqual(h.bodies.map(\.content), ["body"])
        XCTAssertTrue(h.authorRequests.isEmpty)
        // A selection without any feed/cache value is also a normal body load.
        h.loader.select(id: "new-not-in-feed")
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A", "new-not-in-feed"])
    }

    @MainActor
    func testCachedBodyPublishesImmediatelyAndOnlyMissingAuthorIsLoaded() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A", cached: article("A", body: "cached", authorID: "writer"))
        XCTAssertEqual(h.bodies.map(\.content), ["cached"])
        XCTAssertTrue(h.bodyRequests.isEmpty)
        XCTAssertEqual(h.authorRequests.map(\.0), ["writer"])
        h.authorRequests[0].1(.success(author))
        XCTAssertEqual(h.authorUpdates.first?.0, "A")
        XCTAssertEqual(h.authorUpdates.first?.2.name, "Maja")
    }

    @MainActor
    func testDeselectRejectsLateBodyAndDoesNotRemoveNewSelection() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A")
        h.loader.deselect(id: "A")
        h.loader.select(id: "B")
        h.loader.deselect(id: "A") // Disappearing previous screen.
        h.bodyRequests[0].1(.success(article("A", body: "old")))
        XCTAssertTrue(h.bodies.isEmpty)
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A", "B"])
        h.bodyRequests[1].1(.success(article("B", body: "new")))
        XCTAssertEqual(h.bodies.map(\.id), ["B"])
    }

    @MainActor
    func testExplicitWithdrawalNeverPublishesAnOfflineBody() {
        let h = DetailLoaderHarness()
        h.offline["A"] = article("A", body: "withdrawn old body")
        h.loader.select(id: "A")
        h.bodyRequests[0].1(.failure(FirestoreArticleError.withdrawn))
        XCTAssertTrue(h.bodies.isEmpty)
        XCTAssertEqual(h.failures, ["A"])
        XCTAssertTrue(h.loading.isEmpty)
    }

    @MainActor
    func testWithdrawnRequestCannotBeRejoinedAfterRepublicationOfSameID() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A")
        h.loader.invalidate(id: "A")
        h.loader.select(id: "A")
        XCTAssertEqual(h.bodyRequests.count, 1) // Hold the old transport slot.
        h.bodyRequests[0].1(.success(article("A", body: "obsolete completion")))
        XCTAssertTrue(h.bodies.isEmpty)
        XCTAssertEqual(h.bodyRequests.count, 2)
        h.bodyRequests[1].1(.success(article("A", body: "republished body")))
        XCTAssertEqual(h.bodies.map(\.content), ["republished body"])
    }

    @MainActor
    func testFailureFallbackOnlyPublishesForCurrentSelection() {
        let h = DetailLoaderHarness()
        h.offline["A"] = article("A", body: "offline A")
        h.offline["B"] = article("B", body: "offline B")
        h.loader.select(id: "A")
        h.loader.select(id: "B")
        h.bodyRequests[0].1(.failure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(h.bodies.isEmpty)
        XCTAssertTrue(h.failures.isEmpty)
        h.bodyRequests[1].1(.failure(URLError(.notConnectedToInternet)))
        XCTAssertEqual(h.bodies.map(\.content), ["offline B"])
        XCTAssertEqual(h.failures, ["B"])
    }

    @MainActor
    func testOfflineCachedBodyRequiresNoTransportOrDeadline() {
        let h = DetailLoaderHarness()
        h.loader.select(id: "A", cached: article("A", body: "offline", authorID: "writer"), canFetch: false)
        h.loader.select(id: "B", cached: article("B"), canFetch: false)
        h.loader.select(id: "  ")
        XCTAssertEqual(h.bodies.map(\.content), ["offline"])
        XCTAssertTrue(h.bodyRequests.isEmpty)
        XCTAssertTrue(h.authorRequests.isEmpty)
        XCTAssertTrue(h.deadlines.isEmpty)
        XCTAssertTrue(h.loading.isEmpty)
    }

    func testCachedBodyMustMatchCurrentFeedRevision() {
        let feed = article("A", revision: "2026-10-20T09:00:00Z")
        let stale = article("A", body: "old body")
        let result = ArticleDetailContentPolicy.cachedArticle(id: "A", feed: feed, full: stale, initial: stale)
        XCTAssertEqual(result?.lastPublished, feed.lastPublished)
        XCTAssertFalse(ArticleDetailContentPolicy.hasBody(result))
        XCTAssertEqual(ArticleDetailContentPolicy.cachedArticle(id: "A", feed: nil, full: stale, initial: nil)?.content, "old body")
        let matching = feed.replacingBodyContent("current body")
        XCTAssertEqual(ArticleDetailContentPolicy.cachedArticle(id: "A", feed: feed, full: matching, initial: stale)?.content, "current body")
    }

    func testLateAuthorPatchesCurrentBodyWithoutRestoringSnapshotOrWrongAuthor() {
        let current = article("A", body: "new body", authorID: "writer", revision: "2026-10-20T09:00:00Z")
        let updated = ArticleDetailContentPolicy.applyingAuthor(author, articleID: "A", authorID: "writer", to: current)
        XCTAssertEqual(updated?.content, "new body")
        XCTAssertEqual(updated?.lastPublished, current.lastPublished)
        XCTAssertEqual(updated?.author, author)
        XCTAssertNil(ArticleDetailContentPolicy.applyingAuthor(author, articleID: "A", authorID: "old-writer", to: current))
        XCTAssertNil(ArticleDetailContentPolicy.applyingAuthor(author, articleID: "B", authorID: "writer", to: current))
    }

    func testLateDetailCannotOverwriteFeedRevisionCommittedSinceRequestStarted() {
        let initial = article("A")
        let newer = article("A", body: "new feed body", revision: "2026-10-20T09:00:00Z")
        XCTAssertFalse(ArticleDetailContentPolicy.canApplyFetchedBody(initial.replacingBodyContent("old"), requestedFrom: initial, current: newer))
        XCTAssertTrue(ArticleDetailContentPolicy.canApplyFetchedBody(newer, requestedFrom: initial, current: newer))
        XCTAssertTrue(ArticleDetailContentPolicy.canApplyFetchedBody(newer, requestedFrom: initial, current: initial))
        XCTAssertTrue(ArticleDetailContentPolicy.canApplyFetchedBody(newer, requestedFrom: nil, current: nil))
        XCTAssertFalse(ArticleDetailContentPolicy.canApplyFetchedBody(initial, requestedFrom: nil, current: newer))
        XCTAssertFalse(ArticleDetailContentPolicy.canApplyFetchedBody(initial, requestedFrom: newer, current: newer))
        let fractionalOlder = article("A", body: "cached", revision: "2026-10-20T08:59:59.999Z")
        XCTAssertFalse(ArticleDetailContentPolicy.canApplyFetchedBody(fractionalOlder, requestedFrom: newer, current: newer))
    }

    @MainActor
    func testSameIDNewRevisionRequestsAgainWithoutLoopingOnBodyOrAuthorUpdates() {
        let h = DetailLoaderHarness()
        let initial = article("A")
        let newer = article("A", revision: "2026-10-20T09:00:00Z")
        XCTAssertNotEqual(ArticleDetailRequestIdentity(initial), ArticleDetailRequestIdentity(newer))
        var enriched = newer.replacingBodyContent("new body")
        enriched.author = author
        XCTAssertEqual(ArticleDetailRequestIdentity(newer), ArticleDetailRequestIdentity(enriched))
        h.loader.select(id: "A", cached: initial)
        h.loader.select(id: "A", cached: newer)
        XCTAssertEqual(h.bodyRequests.count, 1)
        h.bodyRequests[0].1(.success(initial.replacingBodyContent("obsolete body")))
        XCTAssertTrue(h.bodies.isEmpty)
        XCTAssertEqual(h.bodyRequests.map(\.0), ["A", "A"])
        h.bodyRequests[1].1(.success(newer.replacingBodyContent("current body")))
        XCTAssertEqual(h.bodies.map(\.content), ["current body"])
        XCTAssertTrue(h.loading.isEmpty)
    }

    @MainActor
    func testDeinitCancelsActiveDeadline() {
        var cancelled = false
        var loader: ArticleDetailLoader? = ArticleDetailLoader(
            scheduleDeadline: { _, _ in { cancelled = true } },
            fetchArticle: { _, _ in }, fetchAuthor: { _, _ in },
            onBody: { _, _ in }, onAuthor: { _, _, _ in }
        )
        loader?.select(id: "A")
        loader = nil
        XCTAssertTrue(cancelled)
    }
}
