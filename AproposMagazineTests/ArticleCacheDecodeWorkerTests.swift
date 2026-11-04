import XCTest
@testable import Apropos

final class ArticleCacheDecodeWorkerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var policy: ArticleCacheHydrationCoordinator.Policy { .init(version: "1.3", maximumAge: 7 * 24 * 60 * 60, now: now) }
    private func encoded(_ articles: [Article], version: String = "1.3", age: TimeInterval = 0) throws -> Data {
        try JSONEncoder().encode(CacheData(articles: articles, timestamp: now.addingTimeInterval(-age), version: version))
    }
    func testActualDecoderKeepsExistingEnvelopeSchemaAndMetadata() async throws {
        let article = cacheArticle("A", created: "2026-01-01T12:00:00Z")
        let data = try encoded([article])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["articles", "timestamp", "version"]))
        let result = await ArticleCacheDecodeWorker().prepare(.encoded(data), policy: policy)
        guard case .ready(let prepared) = result else { return XCTFail("Expected accepted original schema") }
        XCTAssertEqual(prepared.articles, [article]); XCTAssertEqual(prepared.timestamp, now)
        XCTAssertTrue(prepared.articlesAreSorted)
    }
    func testCorruptBytesAndWrongVersionAreDistinctRejectedResults() async throws {
        let worker = ArticleCacheDecodeWorker()
        let corrupt = await worker.prepare(.encoded(Data("bad-json".utf8)), policy: policy)
        let wrong = await worker.prepare(.encoded(try encoded([cacheArticle("A")], version: "1.2")), policy: policy)
        XCTAssertEqual(corrupt, .rejected(.corrupt)); XCTAssertEqual(wrong, .rejected(.versionMismatch))
    }
    func testSevenDayBoundaryMatchesExistingStrictFreshnessPolicy() async throws {
        let worker = ArticleCacheDecodeWorker(), age: TimeInterval = 7 * 24 * 60 * 60
        let fresh = await worker.prepare(.encoded(try encoded([cacheArticle("A")], age: age - 0.1)), policy: policy)
        let expired = await worker.prepare(.encoded(try encoded([cacheArticle("A")], age: age)), policy: policy)
        guard case .ready = fresh else { return XCTFail("Just under seven days remains fresh") }
        XCTAssertEqual(expired, .rejected(.expired))
    }
    func testSuccessfulEmptyCacheIsReadyAndDoesNotInventNetworkFailure() async throws {
        let result = await ArticleCacheDecodeWorker().prepare(.encoded(try encoded([])), policy: policy)
        guard case .ready(let prepared) = result else { return XCTFail("An accepted empty cache is not corrupt or missing") }
        XCTAssertTrue(prepared.articles.isEmpty)
    }
    func testDecoderRejectsNonpublicEntriesBeforePresentation() async throws {
        let input = [cacheArticle("public"), cacheArticle("draft", draft: true),
                     cacheArticle("archived", archived: true), cacheArticle("unpublished", published: nil)]
        let result = await ArticleCacheDecodeWorker().prepare(.encoded(try encoded(input)), policy: policy)
        guard case .ready(let prepared) = result else { return XCTFail("Expected valid envelope") }
        XCTAssertEqual(prepared.articles.map(\.id), ["public"])
    }
    @MainActor
    func testWorkerSortMatchesActualExistingCreatedThenEditorialThenIDOrder() async throws {
        let input = [
            cacheArticle("a", created: "2026-01-01T12:00:00Z", editorial: "2026-10-01"),
            cacheArticle("b", created: "2026-01-02T12:00:00Z"),
            cacheArticle("z", editorial: "4. januar 2026"),
            cacheArticle("x", created: "bad-date", editorial: "January 3, 2026"),
            cacheArticle("tie-b", created: "2026-01-02T12:00:00Z"),
            cacheArticle("tie-a", created: "2026-01-02T12:00:00Z")
        ]
        let expected = Article.sortedByCreatedNewestFirst(input).map(\.id)
        let result = await ArticleCacheDecodeWorker().prepare(.encoded(try encoded(input)), policy: policy)
        guard case .ready(let prepared) = result else { return XCTFail("Expected ordered cache") }
        XCTAssertEqual(prepared.articles.map(\.id), expected)
    }
    func testAlreadySortedMemoryAvoidsChangingExistingOrderButStillChecksExpiry() async {
        let input = [cacheArticle("z"), cacheArticle("a")]
        let worker = ArticleCacheDecodeWorker()
        let result = await worker.prepare(.memory(articles: input, timestamp: now, articlesAreSorted: true), policy: policy)
        guard case .ready(let prepared) = result else { return XCTFail("Expected memory hit") }
        XCTAssertEqual(prepared.articles.map(\.id), ["z", "a"])
        let expired = await worker.prepare(.memory(articles: input, timestamp: now.addingTimeInterval(-7 * 24 * 60 * 60), articlesAreSorted: true), policy: policy)
        XCTAssertEqual(expired, .rejected(.expired))
    }
    func testFutureEnvelopeTimestampPreservesExistingAgeComparisonSemantics() async throws {
        let result = await ArticleCacheDecodeWorker().prepare(.encoded(try encoded([cacheArticle("A")], age: -60)), policy: policy)
        guard case .ready = result else { return XCTFail("This performance change must not silently add a different clock policy") }
    }
}
