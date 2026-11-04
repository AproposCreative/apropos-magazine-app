import Combine
import XCTest
@testable import Apropos

final class ArticleFeedPublicationTests: XCTestCase {
    private func article(_ id: String) -> Article {
        Article(id: id, name: id, slug: id, content: "", intro: "", topicID: "topic", isDraft: false,
                createdOn: "2026-01-01T00:00:00Z", lastPublished: "2026-01-01T00:00:00Z")
    }

    @MainActor
    func testLiveResultDuringCacheWillChangeCannotBeOverwritten() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let original = startup.capture()
        let live = article("live")
        let subscription = feed.objectWillChange.sink {
            startup.invalidate()
            feed.replace([live])
        }
        XCTAssertNil(startup.adopt([article("cached")], original: original))
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["live"])
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testAuthoritativeEmptyLiveResultAlsoWinsDuringWillChange() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let original = startup.capture()
        let subscription = feed.objectWillChange.sink {
            startup.invalidate()
            feed.replace([])
        }
        XCTAssertNil(startup.adopt([article("cached")], original: original))
        XCTAssertTrue(feed.snapshot.articles.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testPermissionGetterReentryCannotResumeOlderCacheEffect() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let original = startup.capture()
        XCTAssertNil(startup.adopt([article("cached")], original: original, stillPermitted: {
            startup.invalidate()
            feed.replace([self.article("fresh")])
            return true
        }))
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["fresh"])
    }

    @MainActor
    func testSubscriberReentryFiltersSuspendedOuterSnapshotForEachSubscriber() {
        let feed = ArticleFeedPublication()
        let current = article("newer")
        var first: [[String]] = [], second: [[String]] = []
        let a = feed.changes.sink { snapshot in
            first.append(snapshot.articles.map(\.id))
            if snapshot.articles.first?.id == "older" { feed.replace([current]) }
        }
        let b = feed.changes.sink { second.append($0.articles.map(\.id)) }
        XCTAssertNil(feed.replace([article("older")]))
        XCTAssertEqual(first.last, ["newer"])
        XCTAssertEqual(second.last, ["newer"])
        // Subscriber order is unspecified: an older value may precede newer,
        // but can never arrive after the nested newer committed publication.
        XCTAssertFalse(second.suffix(2).elementsEqual([["newer"], ["older"]]))
        withExtendedLifetime((a, b)) {}
    }

    @MainActor
    func testSameCommittedRequestDuringWillChangeCancelsOuterProposal() {
        let feed = ArticleFeedPublication()
        feed.replace([article("kept")])
        let subscription = feed.objectWillChange.sink { feed.replace([self.article("kept")]) }
        XCTAssertNil(feed.replace([article("discarded")]))
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["kept"])
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testExplicitFeedReplacementInvalidatesCapturedCacheWithoutNetworkSideEffects() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let original = startup.capture()
        feed.replace([article("newer")])
        XCTAssertFalse(startup.isCurrent(original))
        XCTAssertNil(startup.adopt([article("cached")], original: original))
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["newer"])
    }

    @MainActor
    func testLivePublicationRetainsItsOwnReceiptForCacheAndFollowupEffects() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        feed.replace([article("old")])
        startup.invalidate()
        let original = startup.capture()
        let receipt = startup.adopt([article("fresh")], original: original)
        XCTAssertNotNil(receipt)
        XCTAssertTrue(startup.isCurrent(original))
        XCTAssertTrue(feed.isCurrent(receipt!))
        var effects = 0
        if startup.isCurrent(original), feed.isCurrent(receipt!) { effects += 1 }
        XCTAssertEqual(effects, 1)
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["fresh"])
    }

    @MainActor
    func testOriginalStartupTicketFollowsOnlyItsOwnAcceptedPublication() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let original = startup.capture()
        let receipt = startup.adopt([article("cached")], original: original)!
        XCTAssertTrue(startup.isCurrent(original))
        XCTAssertTrue(feed.isCurrent(receipt))
        feed.replace([article("detail-newer")])
        XCTAssertFalse(startup.isCurrent(original))
        XCTAssertFalse(feed.isCurrent(receipt))
    }

    @MainActor
    func testReceiptCannotAuthorizeEffectsAfterNewCommit() {
        let feed = ArticleFeedPublication()
        let receipt = feed.replace([article("one")])!
        XCTAssertTrue(feed.isCurrent(receipt))
        feed.replace([article("two")])
        XCTAssertFalse(feed.isCurrent(receipt))
    }

    @MainActor
    func testLiveFailureDoesNotInvalidateUsableCacheProposal() {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let original = startup.capture()
        // No invalidate is performed on a failed transport in the actual adapter.
        XCTAssertNotNil(startup.adopt([article("cached")], original: original))
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["cached"])
    }

    @MainActor
    func testActualDecoderAndStartupPublicationShareOriginalAdmission() async throws {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let worker = ArticleCacheDecodeWorker()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let data = try JSONEncoder().encode(CacheData(articles: [article("cache")], timestamp: date, version: "1.3"))
        let coordinator = ArticleCacheHydrationCoordinator(read: { .encoded(data) },
            prepare: { await worker.prepare($0, policy: $1) }, now: { date })
        let original = startup.capture()
        let capture = coordinator.capture()
        let decoded = await coordinator.load(capture, stillPermitted: { startup.isCurrent(original) })
        XCTAssertNotNil(startup.adopt(decoded.articles ?? [], original: original,
                                     stillPermitted: { coordinator.isCurrent(capture) }))
        XCTAssertEqual(feed.snapshot.articles.map(\.id), ["cache"])
    }

    @MainActor
    func testActualCacheClearDuringPublicationCannotReintroduceDecodedValue() async {
        let feed = ArticleFeedPublication()
        let startup = ArticleFeedStartupAdmission(feed: feed)
        let worker = ArticleCacheDecodeWorker()
        let date = Date()
        let cached = article("cache")
        let coordinator = ArticleCacheHydrationCoordinator(read: { .memory(articles: [cached], timestamp: date, articlesAreSorted: true) },
            prepare: { await worker.prepare($0, policy: $1) }, now: { date })
        let original = startup.capture(), capture = coordinator.capture()
        let decoded = await coordinator.load(capture)
        let subscription = feed.objectWillChange.sink { coordinator.invalidate() }
        XCTAssertNil(startup.adopt(decoded.articles ?? [], original: original,
                                  stillPermitted: { coordinator.isCurrent(capture) }))
        XCTAssertTrue(feed.snapshot.articles.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testPodcastCatalogReentryCannotRestoreRemovedEpisode() {
        let catalog = PodcastCatalogPublication()
        let episode = PodcastEpisode(id: "episode", articleId: nil, articleSlug: nil, title: "Audio", subtitle: nil, audioURL: nil, productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
        let subscription = catalog.objectWillChange.sink { catalog.replace([]) }
        catalog.replace([episode])
        XCTAssertTrue(catalog.snapshot.episodes.isEmpty)
        withExtendedLifetime(subscription) {}
    }
}
