import XCTest
@testable import Apropos

final class ArticleListenActionTests: XCTestCase {
    private func episode(audio: String = "original", revision: String = "r1") -> PodcastEpisode {
        PodcastEpisode(id: "audio", articleId: "article", articleSlug: "article", title: "Artikel",
            subtitle: nil, audioURL: URL(string: "https://example.invalid/\(audio).mp3"),
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil,
            sourceContentRevision: revision)
    }

    @MainActor
    func testCurrentCatalogRecordingCanPlay() {
        let catalog = PodcastCatalogPublication()
        let offered = episode()
        catalog.replace([offered])
        var played: [PodcastEpisode] = []
        XCTAssertTrue(ArticleListenAction.perform(offered: offered,
            resolve: { catalog.snapshot.episodes.first }, play: { played.append($0) }))
        XCTAssertEqual(played, [offered])
    }

    @MainActor
    func testRemovedRecordingCannotPlayFromEarlierButton() {
        let catalog = PodcastCatalogPublication()
        let offered = episode()
        catalog.replace([offered])
        catalog.replace([])
        XCTAssertFalse(ArticleListenAction.perform(offered: offered,
            resolve: { catalog.snapshot.episodes.first }, play: { _ in XCTFail("Removed audio played") }))
    }

    @MainActor
    func testSameIDReplacementCannotReuseEarlierButton() {
        let catalog = PodcastCatalogPublication()
        let offered = episode()
        catalog.replace([episode(audio: "replacement")])
        XCTAssertFalse(ArticleListenAction.perform(offered: offered,
            resolve: { catalog.snapshot.episodes.first }, play: { _ in XCTFail("Replacement played from old intent") }))
        catalog.replace([episode(revision: "r2")])
        XCTAssertFalse(ArticleListenAction.perform(offered: offered,
            resolve: { catalog.snapshot.episodes.first }, play: { _ in XCTFail("Revised audio played from old intent") }))
    }

    @MainActor
    func testFreshWithdrawalIsRecheckedAtTap() {
        let availability = ArticleAvailabilityModel(schedule: { _ in {} })
        let article = Article(id: "article", name: "Artikel", slug: "article", content: "", intro: "", topicID: "topic",
            isDraft: false, lastPublished: "2026-10-20T10:00:00Z", contentRevision: "r1")
        let offered = episode()
        let resolve = { availability.permitsBody(article) ? offered : nil }
        XCTAssertEqual(resolve(), offered)
        availability.recordWithdrawals([article.id], ticket: availability.beginRead())
        XCTAssertFalse(ArticleListenAction.perform(offered: offered, resolve: resolve,
            play: { _ in XCTFail("Withdrawn article played") }))
    }

