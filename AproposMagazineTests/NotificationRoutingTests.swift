import XCTest
@testable import Apropos_Magazine

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
}
