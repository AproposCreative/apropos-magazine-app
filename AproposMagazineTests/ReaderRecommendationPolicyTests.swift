import XCTest
@testable import Apropos

final class ReaderRecommendationPolicyTests: XCTestCase {
    private func article(_ id: String, topic: String = "music", authorID: String? = nil, published: Bool = true) -> Article {
        Article(id: id, name: id, slug: id, content: "", intro: "", topicID: topic,
                authorID: authorID, isDraft: !published, createdOn: "2026-10-20T12:00:00Z",
                lastPublished: "2026-10-20T12:00:00Z")
    }

    func testExplicitInterestsDriveRecommendationsWithoutPushSubscription() {
        let result = ReaderRecommendationPolicy.recommendations(
            articles: [article("music"), article("film", topic: "film")], favorites: [],
            interestTopicIDs: ["film"], readArticleIDs: []
        )
        XCTAssertEqual(result.first?.0.id, "film")
        XCTAssertTrue(result.first?.1.contains("valgte interesser") == true)
    }

    func testDraftsReadArticlesAndDuplicateIDsAreExcluded() {
        let result = ReaderRecommendationPolicy.recommendations(
            articles: [article("read"), article("draft", published: false), article("visible"), article("visible")],
            favorites: [], interestTopicIDs: [], readArticleIDs: ["read"]
        )
        XCTAssertEqual(result.map { $0.0.id }, ["visible"])
    }

    func testColdStartDoesNotInventFollowingAnAuthor() {
        let result = ReaderRecommendationPolicy.recommendations(
            articles: [article("story", authorID: "writer")], favorites: [], interestTopicIDs: [], readArticleIDs: []
        )
        XCTAssertEqual(result.first?.1, "Nyt fra Apropos Magazine")
    }

    func testDiversityAndLimitDoNotLoseCandidates() {
        let input = (0..<7).map { article("music-\($0)") } + [article("film", topic: "film")]
        let result = ReaderRecommendationPolicy.recommendations(
            articles: input, favorites: [], interestTopicIDs: ["music"], readArticleIDs: [], limit: 8
        )
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual(result[3].0.id, "film")
        XCTAssertEqual(Set(result.map { $0.0.id }).count, 8)
    }

    func testFavoriteAuthorReasonRequiresAnActualFavorite() {
        let result = ReaderRecommendationPolicy.recommendations(
            articles: [article("story", topic: "film", authorID: "writer")],
            favorites: [article("saved", topic: "books", authorID: "writer")],
            interestTopicIDs: [], readArticleIDs: []
        )
        XCTAssertEqual(result.first?.1, "Fra en forfatter i dine gemte artikler")
    }
}
