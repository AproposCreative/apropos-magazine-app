import Foundation

enum NotificationNavigation {
    static let skipBootloaderKey = "skip_bootloader_for_notification"

    struct Payload {
        let articleIdentifier: String
        let articleSlug: String?
        let type: String
        let podcastTitle: String?

        var isPodcastNotification: Bool {
            // Both human/NotebookLM podcasts ("new_podcast") and AI narrations
            // ("new_narration") are audio content: route them through the podcast
            // path so the manifest is force-refreshed and the player opens.
            type == "new_podcast" || type == "new_narration"
        }

        var isArticleNotification: Bool {
            type == "new_article" || type == "breaking_news"
        }
    }

    static func userInfo(for payload: Payload) -> [String: Any] {
        var info: [String: Any] = [
            "articleId": payload.articleIdentifier,
            "article_id": payload.articleIdentifier,
            "type": payload.type,
            "notificationType": payload.type,
        ]

        if let slug = payload.articleSlug, !slug.isEmpty {
            info["article_slug"] = slug
        }

        if let podcastTitle = payload.podcastTitle, !podcastTitle.isEmpty {
            info["podcast_title"] = podcastTitle
        }

        return info
    }

    static func payload(from userInfo: [AnyHashable: Any]) -> Payload? {
        let normalized = normalize(userInfo)

        let slug = stringValue(normalized, keys: ["article_slug", "articleSlug", "slug"])
        let articleId = stringValue(normalized, keys: ["article_id", "articleId", "id"])
        // Prefer Webflow/Firestore id for fetch (fast doc lookup); keep slug for cache matching.
        let identifier: String? = {
            for candidate in [articleId, slug] {
                if let candidate, !candidate.isEmpty {
                    return candidate
                }
            }
            return nil
        }()

        guard let identifier else { return nil }

        return Payload(
            articleIdentifier: identifier,
            articleSlug: slug ?? (identifier.contains("-") ? identifier : nil),
            type: stringValue(normalized, keys: ["type", "notification_type"]) ?? "general",
            podcastTitle: stringValue(normalized, keys: ["podcast_title", "podcastTitle"])
        )
    }

    static func normalize(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]

        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            merged[key] = value
        }

        if let nested = merged["data"] as? [String: Any] {
            for (key, value) in nested {
                merged[key] = value
            }
        } else if let nestedString = merged["data"] as? String,
                  let data = nestedString.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in nested {
                merged[key] = value
            }
        }

        return merged
    }

    private static func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
