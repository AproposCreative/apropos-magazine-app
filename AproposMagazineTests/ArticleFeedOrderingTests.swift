import XCTest
@testable import Apropos_Magazine

/// Regression coverage for the article feed ordering + publish gating. The feed
/// repeatedly mis-ordered after the createdOn/lastPublished changes (bulk CMS
/// republishes pushing old stories to the top), so these tests pin the rules.
final class ArticleFeedOrderingTests: XCTestCase {

    private func makeArticle(
        id: String,
        createdOn: String? = nil,
        lastPublished: String? = nil,
        isDraft: Bool = false,
        date: String? = nil
    ) -> Article {
        Article(
            id: id,
            name: "Article \(id)",
            slug: "article-\(id)",
            content: "",
            intro: "",
            topicID: "topic",
            isDraft: isDraft,
            date: date,
            createdOn: createdOn,
            lastPublished: lastPublished
        )
    }

    // MARK: - Ordering

    func testSortsByCreatedOnNewestFirst() {
        let older = makeArticle(id: "a", createdOn: "2026-01-01T10:00:00.000Z")
        let newer = makeArticle(id: "b", createdOn: "2026-06-01T10:00:00.000Z")
        let middle = makeArticle(id: "c", createdOn: "2026-03-01T10:00:00.000Z")

        let sorted = Article.sortedByCreatedNewestFirst([older, newer, middle])
        XCTAssertEqual(sorted.map(\.id), ["b", "c", "a"])
    }

    func testBulkRepublishDoesNotReorderByLastPublished() {
        // Both republished "today", but created months apart -> created wins.
        let today = "2026-06-25T09:00:00.000Z"
        let oldStory = makeArticle(id: "old", createdOn: "2026-01-01T10:00:00.000Z", lastPublished: today)
        let newStory = makeArticle(id: "new", createdOn: "2026-06-20T10:00:00.000Z", lastPublished: today)

        let sorted = Article.sortedByCreatedNewestFirst([oldStory, newStory])
        XCTAssertEqual(sorted.map(\.id), ["new", "old"])
    }

    func testStableTieBreakById() {
        let a = makeArticle(id: "a", createdOn: "2026-06-01T10:00:00.000Z")
        let b = makeArticle(id: "b", createdOn: "2026-06-01T10:00:00.000Z")

        // Identical createdOn -> deterministic order via id (descending).
        let sorted = Article.sortedByCreatedNewestFirst([a, b])
        XCTAssertEqual(sorted.map(\.id), ["b", "a"])
    }

    // MARK: - Publish gating

    func testDraftIsNotPubliclyPublished() {
        let draft = makeArticle(id: "d", lastPublished: "2026-06-01T10:00:00.000Z", isDraft: true)
        XCTAssertFalse(draft.isPubliclyPublished)
    }

    func testMissingLastPublishedIsNotPublished() {
        let unpublished = makeArticle(id: "u", lastPublished: nil)
        XCTAssertFalse(unpublished.isPubliclyPublished)
    }

    func testPublishedArticleIsPublic() {
        let published = makeArticle(id: "p", lastPublished: "2026-06-01T10:00:00.000Z", isDraft: false)
        XCTAssertTrue(published.isPubliclyPublished)
    }
}
