import XCTest
@testable import Apropos

final class OfflineLibrarySnapshotTests: XCTestCase {
    private func article(_ id: String, body: String = "body", revision: String = "v1") -> Article {
        Article(id: id, name: id, slug: id, content: body, intro: "intro", topicID: "topic", lastPublished: revision)
    }

    func testBatchMatchesSequentialUpdatesAndKeepsNewestFifty() {
        let existing = (0..<45).map { article("existing-\($0)") }
        let incoming = (0..<20).map { article("new-\($0)") }
        let result = OfflineLibrarySnapshot.merging(incoming, into: existing)
        XCTAssertEqual(result.articles.count, 50)
        XCTAssertEqual(result.articles.map(\.id), Array(existing.suffix(30)).map(\.id) + incoming.map(\.id))
        XCTAssertEqual(result.removedIDs, Set(existing.prefix(15).map(\.id)))
        XCTAssertEqual(result.changedArticles.map(\.id), incoming.map(\.id))
    }

    func testDuplicatesUpdateOnceAndMostRecentSaveControlsOrder() {
        let result = OfflineLibrarySnapshot.merging(
            [article("b"), article("a", body: "updated"), article("b", body: "last")],
            into: [article("a"), article("c")]
        )
        XCTAssertEqual(result.articles.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(result.articles.last?.content, "last")
        XCTAssertEqual(result.changedArticles.map(\.id), ["a", "b"])
    }

    func testSameRevisionSummaryPreservesOfflineBodyAndNewMetadata() {
        let existing = article("a", body: "saved full body")
        let incoming = Article(id: "a", name: "New headline", slug: "a", content: "", intro: "intro", topicID: "topic", lastPublished: "v1")
        let result = OfflineLibrarySnapshot.merging([incoming], into: [existing])
        XCTAssertEqual(result.articles.first?.content, "saved full body")
        XCTAssertEqual(result.articles.first?.name, "New headline")
    }

    func testChangedRevisionDoesNotSilentlyReuseOldBody() {
        let result = OfflineLibrarySnapshot.merging(
            [article("a", body: "", revision: "v2")], into: [article("a", body: "old body")]
        )
        XCTAssertEqual(result.articles.first?.content, "")
        XCTAssertEqual(result.articles.first?.lastPublished, "v2")
    }

    func testIdenticalBatchHasNoChangedMediaAndEmptyInputPreservesLibrary() {
        let existing = [article("a"), article("b")]
        let result = OfflineLibrarySnapshot.merging(existing, into: existing)
        XCTAssertEqual(result.articles, existing)
        XCTAssertTrue(result.changedArticles.isEmpty)
        XCTAssertTrue(result.removedIDs.isEmpty)
        XCTAssertEqual(OfflineLibrarySnapshot.merging([], into: existing).articles, existing)
    }
}
