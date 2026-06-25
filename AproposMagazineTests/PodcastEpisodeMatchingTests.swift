import XCTest
@testable import Apropos_Magazine

/// Regression coverage for `PodcastRepository.bestMatch`. Several distinct
/// articles previously resolved to the same generic episode (the "three
/// Heartland Festival 2026 episodes show the same title" bug). These tests pin
/// down the ranking: id > slug > exact title > loose contains.
final class PodcastEpisodeMatchingTests: XCTestCase {

    private func makeEpisode(
        id: String,
        articleId: String? = nil,
        articleSlug: String? = nil,
        title: String,
        audio: String? = "https://cdn.example.com/\(UUID().uuidString).mp3",
        isAINarration: Bool = false
    ) -> PodcastEpisode {
        PodcastEpisode(
            id: id,
            articleId: articleId,
            articleSlug: articleSlug,
            title: title,
            subtitle: nil,
            audioURL: audio.flatMap(URL.init(string:)),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: [],
            publishedDate: nil,
            isAINarration: isAINarration
        )
    }

    private func makeArticle(id: String, name: String, slug: String) -> Article {
        Article(id: id, name: name, slug: slug, content: "", intro: "", topicID: "topic")
    }

    // MARK: - Ranking

    func testIdMatchBeatsLooseTitleMatch() {
        let article = makeArticle(id: "art-1", name: "LP på Heartland Festival 2026", slug: "lp-heartland")
        let episodes = [
            makeEpisode(id: "generic", title: "Heartland Festival 2026"),
            makeEpisode(id: "exact", articleId: "art-1", title: "LP på Heartland Festival 2026"),
        ]

        let match = PodcastRepository.bestMatch(in: episodes, for: article, requirePlayableAudio: true)
        XCTAssertEqual(match?.id, "exact")
    }

    func testSlugMatchBeatsTitleMatch() {
        let article = makeArticle(id: "art-2", name: "Some Title", slug: "unique-slug")
        let episodes = [
            makeEpisode(id: "title-only", title: "Some Title"),
            makeEpisode(id: "slug", articleSlug: "unique-slug", title: "Different Title"),
        ]

        let match = PodcastRepository.bestMatch(in: episodes, for: article, requirePlayableAudio: true)
        XCTAssertEqual(match?.id, "slug")
    }

    func testDistinctArticlesDoNotShareGenericEpisode() {
        // The core regression: two different articles, each with their own
        // dedicated episode, must not both resolve to a generic episode whose
        // title is a substring of theirs.
        let lp = makeArticle(id: "lp", name: "LP på Heartland Festival 2026", slug: "lp")
        let minds = makeArticle(id: "minds", name: "The Minds of 99 på Heartland 2026", slug: "minds")

        let episodes = [
            makeEpisode(id: "generic", title: "Heartland"),
            makeEpisode(id: "lp-ep", articleId: "lp", title: "LP på Heartland Festival 2026"),
            makeEpisode(id: "minds-ep", articleId: "minds", title: "The Minds of 99 på Heartland 2026"),
        ]

        XCTAssertEqual(PodcastRepository.bestMatch(in: episodes, for: lp, requirePlayableAudio: true)?.id, "lp-ep")
        XCTAssertEqual(PodcastRepository.bestMatch(in: episodes, for: minds, requirePlayableAudio: true)?.id, "minds-ep")
    }

    // MARK: - Playable-audio gating

    func testRequirePlayableAudioSkipsEpisodesWithoutAudio() {
        let article = makeArticle(id: "art-3", name: "No Audio Yet", slug: "no-audio")
        let pending = makeEpisode(id: "pending", articleId: "art-3", title: "No Audio Yet", audio: nil)

        XCTAssertNil(PodcastRepository.bestMatch(in: [pending], for: article, requirePlayableAudio: true))
        XCTAssertEqual(
            PodcastRepository.bestMatch(in: [pending], for: article, requirePlayableAudio: false)?.id,
            "pending"
        )
    }

    // MARK: - AI narration preference

    func testHumanPodcastPreferredOverAINarrationAtSameRank() {
        let article = makeArticle(id: "art-4", name: "Dual Coverage", slug: "dual")
        let episodes = [
            makeEpisode(id: "ai", articleId: "art-4", title: "Dual Coverage", isAINarration: true),
            makeEpisode(id: "human", articleId: "art-4", title: "Dual Coverage", isAINarration: false),
        ]

        let match = PodcastRepository.bestMatch(in: episodes, for: article, requirePlayableAudio: true)
        XCTAssertEqual(match?.id, "human")
    }

    func testNoMatchReturnsNil() {
        let article = makeArticle(id: "art-5", name: "Completely Unrelated", slug: "unrelated")
        let episodes = [makeEpisode(id: "other", articleId: "zzz", articleSlug: "zzz", title: "Nothing Alike")]

        XCTAssertNil(PodcastRepository.bestMatch(in: episodes, for: article, requirePlayableAudio: true))
    }
}
