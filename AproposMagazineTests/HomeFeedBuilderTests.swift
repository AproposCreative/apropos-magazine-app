import XCTest
@testable import Apropos

final class HomeFeedBuilderTests: XCTestCase {
    func testEnglishHomeAudioNeedsExplicitEditionIDDespiteSharedSlug() {
        let raw = "0123456789abcdef01234567"
        let english = Article(id: "en_" + raw, name: "Shared story", slug: "shared", content: "", intro: "",
            topicID: "music", contentLanguage: .english, sourceArticleID: raw,
            cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        var legacy = HomePodcastIndex(episodes: [episode("legacy", slug: "shared", title: "Shared story")])
        XCTAssertNil(legacy.bestMatch(for: english))
        var danish = HomePodcastIndex(episodes: [episode("danish", article: raw, slug: "shared")])
        XCTAssertNil(danish.bestMatch(for: english))
        var explicit = HomePodcastIndex(episodes: [episode("english", article: english.id, slug: "shared")])
        XCTAssertEqual(explicit.bestMatch(for: english)?.id, "english")
        for bound in [" " + english.id + " ", english.id.uppercased()] {
            var malformed = HomePodcastIndex(episodes: [episode("wrong", article: bound, slug: "shared")])
            XCTAssertNil(malformed.bestMatch(for: english))
        }
    }

    func testEnglishHomeResumeNeverBorrowsLegacyEpisodeWithSharedSlug() {
        let raw = "0123456789abcdef01234567"
        let english = Article(id: "en_" + raw, name: "English story", slug: "shared", content: "", intro: "",
            topicID: "music", isDraft: false, lastPublished: "2026-10-30T00:00:00Z",
            contentLanguage: .english, sourceArticleID: raw, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        for bound in [nil, raw, " " + english.id + " ", english.id.uppercased()] {
            let value = episode("legacy", article: bound, slug: "shared")
            let result = HomeFeedBuilder().build(input([english], episodes: [value]))
            XCTAssertNil(result.resumeIndex.pair(episodeID: value.id, articleID: nil, hasResumableProgress: true))
            XCTAssertNil(result.resumeIndex.pair(episodeID: value.id, articleID: english.id, hasResumableProgress: true))
        }
        let valid = episode("english", article: english.id, slug: "shared")
        let result = HomeFeedBuilder().build(input([english], episodes: [valid]))
        XCTAssertEqual(result.resumeIndex.pair(episodeID: valid.id, articleID: english.id,
            hasResumableProgress: true)?.article.id, english.id)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func article(_ id: String, day: Int = 1, topic: String = "other", name: String? = nil,
                         slug: String? = nil, content: String = "", revision: String = "r1",
                         editorial: String? = nil, section: String? = nil, author: String? = nil,
                         mobile: URL? = nil, thumb: URL? = nil, cover: URL? = nil,
                         draft: Bool = false, archived: Bool = false) -> Article {
        Article(id: id, name: name ?? id, slug: slug ?? id, content: content, intro: "Intro", topicID: topic,
            sectionID: section, authorID: author, mobileImageURL: mobile, thumbURL: thumb, coverURL: cover,
            isDraft: draft, isArchived: archived, date: editorial,
            createdOn: String(format: "2026-01-%02dT10:00:00.000Z", day),
            lastPublished: "2026-01-01T10:00:00Z", contentRevision: revision)
    }
    private func episode(_ id: String, article: String? = nil, slug: String? = nil, title: String = "Story",
                         ai: Bool = false, playable: Bool = true) -> PodcastEpisode {
        PodcastEpisode(id: id, articleId: article, articleSlug: slug, title: title, subtitle: nil,
            audioURL: playable ? URL(string: "https://example.invalid/\(id).mp3") : nil,
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [" Host "], publishedDate: nil,
            isAINarration: ai, sourceContentRevision: "r1")
    }
    private func input(_ articles: [Article], topics: [Topic] = [], sections: [WebflowSection] = [],
                       authors: [Author] = [], episodes: [PodcastEpisode] = [], recommendations: [HomeRecommendation] = [],
                       authority: HomeFeedAuthority = .init(), now: Date? = nil) -> HomeFeedInput {
        HomeFeedInput(authority: authority, articles: articles, topics: topics, sections: sections,
            authors: authors, episodes: episodes, recommendations: recommendations, now: now ?? self.now)
    }
    func testEmptyInputIsAnHonestEmptySnapshot() {
        let result = HomeFeedBuilder().build(input([]))
        XCTAssertTrue(result.hero.isEmpty); XCTAssertEqual(result.rails.count, 6)
        XCTAssertTrue(result.rails.allSatisfy { $0.visible.isEmpty && $0.all.isEmpty })
        XCTAssertTrue(result.podcastPairs.isEmpty); XCTAssertNil(result.nextBoundary)
    }
    func testDraftArchiveAndInvalidOrDuplicateIDsAreExcludedDeterministically() {
        let result = HomeFeedBuilder().build(input([article("a"), article("a", day: 2), article("b", draft: true),
            article("c", archived: true), article(""), article("x/y"), article("__reserved__")]))
        XCTAssertEqual(result.hero.map(\.id), ["a"]); XCTAssertEqual(result.hero.first?.createdOn, article("a").createdOn)
    }
    func testCreatedOrderingAndHeroLimitMatchActualArticleOrdering() {
        let values = (1...15).map { article("a\($0)", day: $0) }.reversed()
        let result = HomeFeedBuilder().build(input(Array(values)))
        XCTAssertEqual(result.hero.map(\.id), Article.sortedByCreatedNewestFirst(Array(values)).prefix(5).map(\.id))
        XCTAssertEqual(result.hero.count, 5)
    }
    func testHeroUsesCreatedDateWhileRecentUsesLaterEditorialDate() {
        let value = article("a", editorial: "1. januar 2030")
        let result = HomeFeedBuilder().build(input([value]))
        XCTAssertEqual(result.hero.map(\.id), ["a"]); XCTAssertTrue(result.rail(.recommended).all.isEmpty)
        XCTAssertGreaterThan(result.nextBoundary ?? .distantPast, now)
    }
    func testFutureHeroAppearsExactlyAtItsBoundary() throws {
        let future = article("future", day: 20)
        let parser = ArticlePresentationDateParser(); let boundary = try XCTUnwrap(parser.dates(for: future).created)
        let builder = HomeFeedBuilder()
        let before = builder.build(input([future], now: boundary.addingTimeInterval(-0.001)))
        XCTAssertTrue(before.hero.isEmpty); XCTAssertEqual(before.nextBoundary, boundary)
        let after = builder.build(input([future], now: boundary))
        XCTAssertEqual(after.hero.map(\.id), ["future"]); XCTAssertNil(after.nextBoundary)
        XCTAssertEqual(after.metrics.archiveSorts, before.metrics.archiveSorts)
    }
    func testReviewReservationUsesInputPrefixBeforeSortedVisibleSelection() {
        let values = (1...20).map { article("a\($0)", day: $0, topic: "review") }
        let result = HomeFeedBuilder().build(input(values, topics: [Topic(id: "review", name: "Anmeldelser")]))
        XCTAssertEqual(result.rail(.reviews).visible.map(\.id), (6...15).reversed().map { "a\($0)" })
        XCTAssertEqual(result.rail(.popular).all.map(\.id), (11...15).reversed().map { "a\($0)" })
        XCTAssertEqual(result.rail(.reviews).all.count, 15)
    }
    func testAbsentReviewTopicPreservesNilMainTopicFallback() throws {
        let values = try (1...8).map { day -> Article in
            let data = Data("{\"id\":\"a\(day)\",\"createdOn\":\"2026-01-\(String(format: "%02d", day))T10:00:00Z\",\"lastPublished\":\"2026-01-01T10:00:00Z\",\"fieldData\":{\"name\":\"A\",\"slug\":\"a\"}}".utf8)
            return try JSONDecoder().decode(Article.self, from: data)
        }
        let result = HomeFeedBuilder().build(input(values, topics: [Topic(id: "music", name: "Musik")]))
        XCTAssertEqual(result.rail(.reviews).all.map(\.id), ["a3", "a2", "a1"])
        XCTAssertTrue(result.rail(.popular).all.isEmpty)
    }
    func testNoTopicsDoesNotInventReviews() {
        let result = HomeFeedBuilder().build(input((1...8).map { article("a\($0)", day: $0, topic: "review") }))
        XCTAssertTrue(result.rail(.reviews).all.isEmpty); XCTAssertEqual(result.rail(.popular).all.count, 3)
    }
    func testSectionRailUsesTopicHeuristicWhileHeroTagPrefersDirectSection() {
        let values = (1...8).map { article("a\($0)", day: $0, topic: "music", section: "culture") }
        let result = HomeFeedBuilder().build(input(values, topics: [Topic(id: "music", name: "Koncerter")],
            sections: [WebflowSection(id: "music", name: "Musik"), WebflowSection(id: "culture", name: "Kultur")]))
        XCTAssertEqual(result.rail(.music).all.count, 8); XCTAssertTrue(result.rail(.culture).all.isEmpty)
        XCTAssertEqual(result.metadataByID["a8"]?.heroTag, "Kultur")
    }
    func testRecentPrefixBeforeExclusionDoesNotFillToTen() {
        let values = (1...20).map { article("a\($0)", day: $0) }
        let result = HomeFeedBuilder().build(input(values))
        XCTAssertEqual(result.rail(.recommended).visible.map(\.id), (11...15).reversed().map { "a\($0)" })
        XCTAssertEqual(result.rail(.recommended).all.count, 15)
    }
    func testPersonalReasonsFollowUniqueAcceptedIDsAndAllRouteRemainsEditorial() {
        let values = (1...8).map { article("a\($0)", day: $0) }
        let result = HomeFeedBuilder().build(input(values, recommendations: [.init(articleID: "a1", reason: "First"),
            .init(articleID: "a1", reason: "Duplicate"), .init(articleID: "missing", reason: "Hidden")]))
        XCTAssertEqual(result.rail(.recommended).visible.map(\.id), ["a1"])
        XCTAssertEqual(result.rail(.recommended).reasonsByID, ["a1": "First"])
        XCTAssertEqual(result.rail(.recommended).all.map(\.id), ["a3", "a2", "a1"])
    }
    func testFuturePublicArticlesRemainEligibleOutsideHeroAndRecent() throws {
        let future = article("future", day: 20)
        let date = try XCTUnwrap(ArticlePresentationDateParser().dates(for: future).created)
        let result = HomeFeedBuilder().build(input([future], now: date.addingTimeInterval(-1)))
        XCTAssertTrue(result.hero.isEmpty); XCTAssertEqual(result.rail(.popular).visible.map(\.id), ["future"])
    }
    func testFirstNormalizedAuthorIDOrNameWinsAcrossBothLookupKinds() {
        let authors = [Author(id: "first", name: " Shared ", bio: nil, imageURL: nil, position: "", photoURL: ""),
            Author(id: "shared", name: "Second", bio: nil, imageURL: nil, position: "", photoURL: "")]
        let result = HomeFeedBuilder().build(input([article("a", author: " SHARED ")], authors: authors))
        XCTAssertEqual(result.metadataByID["a"]?.authorName, " Shared ")
    }
    func testHeroImageOrderDeduplicatesAndCardKeepsMobilePriority() {
        let thumb = URL(string: "https://example.invalid/thumb.jpg")!, mobile = URL(string: "https://example.invalid/mobile.jpg")!
        let result = HomeFeedBuilder().build(input([article("a", mobile: mobile, thumb: thumb, cover: thumb)]))
        XCTAssertEqual(result.metadataByID["a"]?.heroImageCandidates, [thumb, mobile])
        XCTAssertEqual(result.metadataByID["a"]?.cardImageURL, mobile)
    }
    func testHTMLFallbackIsPreparedAndAVisibleChangeRebuildsMetadataOnly() {
        let builder = HomeFeedBuilder()
        let before = builder.build(input([article("a", content: "<img src='https://example.invalid/one.jpg'>")]))
        let after = builder.build(input([article("a", content: "<p>Changed</p><img src='https://example.invalid/two.jpg'>")]))
        XCTAssertEqual(after.metadataByID["a"]?.listImageURL?.lastPathComponent, "two.jpg")
        XCTAssertGreaterThan(after.metrics.metadataBuilds, before.metrics.metadataBuilds)
        XCTAssertEqual(after.metrics.archiveSorts, before.metrics.archiveSorts)
        XCTAssertEqual(after.metrics.podcastCandidateChecks, before.metrics.podcastCandidateChecks)
    }
    func testInvisibleBodyAndEmbeddedAuthorChangesRebindWithoutArchiveWork() {
        let builder = HomeFeedBuilder(), image = URL(string: "https://example.invalid/image.jpg")!
        let first = article("a", content: "Before", mobile: image)
        let before = builder.build(input([first]))
        var changed = article("a", content: "After", mobile: image)
        changed.author = Author(id: "author", name: "Embedded", bio: "Updated detail", imageURL: nil, position: "", photoURL: "")
        let after = builder.build(input([changed]))
        XCTAssertEqual(after.hero.first?.content, "After"); XCTAssertEqual(after.hero.first?.author?.name, "Embedded")
        XCTAssertEqual(after.metrics.archiveSorts, before.metrics.archiveSorts)
        XCTAssertEqual(after.metrics.metadataBuilds, before.metrics.metadataBuilds)
        XCTAssertEqual(after.metrics.podcastCandidateChecks, before.metrics.podcastCandidateChecks)
    }
    func testIndexedMatcherPreservesEveryTierAndManifestTieAgainstActualRepository() {
        let target = article("a", name: "Exact Story", slug: "exact-slug")
        let cases: [[PodcastEpisode]] = [[], [episode("wrong", article: "other", slug: "exact-slug", title: "Exact Story")],
            [episode("wrong-slug", slug: "other", title: "Exact Story")], [episode("loose", title: "Story")],
            [episode("ai", article: " a ", ai: true), episode("human", article: "a")],
            [episode("exact-title", title: " Exact Story "), episode("slug", slug: " EXACT-SLUG ")],
            [episode("pending", article: "a", playable: false), episode("ai", article: "a", ai: true)],
            [episode("first", title: "Story"), episode("second", title: "Story")]]
        for values in cases {
            for playable in [false, true] {
                var index = HomePodcastIndex(episodes: values)
                XCTAssertEqual(index.bestMatch(for: target, requirePlayableAudio: playable),
                    PodcastRepository.bestMatch(in: values, for: target, requirePlayableAudio: playable))
            }
        }
    }
    func testHumanPendingMayWinMetadataWhilePlayableAIWinsPlayback() {
        let target = article("a"), values = [episode("ai", article: "a", ai: true), episode("human", article: "a", playable: false)]
        var index = HomePodcastIndex(episodes: values)
        XCTAssertEqual(index.bestMatch(for: target)?.id, "human")
        XCTAssertEqual(index.bestMatch(for: target, requirePlayableAudio: true)?.id, "ai")
    }
    func testPreparedPodcastPrefixAndFullResumeIndexAreIndependent() {
        let values = (1...125).map { article("a\($0)", day: 1 + $0 % 28) }
        let episodes = values.map { episode("e-\($0.id)", article: $0.id) } + [episode("historical", article: "a1", ai: true)]
        let result = HomeFeedBuilder().build(input(values, episodes: episodes))
        XCTAssertEqual(result.podcastPairs.count, 100)
        XCTAssertEqual(result.resumeIndex.pair(episodeID: "historical", articleID: "a1", hasResumableProgress: true)?.episode.id, "historical")
        XCTAssertEqual(result.podcastPairs.prefix(2).count, 2)
    }
    func testDuplicatePlayableEpisodeIDRejectsResumeButPendingDuplicateDoesNot() {
        let target = article("a"), value = episode("e", article: "a")
        let ambiguous = HomeFeedBuilder().build(input([target], episodes: [value, value]))
        XCTAssertNil(ambiguous.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
        let unique = HomeFeedBuilder().build(input([target], episodes: [value, episode("e", article: "a", playable: false)]))
        XCTAssertNotNil(unique.resumeIndex.pair(episodeID: "e", articleID: "a", hasResumableProgress: true))
    }
    func testResumeExplicitCurrentArticleOverridesFallbackButStrictIdentityStillApplies() {
        let a = article("a", slug: "shared"), b = article("b", slug: "shared")
        let slugOnly = episode("e", slug: "shared")
        let result = HomeFeedBuilder().build(input([a, b], episodes: [slugOnly]))
        XCTAssertEqual(result.resumeIndex.pair(episodeID: "e", articleID: nil, hasResumableProgress: true)?.article.id, "a")
        XCTAssertEqual(result.resumeIndex.pair(episodeID: "e", articleID: "b", hasResumableProgress: true)?.article.id, "b")
        XCTAssertNil(result.resumeIndex.pair(episodeID: "e", articleID: "missing", hasResumableProgress: true))
        let mismatch = HomeFeedBuilder().build(input([a], episodes: [episode("bound", article: " b ", slug: "shared")]))
        XCTAssertNil(mismatch.resumeIndex.pair(episodeID: "bound", articleID: nil, hasResumableProgress: true))
    }
    func testAuthorMetadataChangeDoesNotReSortOrRematch() {
        let builder = HomeFeedBuilder(), a = article("a", author: "writer")
        let before = builder.build(input([a]))
        let after = builder.build(input([a], authors: [Author(id: "writer", name: "Writer", bio: nil, imageURL: nil, position: "", photoURL: "")]))
        XCTAssertEqual(after.metrics.archiveSorts, before.metrics.archiveSorts)
        XCTAssertEqual(after.metrics.podcastCandidateChecks, before.metrics.podcastCandidateChecks)
        XCTAssertEqual(after.metadataByID["a"]?.authorName, "Writer")
    }
    func testDateParserMatchesActualFormatsRawComparisonAndIgnoresBulkRepublish() {
        let parser = ArticlePresentationDateParser()
        let values = [article("a", editorial: "1. oktober 2026"), article("z", day: 2), article("b", day: 1)]
        XCTAssertEqual(parser.sortedByCreatedNewestFirst(values).map(\.id), Article.sortedByCreatedNewestFirst(values).map(\.id))
        for value in values { XCTAssertEqual(parser.dates(for: value).feed, value.feedSortDate) }
        let before = parser.dateParses; _ = parser.sortedByCreatedNewestFirst(values)
        XCTAssertEqual(parser.dateParses, before)
    }
    func testEmptyManifestIsAuthoritativeAfterNonemptyBuild() {
        let builder = HomeFeedBuilder(), a = article("a")
        XCTAssertFalse(builder.build(input([a], episodes: [episode("e", article: "a")])).podcastPairs.isEmpty)
        let empty = builder.build(input([a], episodes: []))
        XCTAssertTrue(empty.podcastPairs.isEmpty); XCTAssertTrue(empty.resumeIndex.playableEpisodesByID.isEmpty)
    }
    func testResumeFallbackPreservesActualFoundationCaseInsensitiveMatchingAndRawArticleID() {
        for (slug, episodeSlug) in [("Straße", "STRASSE"), ("ΟΣ", "ος"), (" Æ ", "æ")] {
            let target = article("a", slug: slug), value = episode("e", slug: episodeSlug)
            let result = HomeFeedBuilder().build(input([target], episodes: [value]))
            XCTAssertEqual(result.resumeIndex.pair(episodeID: "e", articleID: nil, hasResumableProgress: true)?.article,
                PodcastEpisode.matchingArticle(for: value, in: [target]))
        }
        let spaced = article(" a "), value = episode("e", article: "a")
        XCTAssertNil(PodcastEpisode.matchingArticle(for: value, in: [spaced]))
        let result = HomeFeedBuilder().build(input([spaced], episodes: [value]))
        XCTAssertNil(result.resumeIndex.pair(episodeID: "e", articleID: nil, hasResumableProgress: true))
    }
}
