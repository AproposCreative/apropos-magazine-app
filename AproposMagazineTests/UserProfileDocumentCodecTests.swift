import XCTest
@testable import Apropos

/// Pure document fixtures: these tests never create an Auth or Firestore client.
final class UserProfileDocumentCodecTests: XCTestCase {
    private let created = Date(timeIntervalSince1970: 1_750_000_000.125)
    private let lastLogin = Date(timeIntervalSince1970: 1_760_000_000)

    private func decode(_ fields: [String: Any]) throws -> UserProfile {
        try UserProfileDocumentCodec.decode(
            fields,
            userID: "reader-1",
            fallbackCreatedAt: created,
            fallbackLastLoginAt: lastLogin
        )
    }

    func testFirestoreDatesAndReaderDataSurviveDecoding() throws {
        let profile = try decode([
            "uid": "reader-1", "email": "reader@example.invalid", "displayName": "Reader",
            "createdAt": created, "lastLoginAt": lastLogin,
            "favoriteCategories": ["music"], "favoriteAuthors": ["author-1"],
            "readArticles": ["read-1"], "bookmarkedArticles": ["saved-1"],
            "readingProgress": ["read-1": 0.75]
        ])
        XCTAssertEqual(profile.createdAt, created)
        XCTAssertEqual(profile.lastLoginAt, lastLogin)
        XCTAssertEqual(profile.favoriteCategories, ["music"])
        XCTAssertEqual(profile.readArticles, ["read-1"])
        XCTAssertEqual(profile.bookmarkedArticles, ["saved-1"])
        XCTAssertEqual(profile.readingProgress["read-1"], 0.75)
    }

    func testISO8601DatesAcceptFractionalAndWholeSeconds() throws {
        let profile = try decode([
            "createdAt": "2026-10-15T12:34:56.125Z",
            "lastLoginAt": "2026-10-15T12:34:56Z"
        ])
        XCTAssertEqual(profile.createdAt.timeIntervalSince(profile.lastLoginAt), 0.125, accuracy: 0.0001)
    }

    func testNewPreferencesRoundTripIncludingMidnightQuietHours() throws {
        var notifications = NotificationPreferences(newArticles: false, newPodcasts: true)
        notifications.quietHours.enabled = true
        notifications.quietHours.startTime = Date(timeIntervalSince1970: 0)
        notifications.quietHours.endTime = Date(timeIntervalSince1970: 5 * 3600)
        let fields = try UserProfileDocumentCodec.encodePreferences(notifications)
        let restored = try decode(["notificationPreferences": fields])
        XCTAssertEqual(restored.notificationPreferences, notifications)
        XCTAssertTrue((fields["quietHours"] as? [String: Any])?["startTime"] is String)
    }

    func testLegacyJSONEncoderQuietHoursAreMigratedWithoutReset() throws {
        var notifications = NotificationPreferences()
        notifications.quietHours.enabled = true
        notifications.quietHours.startTime = Date(timeIntervalSince1970: 19 * 3600)
        notifications.quietHours.endTime = Date(timeIntervalSince1970: 5 * 3600)
        let legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(notifications))
        let restored = try decode(["notificationPreferences": legacy])
        XCTAssertEqual(restored.notificationPreferences, notifications)
    }

    func testLegacyOfflineSyncQuietHoursUseUnixSeconds() throws {
        let restored = try decode([
            "notificationPreferences": [
                "newArticles": false,
                "quietHours": ["enabled": true, "startTime": 20.0 * 3600, "endTime": 0.0]
            ]
        ])
        XCTAssertFalse(restored.notificationPreferences.newArticles)
        XCTAssertEqual(restored.notificationPreferences.quietHours.startTime.timeIntervalSince1970, 20 * 3600)
        XCTAssertEqual(restored.notificationPreferences.quietHours.endTime.timeIntervalSince1970, 0)
    }

    func testPartialOldPreferencesPreserveStoredChoices() throws {
        let restored = try decode(["readingPreferences": ["showImages": false]])
        XCTAssertFalse(restored.readingPreferences.showImages)
        XCTAssertEqual(restored.readingPreferences.fontSize, .medium)
    }

    func testMalformedStoredDataThrowsInsteadOfBecomingEmptyDefaults() {
        for fields: [String: Any] in [
            ["createdAt": "not-a-date"],
            ["readArticles": "broken"],
            ["readingProgress": ["article": "broken"]],
            ["readingPreferences": ["fontSize": "unknown"]],
            ["notificationPreferences": ["quietHours": ["startTime": "broken"]]],
            ["uid": "another-account"]
        ] {
            XCTAssertThrowsError(try decode(fields))
        }
    }
}
