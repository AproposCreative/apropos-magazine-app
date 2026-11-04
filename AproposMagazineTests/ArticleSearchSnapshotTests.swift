import XCTest
@testable import Apropos

final class ArticleSearchSnapshotTests: XCTestCase {
    private func article(
        _ id: String, title: String = "Title", intro: String = "Intro",
        created: String? = "2026-01-01T12:00:00.000Z", date: String? = nil,
        topic: String = "music", authorID: String? = nil
    ) -> Article {
        Article(
            id: id, name: title, slug: id, content: "", intro: intro,
            topicID: topic, authorID: authorID, date: date, createdOn: created,
            lastPublished: "2030-01-01T12:00:00Z"
        )
    }

    func testDateSortKeepsEditorialFeedSemanticsAndIgnoresBulkRepublish() throws {
        let editorial = article("editorial", created: "2026-01-01T12:00:00Z", date: "2026-02-01")
        let created = article("created", created: "2026-01-15T12:00:00Z")
        let missing = article("missing", created: nil, date: "invalid")
        let index = try ArticleSearchIndex(articles: [created, missing, editorial], authors: [])
        XCTAssertEqual(try index.snapshot(query: "", sort: .newest).articles.map(\.id), ["editorial", "created", "missing"])
        XCTAssertEqual(try index.snapshot(query: "", sort: .oldest).articles.map(\.id), ["missing", "created", "editorial"])
    }

    func testTitleAndCategorySortsRetainOriginalComparisonRules() throws {
        let a = article("a", title: "Alpha", topic: "z-topic")
        let b = article("b", title: "Beta", topic: "a-topic")
        let c = article("c", title: "Zulu", topic: "m-topic")
        let index = try ArticleSearchIndex(articles: [c, a, b], authors: [])
        XCTAssertEqual(try index.snapshot(query: "", sort: .titleAZ).articles.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(try index.snapshot(query: "", sort: .titleZA).articles.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(try index.snapshot(query: "", sort: .category).articles.map(\.id), ["b", "c", "a"])
    }

    func testEqualKeysUseDeterministicIDOrderForEverySort() throws {
        let input = [article("c"), article("a"), article("b")]
        let index = try ArticleSearchIndex(articles: input, authors: [])
        for sort in ArticleSortOption.allCases {
            XCTAssertEqual(try index.snapshot(query: "", sort: sort).articles.map(\.id), ["a", "b", "c"])
        }
    }

    func testCaseInsensitiveTitleIntroAndMetadataAuthorSearch() throws {
        let metadata = Author(id: "writer", name: "Maja Hansen", bio: nil, imageURL: nil, position: "", photoURL: "")
        let input = [
            article("title", title: "HEARTLAND"),
            article("intro", intro: "En kulturfortælling"),
            article("author", authorID: "writer")
        ]
        let index = try ArticleSearchIndex(articles: input, authors: [metadata])
        XCTAssertEqual(try index.snapshot(query: "heartLAND", sort: .newest).articles.map(\.id), ["title"])
        XCTAssertEqual(try index.snapshot(query: "KULTUR", sort: .newest).articles.map(\.id), ["intro"])
        let authors = try index.snapshot(query: "MAJA", sort: .newest).articles
        XCTAssertEqual(authors.map(\.id), ["author"])
        XCTAssertEqual(authors.first?.author, metadata)
        XCTAssertEqual(authors.first?.content, "")
    }

    func testAuthorRevisionReplacesStaleEmbeddedAuthorWithoutParsingDatesAgain() throws {
        var input = article("a", authorID: "writer")
        input.author = Author(id: "writer", name: "Old Name", bio: nil, imageURL: nil, position: "", photoURL: "")
        var dateReads = 0
        let provider: (Article) -> Date = { article in
            dateReads += 1
            return article.feedSortDate
        }
        let first = try ArticleSearchIndex(articles: [input], authors: [], dateProvider: provider)
        let freshAuthor = Author(id: "writer", name: "New Name", bio: nil, imageURL: nil, position: "", photoURL: "")
        let updated = try ArticleSearchIndex(articles: [input], authors: [freshAuthor], reusing: first, dateProvider: provider)
        XCTAssertEqual(dateReads, 1)
        XCTAssertTrue(try updated.snapshot(query: "old name", sort: .newest).articles.isEmpty)
        XCTAssertEqual(try updated.snapshot(query: "new name", sort: .newest).articles.first?.id, "a")
    }

    func testBodyOnlyRevisionReusesDatesAndDateRevisionRecomputesAffectedKey() throws {
        let initial = [article("a"), article("b")]
        var dateReads = 0
        let provider: (Article) -> Date = { article in
            dateReads += 1
            return article.feedSortDate
        }
        let first = try ArticleSearchIndex(articles: initial, authors: [], dateProvider: provider)
        let bodies = [initial[0].replacingBodyContent("<p>New body</p>"), initial[1]]
        let updated = try ArticleSearchIndex(articles: bodies, authors: [], reusing: first, dateProvider: provider)
        XCTAssertEqual(dateReads, 2)
        _ = try updated.snapshot(query: "", sort: .oldest)
        _ = try updated.snapshot(query: "intro", sort: .newest)
        XCTAssertEqual(dateReads, 2)
        _ = try ArticleSearchIndex(
            articles: [article("a", date: "2026-03-01"), initial[1]],
            authors: [], reusing: updated, dateProvider: provider
        )
        XCTAssertEqual(dateReads, 3)
    }

    func testPaginationClampsInvalidAndOversizedCounts() {
        let snapshot = ArticleSearchSnapshot(articles: (0..<23).map { article("id-\($0)") })
        XCTAssertTrue(snapshot.page(visibleCount: -1).articles.isEmpty)
        let first = snapshot.page(visibleCount: 20)
        XCTAssertEqual(first.articles.count, 20)
        XCTAssertEqual(first.totalCount, 23)
        XCTAssertTrue(first.hasMore)
        let last = snapshot.page(visibleCount: Int.max)
        XCTAssertEqual(last.articles.count, 23)
        XCTAssertFalse(last.hasMore)
        XCTAssertFalse(ArticleSearchSnapshot.empty.page(visibleCount: 20).hasMore)
    }

    func testDuplicateInputIDsCannotBecomeDuplicateRows() throws {
        let index = try ArticleSearchIndex(articles: [article("a"), article("a"), article("b")], authors: [])
        XCTAssertEqual(try index.snapshot(query: "", sort: .newest).articles.map(\.id), ["a", "b"])
    }
}
