import XCTest
@testable import Apropos_Magazine

final class ShareAndNotificationTests: XCTestCase {
    func testArticleURLUsesSlugWhenAvailable() {
        let url = ShareLinkBuilder.articleURL(slug: "cape-fear", articleId: "id-1")
        XCTAssertEqual(url?.absoluteString, "https://aproposmagazine.com/article/cape-fear")
    }

    func testPodcastClipURLAddsTimestampQuery() {
        let url = ShareLinkBuilder.podcastClipURL(slug: "bond", articleId: "id-2", timestampSeconds: 125)
        XCTAssertEqual(url?.absoluteString, "https://aproposmagazine.com/article/bond?t=125")
    }

    func testFormattedTimestamp() {
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(65), "1:05")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(3665), "1:01:05")
    }

    func testFavoriteToggleAddsAndRemovesArticle() {
        let article = Article(
            id: "a1",
            name: "Test",
            slug: "test",
            content: "Body",
            intro: "Intro",
            topicID: "topic-1"
        )
        var favorites: [Article] = []

        favorites = FavoriteArticlesLogic.toggledFavorites(for: article, current: favorites)
        XCTAssertTrue(FavoriteArticlesLogic.isFavorite(articleId: "a1", in: favorites))

        favorites = FavoriteArticlesLogic.toggledFavorites(for: article, current: favorites)
        XCTAssertFalse(FavoriteArticlesLogic.isFavorite(articleId: "a1", in: favorites))
    }

    func testNotificationDeliveryPolicyRespectsQuietHours() {
        var settings = NotificationSettings()
        settings.quietHours.enabled = true
        settings.quietHours.startTime = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
        settings.quietHours.endTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()

        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 28
        components.hour = 23
        components.minute = 0
        let lateEvening = Calendar.current.date(from: components)!

        XCTAssertTrue(NotificationDeliveryPolicy.isWithinQuietHours(lateEvening, quietHours: settings.quietHours))
        XCTAssertFalse(
            NotificationDeliveryPolicy.shouldScheduleLocalNotification(at: lateEvening, settings: settings)
        )
    }

    func testWidgetFormattingCTAForReviewArticles() {
        let review = WidgetArticle(
            id: "1",
            name: "Review",
            slug: "review",
            thumbURL: "",
            intro: "",
            date: "",
            stjerne: 5,
            topic: "Anmeldelser"
        )

        XCTAssertEqual(WidgetArticleFormatting.ctaText(for: review), "Læs anmeldelsen →")
    }
}
