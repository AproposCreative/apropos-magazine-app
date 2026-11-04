import XCTest
@testable import Apropos

final class IncomingLinkResolutionPolicyTests: XCTestCase {
    private func article(_ id: String = "article", slug: String = "slug", revision: String = "r1", draft: Bool = false) -> Article {
        Article(id: id, name: "Title", slug: slug, content: "", intro: "", topicID: "topic", isDraft: draft,
                lastPublished: "2026-10-20T12:00:00Z", contentRevision: revision)
    }
    private func episode(_ id: String = "episode", articleID: String? = "article", slug: String? = "slug", ai: Bool = false, revision: String? = nil) -> PodcastEpisode {
        PodcastEpisode(id: id, articleId: articleID, articleSlug: slug, title: "Title", subtitle: nil,
            audioURL: URL(string: "https://media.example.com/audio.mp3"), productionSourceURL: nil, duration: nil,
            artworkURL: nil, hosts: [], publishedDate: nil, isAINarration: ai, sourceContentRevision: revision)
    }
    func testCanonicalArticleExactIDWinsOverOtherArticlesSlug() {
        let canonical = article(), collision = article("other", slug: "article")
        XCTAssertEqual(IncomingLinkResolutionPolicy.article(identifier: "article", in: [collision, canonical], permits: { _ in true })?.id, "article")
    }
    func testDuplicateSlugAndConflictingCachedRevisionsCannotSelectFirstArticle() {
        XCTAssertNil(IncomingLinkResolutionPolicy.article(identifier: "slug", in: [article(), article("other")], permits: { _ in true }))
        XCTAssertNil(IncomingLinkResolutionPolicy.article(identifier: "article", in: [article(), article(revision: "r2")], permits: { _ in true }))
        XCTAssertEqual(IncomingLinkResolutionPolicy.article(identifier: "slug", in: [article(), article()], permits: { _ in true })?.id, "article")
    }
    func testPartialOfflineCatalogNeverPromotesItsSingleSlugMatchToCanonicalIdentity() {
        let partial = [article("canonical-id", slug: "public-slug")]
        XCTAssertNil(IncomingLinkResolutionPolicy.offlineArticle(identifier: "public-slug", in: partial, permits: { _ in true }))
        XCTAssertEqual(IncomingLinkResolutionPolicy.offlineArticle(identifier: "canonical-id", in: partial, permits: { _ in true })?.id, "canonical-id")
        XCTAssertNil(IncomingLinkResolutionPolicy.offlineArticle(identifier: "missing-id", in: partial, permits: { _ in true }))
    }
    func testOfflineExactIDRejectsConflictingRevisionsWithdrawnAndDeniedSnapshots() {
        XCTAssertNil(IncomingLinkResolutionPolicy.offlineArticle(identifier: "article", in: [article(), article(revision: "r2")], permits: { _ in true }))
        XCTAssertNil(IncomingLinkResolutionPolicy.offlineArticle(identifier: "article", in: [article(draft: true)], permits: { _ in true }))
        XCTAssertNil(IncomingLinkResolutionPolicy.offlineArticle(identifier: "article", in: [article()], permits: { _ in false }))
        XCTAssertEqual(IncomingLinkResolutionPolicy.offlineArticle(identifier: "article", in: [article(), article()], permits: { _ in true })?.id, "article")
    }
    func testUnpublishedAndDeniedArticleCannotAuthorizeResolution() {
        XCTAssertNil(IncomingLinkResolutionPolicy.article(identifier: "article", in: [article(draft: true)], permits: { _ in true }))
        XCTAssertNil(IncomingLinkResolutionPolicy.article(identifier: "article", in: [article()], permits: { _ in false }))
    }
    func testRawTitleOnlyEpisodeAndConflictingOriginalIDOrSlugNeverBecomeAuthority() {
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(articleID: nil, slug: nil)]))
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(articleID: "other")]))
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(slug: "other")]))
        XCTAssertEqual(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(articleID: nil)])?.id, "episode")
    }
    func testUniqueHumanPreferenceAndAmbiguityDoNotDependOnArrayOrder() {
        let human = episode("human"), ai = episode("ai", ai: true, revision: "r1")
        XCTAssertEqual(IncomingLinkResolutionPolicy.episode(for: article(), in: [ai, human])?.id, "human")
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [human, episode("another-human")]))
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [ai, episode("ai2", ai: true, revision: "r1")]))
    }
    func testNarrationRequiresOriginalExactSourceRevisionAndPublishedArticle() {
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(ai: true)]))
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(ai: true, revision: "old")]))
        XCTAssertEqual(IncomingLinkResolutionPolicy.episode(for: article(), in: [episode(ai: true, revision: "r1")])?.id, "episode")
        XCTAssertNil(IncomingLinkResolutionPolicy.episode(for: article(draft: true), in: [episode()]))
    }
}