    @MainActor
    func testOfflineAccessIsRecheckedAtTap() {
        let offered = episode()
        var online = true
        var downloaded: PodcastEpisode?
        let resolve = { online || downloaded == offered ? offered : nil }
        XCTAssertEqual(resolve(), offered)
        online = false
        downloaded = episode(audio: "different-recording")
        XCTAssertFalse(ArticleListenAction.perform(offered: offered, resolve: resolve,
            play: { _ in XCTFail("Different offline audio admitted") }))
        downloaded = offered
        var count = 0
        XCTAssertTrue(ArticleListenAction.perform(offered: offered, resolve: resolve, play: { _ in count += 1 }))
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testVisibleOfflineExplanationDoesNotAuthorizePlayback() {
        let offered = episode()
        var resolved = 0
        XCTAssertFalse(ArticleListenAction.perform(offered: offered,
            resolve: { resolved += 1; return offered }, isEnabled: { false },
            play: { _ in XCTFail("Disabled offline action played") }))
        XCTAssertEqual(resolved, 0)
    }

    @MainActor
    func testConnectivityLossDuringCatalogResolutionCannotStartPlayback() {
        let offered = episode()
        var online = true
        XCTAssertFalse(ArticleListenAction.perform(offered: offered,
            resolve: { online = false; return offered }, isEnabled: { online },
            play: { _ in XCTFail("Network loss during tap resolution played") }))
    }
    @MainActor
    func testDisplayMetadataRefreshKeepsTheSameRecordingAndUsesFreshPresentation() {
        let catalog = PodcastCatalogPublication(), offered = episode()
        let refreshed = PodcastEpisode(id: offered.id, articleId: offered.articleId,
            articleSlug: offered.articleSlug, title: "Opdateret visning", subtitle: "Nyt resumé",
            audioURL: offered.audioURL, productionSourceURL: offered.productionSourceURL,
            duration: "4:34", artworkURL: URL(string: "https://example.invalid/new-cover.jpg"),
            hosts: ["Peter Milo"], publishedDate: Date(timeIntervalSince1970: 1_793_000_000),
            isAINarration: offered.isAINarration, sourceContentRevision: offered.sourceContentRevision)
        catalog.replace([offered]); catalog.replace([refreshed])
        var played: [PodcastEpisode] = []
        XCTAssertTrue(ArticleListenAction.perform(offered: offered,
            resolve: { catalog.snapshot.episodes.first }, play: { played.append($0) }))
        XCTAssertEqual(played, [refreshed], "Display metadata must not silently reject the same recording")
    }

    @MainActor
    func testDisplayMetadataRefreshDuringPreparedLocalStartKeepsOriginalRecordingIntent() async throws {
        let offered = episode(), catalog = PodcastCatalogPublication()
        catalog.replace([offered])
        let store = PodcastPlaybackProgressStore(storage: .init(read: { _ in nil }, write: { _, _ in }))
        store.changeContext(to: .confirmed(userID: "A"))
        let coordinator = PodcastPlaybackSessionCoordinator(store: store, effects: .init(
            cancelCallbacks: {}, stopPlayback: {}, clearPresentation: {}, clearNowPlaying: {}, deactivateAudio: {}))
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: offered.id,
            canonicalArticleID: "article", kind: .human, sourceRevision: "r1", remoteURL: try XCTUnwrap(offered.audioURL)))
        let ticket = try XCTUnwrap(coordinator.beginPreparation(asset: asset,
            routeIsCurrent: { ArticleListenAction.perform(offered: offered,
                resolve: { catalog.snapshot.episodes.first }, play: { _ in }) }, accessIsCurrent: { true }))
        let result = await coordinator.prepare(ticket) {
            catalog.replace([PodcastEpisode(id: offered.id, articleId: offered.articleId,
                articleSlug: offered.articleSlug, title: "Samme lyd, nyt cover", subtitle: nil,
                audioURL: offered.audioURL, productionSourceURL: offered.productionSourceURL,
                duration: "4:34", artworkURL: URL(string: "https://example.invalid/updated-cover.jpg"),
                hosts: [], publishedDate: nil, isAINarration: offered.isAINarration,
                sourceContentRevision: offered.sourceContentRevision)])
            return true
        }
        XCTAssertEqual(result, true, "Verified local bytes must survive a harmless display refresh")
        XCTAssertTrue(coordinator.isCurrent(ticket))
        XCTAssertTrue(coordinator.consumePreparation(ticket))
        let session = try XCTUnwrap(coordinator.beginSession(episodeID: offered.id, articleID: "article"))
        XCTAssertTrue(coordinator.isCurrent(session.ticket))
    }

    @MainActor
    func testEveryRecordingAndOwnershipFieldStillRejectsAChangedIntent() {
        let offered = episode()
        func changed(_ field: Int) -> PodcastEpisode {
            PodcastEpisode(id: field == 0 ? "other" : offered.id,
                articleId: field == 1 ? "other-article" : offered.articleId,
                articleSlug: field == 2 ? "other-slug" : offered.articleSlug,
                title: "Only identity fields matter here", subtitle: nil,
                audioURL: field == 3 ? URL(string: "https://example.invalid/other.mp3") : offered.audioURL,
                productionSourceURL: field == 4 ? URL(string: "https://example.invalid/source.mp3") : offered.productionSourceURL,
                duration: nil, artworkURL: nil, hosts: [], publishedDate: nil,
                isAINarration: field == 5 ? !offered.isAINarration : offered.isAINarration,
                sourceContentRevision: field == 6 ? "r2" : offered.sourceContentRevision)
        }
        for field in 0..<7 {
            XCTAssertFalse(ArticleListenAction.perform(offered: offered,
                resolve: { changed(field) }, play: { _ in XCTFail("Changed field \(field) played") }))
        }
    }

}
