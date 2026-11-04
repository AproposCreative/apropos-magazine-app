import XCTest
@testable import Apropos

final class PodcastResumeSelectionTests: XCTestCase {
    @MainActor
    private func makeStore() -> PodcastPlaybackProgressStore {
        var records: [String: Data] = [:]
        let store = PodcastPlaybackProgressStore(storage: .init(read: { records[$0.storageKey] }, write: { records[$0.storageKey] = $1 }))
        store.changeContext(to: .guest)
        return store
    }
    private func episode(id: String = "episode", articleID: String? = "article", audio: String? = "https://example.invalid/test.mp3") -> PodcastEpisode {
        PodcastEpisode(id: id, articleId: articleID, articleSlug: "article-slug", title: "Artikel",
            subtitle: nil, audioURL: audio.flatMap(URL.init(string:)), productionSourceURL: nil,
            duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
    }
    private func article(id: String = "article") -> Article {
        Article(id: id, name: "Artikel", slug: "article-slug", content: "", intro: "", topicID: "topic")
    }

    @MainActor
    func testSelectionUsesActualOwnerSnapshotAndDisappearsImmediatelyForAnotherAccount() throws {
        let store = makeStore()
        let session = try XCTUnwrap(store.beginSession(episodeID: "episode", articleID: "article"))
        store.save(session.ticket, seconds: 42, duration: 600)
        XCTAssertEqual(PodcastResumeSelection.pair(episodes: [episode()], articles: [article()], progress: store.snapshot)?.article.id, "article")
        store.changeContext(to: .confirmed(userID: "account-b"))
        XCTAssertNil(PodcastResumeSelection.pair(episodes: [episode()], articles: [article()], progress: store.snapshot))
        store.changeContext(to: .guest)
        XCTAssertEqual(store.snapshot.position(for: "episode"), 42)
    }

    @MainActor
    func testStoredArticleCannotSelectUnrelatedEpisodeOrFallBackToDifferentArticle() throws {
        let store = makeStore()
        let session = try XCTUnwrap(store.beginSession(episodeID: "episode", articleID: "other"))
        store.save(session.ticket, seconds: 42, duration: 600)
        XCTAssertNil(PodcastResumeSelection.pair(episodes: [episode()], articles: [article(), article(id: "other")], progress: store.snapshot))
    }

    @MainActor
    func testMissingUnavailableOrAmbiguousCandidatesCannotProduceContinueBanner() throws {
        let store = makeStore()
        let session = try XCTUnwrap(store.beginSession(episodeID: "episode", articleID: "article"))
        store.save(session.ticket, seconds: 42, duration: 600)
        XCTAssertNil(PodcastResumeSelection.pair(episodes: [episode()], articles: [], progress: store.snapshot))
        XCTAssertNil(PodcastResumeSelection.pair(episodes: [episode(audio: nil)], articles: [article()], progress: store.snapshot))
        XCTAssertNil(PodcastResumeSelection.pair(episodes: [episode(), episode()], articles: [article()], progress: store.snapshot))
    }

    @MainActor
    func testEpisodeIdentityCanResolveArticleWhenPlaybackHadNoOverride() throws {
        let store = makeStore()
        let session = try XCTUnwrap(store.beginSession(episodeID: "episode", articleID: nil))
        store.save(session.ticket, seconds: 42, duration: 600)
        XCTAssertEqual(PodcastResumeSelection.pair(episodes: [episode()], articles: [article()], progress: store.snapshot)?.episode.id, "episode")
        store.complete(session.ticket)
        XCTAssertNil(PodcastResumeSelection.pair(episodes: [episode()], articles: [article()], progress: store.snapshot))
    }
}
