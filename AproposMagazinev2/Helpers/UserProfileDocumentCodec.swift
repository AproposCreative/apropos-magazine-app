import Foundation

/// Converts profile documents without Firebase or network dependencies. Invalid
/// stored values throw instead of silently replacing a reader's data with defaults.
enum UserProfileDocumentCodec {
    enum DocumentError: Error {
        case invalidField(String)
    }

    static func decode(
        _ fields: [String: Any],
        userID: String,
        fallbackCreatedAt: Date,
        fallbackLastLoginAt: Date
    ) throws -> UserProfile {
        if let storedID = fields["uid"], storedID as? String != userID {
            throw DocumentError.invalidField("uid")
        }

        let notificationFields = try preferences(
            fields["notificationPreferences"],
            defaults: NotificationPreferences(),
            key: "notificationPreferences"
        )
        let readingFields = try preferences(
            fields["readingPreferences"],
            defaults: ReadingPreferences(),
            key: "readingPreferences"
        )
        // QuietHours' legacy Codable implementation tolerates invalid dates. Check
        // them here so corruption cannot reset a saved schedule on the next write.
        var notifications: NotificationPreferences = try decodePreferences(notificationFields)
        if let quietHours = notificationFields["quietHours"] as? [String: Any] {
            for key in ["startTime", "endTime"] {
                if let value = quietHours[key] {
                    let date = try date(value, key: key, quietHour: true)
                    if key == "startTime" {
                        notifications.quietHours.startTime = date
                    } else {
                        notifications.quietHours.endTime = date
                    }
                }
            }
        }

        return UserProfile(
            uid: userID,
            email: try value(fields, key: "email", default: ""),
            displayName: try value(fields, key: "displayName", default: ""),
            photoURL: try optionalValue(fields, key: "photoURL"),
            createdAt: try fields["createdAt"].map { try date($0, key: "createdAt") } ?? fallbackCreatedAt,
            lastLoginAt: try fields["lastLoginAt"].map { try date($0, key: "lastLoginAt") } ?? fallbackLastLoginAt,
            favoriteCategories: try value(fields, key: "favoriteCategories", default: [String]()),
            favoriteAuthors: try value(fields, key: "favoriteAuthors", default: [String]()),
            notificationPreferences: notifications,
            readingPreferences: try decodePreferences(readingFields),
            readArticles: try value(fields, key: "readArticles", default: [String]()),
            bookmarkedArticles: try value(fields, key: "bookmarkedArticles", default: [String]()),
            readingProgress: try value(fields, key: "readingProgress", default: [String: Double]())
        )
    }

    /// Dates use an explicit string format going forward. Earlier versions wrote
    /// JSONEncoder's reference-date numbers; the reader below still accepts them.
    static func encodePreferences<T: Encodable>(_ preferences: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(preferences)) as? [String: Any] ?? [:]
    }

    private static func preferences<T: Encodable>(
        _ stored: Any?, defaults: T, key: String
    ) throws -> [String: Any] {
        var result = try encodePreferences(defaults)
        guard let stored else { return result }
        guard let fields = stored as? [String: Any] else { throw DocumentError.invalidField(key) }
        for (key, value) in fields {
            if let nestedDefaults = result[key] as? [String: Any],
               let nested = value as? [String: Any] {
                result[key] = nestedDefaults.merging(nested) { _, stored in stored }
            } else {
                result[key] = value
            }
        }
        if key == "notificationPreferences", fields["newPodcasts"] == nil,
           let newArticles = fields["newArticles"] {
            result["newPodcasts"] = newArticles
        }
        return result
    }

    private static func decodePreferences<T: Decodable>(_ fields: [String: Any]) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                return try date(string, key: decoder.codingPath.last?.stringValue ?? "date", quietHour: true)
            }
            let number = try container.decode(Double.self)
            return try date(number, key: decoder.codingPath.last?.stringValue ?? "date", quietHour: true)
        }
        func jsonValue(_ value: Any) -> Any {
            if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
            if let dictionary = value as? [String: Any] { return dictionary.mapValues(jsonValue) }
            if let array = value as? [Any] { return array.map(jsonValue) }
            return value
        }
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: jsonValue(fields)))
    }

    private static func date(_ value: Any, key: String, quietHour: Bool = false) throws -> Date {
        let result: Date?
        if let date = value as? Date {
            result = date
        } else if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fractional = formatter.date(from: string)
            formatter.formatOptions = [.withInternetDateTime]
            result = fractional ?? formatter.date(from: string)
        } else if quietHour, let number = value as? Double, number.isFinite {
            // OfflineManager used seconds since 1970 for its 1970-anchored quiet
            // hours. saveUserProfile used seconds since 2001, which are negative.
            result = (0...86_400).contains(number)
                ? Date(timeIntervalSince1970: number)
                : Date(timeIntervalSinceReferenceDate: number)
        } else {
            result = nil
        }
        guard let result, (quietHour ? result.timeIntervalSince1970 >= 0 : result.timeIntervalSince1970 > 0) else {
            throw DocumentError.invalidField(key)
        }
        return result
    }

    private static func value<T>(_ fields: [String: Any], key: String, default fallback: T) throws -> T {
        guard let stored = fields[key] else { return fallback }
        guard let value = stored as? T else { throw DocumentError.invalidField(key) }
        return value
    }

    private static func optionalValue<T>(_ fields: [String: Any], key: String) throws -> T? {
        guard let stored = fields[key], !(stored is NSNull) else { return nil }
        guard let value = stored as? T else { throw DocumentError.invalidField(key) }
        return value
    }
}
