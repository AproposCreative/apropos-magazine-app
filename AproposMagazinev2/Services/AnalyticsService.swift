import FirebaseAnalytics
import Foundation

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    enum ArticleOpenSource: String {
        case feed
        case notification
        case recommendation
        case search
    }

    private var pendingArticleOpenSource: ArticleOpenSource = .feed
    private var articleOpenTimestamps: [String: Date] = [:]
    private var loggedArticleReads: Set<String> = []

    private init() {}

    private var isEnabled: Bool {
        PreferencesManager.shared.preferences.privacyPreferences.analyticsEnabled
    }

    func configure() {
        applyCollectionPreference()
    }

    func applyCollectionPreference() {
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    func setPendingArticleOpenSource(_ source: ArticleOpenSource) {
        pendingArticleOpenSource = source
    }

    func trackArticleOpen(_ article: Article, source: ArticleOpenSource? = nil) {
        guard isEnabled else { return }

        let resolvedSource = source ?? pendingArticleOpenSource
        pendingArticleOpenSource = .feed
        articleOpenTimestamps[article.id] = Date()

        Analytics.logEvent(
            "article_open",
            parameters: [
                "article_id": trimmed(article.id),
                "topic_id": trimmed(article.topicID ?? ""),
                "author_id": trimmed(article.authorID ?? ""),
                "source": resolvedSource.rawValue,
            ]
        )
    }

    func trackArticleReadIfNeeded(_ article: Article, scrollProgress: Double) {
        guard isEnabled else { return }
        guard scrollProgress >= 0.8 else { return }
        guard !loggedArticleReads.contains(article.id) else { return }

        loggedArticleReads.insert(article.id)
        let openedAt = articleOpenTimestamps[article.id] ?? Date()
        let seconds = max(0, Int(Date().timeIntervalSince(openedAt)))

        Analytics.logEvent(
            "article_read",
            parameters: [
                "article_id": trimmed(article.id),
                "read_time_seconds": seconds,
            ]
        )
    }

    func trackPodcastPlay(episode: PodcastEpisode, articleId: String? = nil) {
        guard isEnabled else { return }

        let resolvedArticleId = articleId
            ?? episode.articleId
            ?? episode.articleSlug
            ?? episode.id

        Analytics.logEvent(
            "podcast_play",
            parameters: [
                "article_id": trimmed(resolvedArticleId),
                "episode_title": trimmed(episode.title),
            ]
        )
    }

    func trackRecommendationTap(articleId: String, reason: String) {
        guard isEnabled else { return }

        Analytics.logEvent(
            "recommendation_tap",
            parameters: [
                "article_id": trimmed(articleId),
                "reason": trimmed(reason),
            ]
        )
    }

    func trackNotificationOpen(articleId: String, type: String) {
        guard isEnabled else { return }

        Analytics.logEvent(
            "notification_open",
            parameters: [
                "article_id": trimmed(articleId),
                "notification_type": trimmed(type),
            ]
        )
    }

    private func trimmed(_ value: String, maxLength: Int = 100) -> String {
        String(value.prefix(maxLength))
    }
}
