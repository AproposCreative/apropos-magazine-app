import XCTest
@testable import Apropos_Magazine

@MainActor
final class RecommendationEngineTests: XCTestCase {
    private func article(
        id: String,
        name: String = "Artikel \(UUID().uuidString)",
        topic: String = "topic-default",
        stjerne: Int? = nil,
        authorID: String? = nil,
        topicsIDs: [String]? = nil
    ) -> Article {
        Article(
            id: id,
            name: name,
            slug: id,
            content: "Body",
            intro: "Intro",
            stjerne: stjerne,
            topicID: topic,
            topicsIDs: topicsIDs,
            authorID: authorID
        )
    }

    private func makeUser(readArticles: [String] = []) -> UserProfile {
        UserProfile(
            uid: "u1",
            email: "test@example.com",
            displayName: "Test",
            photoURL: nil,
            createdAt: Date(),
            lastLoginAt: Date(),
            favoriteCategories: ["music"],
            favoriteAuthors: [],
            notificationPreferences: NotificationPreferences(),
            readingPreferences: ReadingPreferences(),
            readArticles: readArticles,
            bookmarkedArticles: [],
            readingProgress: [:]
        )
    }

    func testTrendingSortedByRatingDescendingMaxFive() {
        let engine = RecommendationEngine.shared
        let articles = (1...7).map { article(id: "trend-\($0)", stjerne: $0) }
        let trending = engine.getTrendingArticles(from: articles)

        XCTAssertEqual(trending.count, 5)
        XCTAssertEqual(trending.map(\.rating), [7, 6, 5, 4, 3])
    }

    func testRelatedExcludesSourceAndPrefersSameTopic() {
        let engine = RecommendationEngine.shared
        let source = article(id: "rel-src", topic: "music")
        let sameTopic = article(id: "rel-same", topic: "music")
        let other = article(id: "rel-other", topic: "film")

        let related = engine.getRelatedArticles(to: source, from: [source, sameTopic, other])

        XCTAssertFalse(related.contains { $0.id == "rel-src" })
        XCTAssertEqual(related.first?.id, "rel-same")
    }

    func testRelatedReturnsEmptyForEmptyInput() {
        let engine = RecommendationEngine.shared
        XCTAssertTrue(engine.getRelatedArticles(to: article(id: "x"), from: []).isEmpty)
    }

    func testFestivalRecommendationsFilterByKeyword() {
        let engine = RecommendationEngine.shared
        let festival = article(id: "fest", name: "Roskilde Festival 2026")
        let plain = article(id: "plain", name: "En stille eftermiddag")

        let result = engine.getFestivalRecommendations(from: [festival, plain])

        XCTAssertEqual(result.map(\.id), ["fest"])
    }

    func testPersonalizedFeedIsCappedAtTen() async {
        let engine = RecommendationEngine.shared
        let articles = (1...20).map { article(id: "feed-\($0)", stjerne: $0 % 5) }

        let feed = await engine.getPersonalizedFeed(for: makeUser(), from: articles)

        XCTAssertLessThanOrEqual(feed.count, 10)
    }
}
