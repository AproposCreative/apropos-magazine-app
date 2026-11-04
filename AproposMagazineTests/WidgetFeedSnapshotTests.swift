import XCTest
@testable import Apropos

final class WidgetFeedSnapshotTests: XCTestCase {
    private func article(
        _ id: String, name: String? = nil, created: String? = "2026-10-01T12:00:00Z",
        date: String? = nil, topic: String = "music", draft: Bool = false
    ) -> Article {
        Article(
            id: id, name: name ?? id, slug: id, content: "<p>Body</p>", intro: "Intro",
            stjerne: 4, topicID: topic, topicsIDs: ["fallback"],
            mobileImageURL: URL(string: "https://example.invalid/\(id).jpg"),
            isDraft: draft, date: date, createdOn: created,
            lastPublished: "2026-10-02T12:00:00Z"
        )
    }

    func testSortedFeedUsesOnlyFiveRowsWithoutParsingDates() throws {
        let source = WidgetFeedSource(
            articles: (0..<10).map { article("id-\($0)") },
            topics: [Topic(id: "music", name: "Musik")], articlesAreSorted: true
        )
        var dateReads = 0
        let result = try WidgetFeedSnapshot(source: source, dateProvider: { article in
            dateReads += 1
            return article.feedSortDate
        })
        XCTAssertEqual(source.entries.count, 5)
        XCTAssertEqual(result.articles.map(\.id), (0..<5).map { "id-\($0)" })
        XCTAssertEqual(dateReads, 0)
        XCTAssertEqual(result.articles.first?.topic, "Musik")
        XCTAssertEqual(result.articles.first?.stjerne, 4)
        XCTAssertEqual(result.articles.first?.thumbURL, "https://example.invalid/id-0.jpg")
    }

    func testSourceIgnoresBodiesAndChangesOutsideSortedTopFive() {
        let input = (0..<7).map { article("id-\($0)") }
        let first = WidgetFeedSource(articles: input, topics: [], articlesAreSorted: true)
        var updated = input
        updated[0] = updated[0].replacingBodyContent("Different large body")
        updated[6] = article("new-below-top-five")
        XCTAssertEqual(first, WidgetFeedSource(articles: updated, topics: [], articlesAreSorted: true))
    }

    func testWidgetMetadataAndTopicNamesInvalidateTheSource() {
        let input = [article("a")]
        let first = WidgetFeedSource(articles: input, topics: [Topic(id: "music", name: "Old")])
        XCTAssertNotEqual(first, WidgetFeedSource(
            articles: input, topics: [Topic(id: "music", name: "New")]
        ))
        XCTAssertNotEqual(first, WidgetFeedSource(
            articles: [article("a", name: "Renamed")], topics: [Topic(id: "music", name: "Old")]
        ))
    }

    func testUnsortedPayloadMatchesCreatedFirstOrderAndParsesEachDateOnce() throws {
        let input = [
            article("a", created: "2026-10-01T12:00:00Z"),
            article("b", created: "2026-10-02T12:00:00Z"),
            article("c", created: "2026-10-02T12:00:00Z", date: "2026-10-04"),
            article("d", created: "2026-10-02T12:00:00Z"),
            article("e", created: "2026-10-03T12:00:00Z"),
            article("f", created: "2026-10-03T12:00:00Z")
        ]
        var dateReads = 0
        let result = try WidgetFeedSnapshot(
            source: WidgetFeedSource(articles: input, topics: []),
            dateProvider: { article in dateReads += 1; return article.feedSortDate }
        )
        XCTAssertEqual(result.articles.map(\.id), Array(Article.sortedByCreatedNewestFirst(input).prefix(5)).map(\.id))
        XCTAssertEqual(dateReads, input.count)
    }

    func testMetadataRefreshReusesDatesAndOnlyChangedDateIsParsedAgain() throws {
        var reads = 0
        let provider: (Article) -> Date = { article in reads += 1; return article.feedSortDate }
        let first = try WidgetFeedSnapshot(
            source: WidgetFeedSource(articles: [article("a"), article("b")], topics: []),
            dateProvider: provider
        )
        let renamed = try WidgetFeedSnapshot(
            source: WidgetFeedSource(articles: [article("a", name: "New"), article("b")], topics: []),
            reusing: first, dateProvider: provider
        )
        XCTAssertEqual(reads, 2)
        _ = try WidgetFeedSnapshot(
            source: WidgetFeedSource(articles: [article("a", date: "2026-11-01"), article("b")], topics: []),
            reusing: renamed, dateProvider: provider
        )
        XCTAssertEqual(reads, 3)
    }

    func testDuplicateAndDraftArticlesCannotOccupyWidgetRows() throws {
        let source = WidgetFeedSource(
            articles: [article("draft", draft: true), article("a"), article("a"), article("b", topic: "missing")],
            topics: [Topic(id: "fallback", name: "Kultur")], articlesAreSorted: true
        )
        let result = try WidgetFeedSnapshot(source: source)
        XCTAssertEqual(result.articles.map(\.id), ["a", "b"])
        XCTAssertEqual(result.articles.last?.topic, "Kultur")
    }
}
