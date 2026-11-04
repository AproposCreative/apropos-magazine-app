import XCTest
@testable import Apropos

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

extension PodcastEpisodeMatchingTests {
    func testConflictingCanonicalIDCannotMatchRecycledSlugOrSameTitle() {
        let article = makeArticle(id: "new-owner", name: "Same title", slug: "recycled")
        let wrong = makeEpisode(id: "wrong", articleId: "old-owner", articleSlug: "recycled", title: "Same title")
        XCTAssertNil(PodcastRepository.bestMatch(in: [wrong], for: article, requirePlayableAudio: true))
    }

    func testExplicitDifferentSlugCannotFallBackToSharedTitle() {
        let article = makeArticle(id: "article", name: "Same title", slug: "correct-story")
        let wrong = makeEpisode(id: "wrong", articleSlug: "different-story", title: "Same title")
        XCTAssertNil(PodcastRepository.bestMatch(in: [wrong], for: article, requirePlayableAudio: true))
    }

    private func languageArticle(_ language: ArticleContentLanguage) -> Article {
        let source = "6ae1f9da0e01d3d2ff34859f"
        return Article(id: language == .danish ? source : "en_" + source, name: "Shared title",
            slug: "shared-slug", content: "", intro: "", topicID: "topic",
            contentLanguage: language, sourceArticleID: source, cmsLocaleId: language.cmsLocaleID)
    }

    func testEnglishRepositoryAdmissionNeedsExactExplicitIDForAudioAndMetadata() {
        let english = languageArticle(.english), danish = languageArticle(.danish)
        let borrowed = [
            makeEpisode(id: "da-bound", articleId: danish.id, articleSlug: "shared-slug", title: "Shared title"),
            makeEpisode(id: "legacy-slug", articleSlug: "shared-slug", title: "Shared title"),
            makeEpisode(id: "legacy-title", title: "Shared title"),
            makeEpisode(id: "loose-title", title: "Shared"),
            makeEpisode(id: "padded-en", articleId: " " + english.id + " ", title: "Shared title"),
            makeEpisode(id: "upper-en", articleId: english.id.uppercased(), title: "Shared title")
        ]
        for playable in [false, true] {
            XCTAssertNil(PodcastRepository.bestMatch(in: borrowed, for: english, requirePlayableAudio: playable))
            let own = makeEpisode(id: "english-bound", articleId: english.id, articleSlug: "shared-slug", title: "English audio")
            XCTAssertEqual(PodcastRepository.bestMatch(in: borrowed + [own], for: english,
                requirePlayableAudio: playable)?.id, own.id)
        }
        let invalid = Article(id: english.id, name: "Invalid identity", slug: "shared-slug", content: "", intro: "", topicID: "",
            contentLanguage: .english)
        XCTAssertNil(PodcastRepository.bestMatch(in: [makeEpisode(id: "fake", articleId: english.id, title: "Invalid identity")],
            for: invalid, requirePlayableAudio: true))
    }

    func testDisplayCanonicalIDWinsAcrossMixedCatalogOrdersWithoutSlugFallback() {
        let english = languageArticle(.english), danish = languageArticle(.danish)
        let daEpisode = makeEpisode(id: "da", articleId: danish.id, articleSlug: "shared-slug", title: "Shared title")
        let enEpisode = makeEpisode(id: "en", articleId: english.id, articleSlug: "shared-slug", title: "Shared title")
        let wrong = makeEpisode(id: "wrong", articleId: "not-this-story", articleSlug: "shared-slug", title: "Shared title")
        for articles in [[english, danish], [danish, english]] {
            XCTAssertEqual(PodcastEpisode.matchingArticle(for: daEpisode, in: articles)?.id, danish.id)
            XCTAssertEqual(PodcastEpisode.matchingArticle(for: enEpisode, in: articles)?.id, english.id)
            XCTAssertNil(PodcastEpisode.matchingArticle(for: wrong, in: articles))
        }
        XCTAssertNil(PodcastEpisode.matchingArticle(for: daEpisode, in: [english]))
        XCTAssertNil(PodcastEpisode.matchingArticle(for: enEpisode, in: [danish]))
        let paddedEN = makeEpisode(id: "padded", articleId: " " + english.id + " ", articleSlug: "shared-slug", title: "Shared title")
        XCTAssertNil(PodcastEpisode.matchingArticle(for: paddedEN, in: [english, danish]))
    }

    func testLegacyDisplaySlugFallbackRequiresOneDanishIdentity() {
        let english = languageArticle(.english), danish = languageArticle(.danish)
        let legacy = makeEpisode(id: "legacy", articleSlug: " SHARED-SLUG ", title: "Shared title")
        for articles in [[english, danish], [danish, english]] {
            XCTAssertEqual(PodcastEpisode.matchingArticle(for: legacy, in: articles)?.id, danish.id)
        }
        XCTAssertNil(PodcastEpisode.matchingArticle(for: legacy, in: [english]))
        let duplicateSlug = makeArticle(id: "another-da-story", name: "Different article", slug: "shared-slug")
        XCTAssertNil(PodcastEpisode.matchingArticle(for: legacy, in: [english, danish, duplicateSlug]))
        // Preserve existing Danish ranking/streaming compatibility for ID-less audio.
        XCTAssertEqual(PodcastRepository.bestMatch(in: [legacy], for: danish, requirePlayableAudio: true)?.id, legacy.id)
        let titleOnly = makeEpisode(id: "title", title: "Shared title")
        XCTAssertEqual(PodcastRepository.bestMatch(in: [titleOnly], for: danish, requirePlayableAudio: true)?.id, titleOnly.id)
    }
}
