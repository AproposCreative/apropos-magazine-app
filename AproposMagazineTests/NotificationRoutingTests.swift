import XCTest
@testable import Apropos

/// Regression coverage for `NotificationNavigation`. Tapping an audio
/// notification must route through the podcast path so the player opens —
/// this broke when AI narrations (`new_narration`) were not recognised as
/// audio content.
final class NotificationRoutingTests: XCTestCase {

    // MARK: - Audio vs article classification

    func testNewPodcastIsAudio() {
        let payload = NotificationNavigation.Payload(
            articleIdentifier: "1", articleSlug: nil, type: "new_podcast", podcastTitle: nil
        )
        XCTAssertTrue(payload.isPodcastNotification)
        XCTAssertFalse(payload.isArticleNotification)
    }

    func testNewNarrationIsAudio() {
        // The AI-narration regression: must be treated as audio.
        let payload = NotificationNavigation.Payload(
            articleIdentifier: "1", articleSlug: nil, type: "new_narration", podcastTitle: nil
        )
        XCTAssertTrue(payload.isPodcastNotification)
    }

    func testNewArticleIsNotAudio() {
        let payload = NotificationNavigation.Payload(
            articleIdentifier: "1", articleSlug: nil, type: "new_article", podcastTitle: nil
        )
        XCTAssertFalse(payload.isPodcastNotification)
        XCTAssertTrue(payload.isArticleNotification)
    }

    // MARK: - Payload extraction

    func testPayloadFromFlatUserInfo() {
        let payload = NotificationNavigation.payload(from: [
            "article_id": "abc123",
            "article_slug": "heartland-2026",
            "type": "new_narration",
        ])
        XCTAssertEqual(payload?.articleIdentifier, "abc123")
        XCTAssertEqual(payload?.articleSlug, "heartland-2026")
        XCTAssertEqual(payload?.type, "new_narration")
        XCTAssertEqual(payload?.isPodcastNotification, true)
    }

    func testPayloadFromNestedDataDictionary() {
        // FCM data sometimes arrives nested under "data".
        let payload = NotificationNavigation.payload(from: [
            "data": [
                "article_id": "nested-id",
                "type": "new_article",
            ] as [String: Any],
        ])
        XCTAssertEqual(payload?.articleIdentifier, "nested-id")
        XCTAssertEqual(payload?.type, "new_article")
    }

    func testPayloadFromNestedJSONStringData() {
        let payload = NotificationNavigation.payload(from: [
            "data": "{\"article_id\":\"json-id\",\"type\":\"new_podcast\"}",
        ])
        XCTAssertEqual(payload?.articleIdentifier, "json-id")
        XCTAssertEqual(payload?.type, "new_podcast")
    }

    func testPayloadPrefersIdOverSlug() {
        let payload = NotificationNavigation.payload(from: [
            "article_id": "real-id",
            "slug": "some-slug",
            "type": "new_article",
        ])
        XCTAssertEqual(payload?.articleIdentifier, "real-id")
        XCTAssertEqual(payload?.articleSlug, "some-slug")
    }

    func testPayloadReturnsNilWithoutIdentifier() {
        XCTAssertNil(NotificationNavigation.payload(from: ["type": "new_article"]))
        XCTAssertNil(NotificationNavigation.payload(from: ["article_id": "   "]))
    }

    func testPayloadDefaultsTypeToGeneral() {
        let payload = NotificationNavigation.payload(from: ["article_id": "x"])
        XCTAssertEqual(payload?.type, "general")
    }

    // MARK: - userInfo round trip

    func testUserInfoRoundTrip() {
        let original = NotificationNavigation.Payload(
            articleIdentifier: "id-1",
            articleSlug: "slug-1",
            type: "new_narration",
            podcastTitle: "Episode"
        )
        let info = NotificationNavigation.userInfo(for: original)
        let restored = NotificationNavigation.payload(from: info)

        XCTAssertEqual(restored?.articleIdentifier, "id-1")
        XCTAssertEqual(restored?.articleSlug, "slug-1")
        XCTAssertEqual(restored?.type, "new_narration")
        XCTAssertEqual(restored?.isPodcastNotification, true)
    }

