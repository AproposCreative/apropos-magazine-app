import XCTest
@testable import Apropos_Magazine

final class WidgetArticleTests: XCTestCase {
    func testWidgetArticleRoundTripJSON() throws {
        let article = WidgetArticle(
            id: "abc123",
            name: "Test artikel",
            slug: "test-artikel",
            thumbURL: "https://example.com/thumb.jpg",
            intro: "Intro tekst",
            date: "2026-05-28T10:00:00.000Z",
            stjerne: 4,
            topic: "Musik"
        )

        let data = try JSONEncoder().encode([article])
        let decoded = try JSONDecoder().decode([WidgetArticle].self, from: data)

        XCTAssertEqual(decoded.first?.id, article.id)
        XCTAssertEqual(decoded.first?.name, article.name)
        XCTAssertEqual(decoded.first?.stjerne, 4)
        XCTAssertEqual(decoded.first?.topic, "Musik")
    }

    func testWidgetDataStoreSkipsEmptySave() throws {
        guard WidgetDataStore.isAppGroupAvailable else {
            throw XCTSkip("App Group unavailable in test host")
        }

        let before = WidgetDataStore.loadLatestArticles()
        WidgetDataStore.saveLatestArticles([], reloadTimelines: false)
        let after = WidgetDataStore.loadLatestArticles()
        XCTAssertEqual(before.map(\.id), after.map(\.id))
    }
}