    func testArticleOutboxNarrationAvailabilityDoesNotChangeArticleDestination() throws {
        // The existing article-outbox envelope labels the availability of an
        // AI narration with new_narration, while still announcing an article.
        let item = try XCTUnwrap(NotificationInboxItem.make(id: "article-announcement", title: "Ny artikel",
            body: "Artiklen er tilgængelig", date: Date(timeIntervalSince1970: 100), userInfo: [
            "article_id": "article-1", "article_slug": "article-one",
            "article_name": "En ny artikel", "type": "new_narration", "click_action": "OPEN_ARTICLE",
        ]))
        let payload = try XCTUnwrap(item.target?.payload)
        XCTAssertTrue(payload.isArticleNotification)
        XCTAssertFalse(payload.isPodcastNotification)
        XCTAssertEqual(payload.articleIdentifier, "article-1")
        XCTAssertEqual(payload.articleSlug, "article-one")
    }

    func testExplicitPodcastOutboxNarrationAndPodcastStillOpenAudio() throws {
        for type in ["new_podcast", "new_narration"] {
            let item = try XCTUnwrap(NotificationInboxItem.make(id: "audio-announcement", title: "Lyt nu",
                body: "Lyden er klar", date: Date(timeIntervalSince1970: 100), userInfo: [
                "article_id": "article-1", "article_slug": "article-one",
                "podcast_title": "En ny episode", "type": type, "click_action": "OPEN_ARTICLE",
            ]))
            let payload = try XCTUnwrap(item.target?.payload)
            XCTAssertTrue(payload.isPodcastNotification, type)
            XCTAssertFalse(payload.isArticleNotification, type)
        }
    }

    func testInboxUsesStructuredTypeAndAudioMetadataRatherThanVisibleTitle() throws {
        func target(_ info: [AnyHashable: Any], title: String = "Ny artikel") -> NotificationInboxItem.Target? {
            NotificationInboxItem.make(id: "receipt", title: title, body: "Lyt nu, hvis du vil",
                date: Date(timeIntervalSince1970: 100), userInfo: info)?.target
        }
        for type in ["new_article", "breaking_news"] {
            let article = try XCTUnwrap(target(["type": type, "article_id": "a", "article_name": "Artikel",
                                                "podcast_title": "En eksisterende oplæsning"]))
            XCTAssertTrue(article.payload.isArticleNotification)
            XCTAssertFalse(article.payload.isPodcastNotification)
            XCTAssertNil(article.podcastTitle)
        }
        // Both descriptive names may coexist in the explicit audio envelope.
        let narration = try XCTUnwrap(target(["type": "new_narration", "article_id": "a",
            "article_name": "Artikel", "podcast_title": "  Oplæsningen  "]))
        XCTAssertTrue(narration.payload.isPodcastNotification)
        XCTAssertEqual(narration.payload.podcastTitle, "Oplæsningen")
        let ambiguous = try XCTUnwrap(target(["type": "new_narration", "article_id": "a"], title: "Lyt til podcasten"))
        XCTAssertTrue(ambiguous.payload.isArticleNotification)
        XCTAssertFalse(ambiguous.payload.isPodcastNotification)
        XCTAssertTrue(try XCTUnwrap(target(["type": "new_podcast", "article_id": "a"])).payload.isPodcastNotification)
        for type in ["general", "test", "audio", "narration"] {
            XCTAssertNil(target(["type": type, "article_id": "a", "podcast_title": "En episode"]), type)
        }
        XCTAssertNil(target(["type": "new_narration", "article_id": "a", "podcast_title": "En episode", "uid": "A"]))
        // The global typed ingress retains its existing narration semantics.
        XCTAssertTrue(NotificationNavigation.Payload(articleIdentifier: "a", articleSlug: nil,
            type: "new_narration", podcastTitle: nil).isPodcastNotification)
    }
}
