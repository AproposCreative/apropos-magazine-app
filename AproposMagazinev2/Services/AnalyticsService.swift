import FirebaseAnalytics
import Foundation

/// No SDK work starts at construction. The guarded app runtime installs consent;
/// tests inject a sink and a clock instead of initializing Analytics.
@MainActor
final class AnalyticsService {
    struct Event: Equatable {
        let name: String
        let identifiers: [String: String]
        let counts: [String: Int]
    }
    static let shared = AnalyticsService(model: nil, now: Date.init) { event in
        var parameters: [String: Any] = event.identifiers
        for (key, value) in event.counts { parameters[key] = value }
        Analytics.logEvent(event.name, parameters: parameters)
    }

    enum ArticleOpenSource: String { case feed, notification, recommendation, search }
    private var model: TelemetryConsentModel?
    private let now: () -> Date
    private let emit: (Event) -> Void
    private var pendingArticleOpenSource: ArticleOpenSource = .feed
    private var articleOpenTimestamps: [String: Date] = [:]
    private var loggedArticleReads: Set<String> = []
    private var bufferGeneration: UUID?

    init(model: TelemetryConsentModel?, now: @escaping () -> Date, emit: @escaping (Event) -> Void) {
        self.model = model
        self.now = now
        self.emit = emit
    }

    func configure(model: TelemetryConsentModel) {
        clearTransientBuffers()
        self.model = model
    }

    func clearTransientBuffers() {
        pendingArticleOpenSource = .feed
        articleOpenTimestamps.removeAll()
        loggedArticleReads.removeAll()
        bufferGeneration = nil
    }

    private func permitted(_ action: ((Event) -> Void) -> Void) {
        guard let model, let ticket = model.captureTicket(for: .analytics) else { return }
        model.withPermission(ticket, for: .analytics) {
            let generation = model.snapshot().generation
            if bufferGeneration != generation {
                clearTransientBuffers()
                bufferGeneration = generation
            }
            action { event in
                model.withPermission(ticket, for: .analytics) { emit(event) }
            }
        }
    }

    func setPendingArticleOpenSource(_ source: ArticleOpenSource) {
        permitted { _ in pendingArticleOpenSource = source }
    }

    func trackArticleOpen(_ article: Article, source: ArticleOpenSource? = nil) {
        guard let id = identifier(article.id) else { return }
        permitted { send in
            let instant = now()
            guard instant.timeIntervalSince1970.isFinite, instant.timeIntervalSince1970 > 0 else { return }
            let source = source ?? pendingArticleOpenSource
            pendingArticleOpenSource = .feed
            // Keep in-session data bounded even during unusually long sessions.
            if articleOpenTimestamps.count >= 256 { articleOpenTimestamps.removeAll(); loggedArticleReads.removeAll() }
            articleOpenTimestamps[id] = instant
            var fields = ["article_id": id, "source": source.rawValue]
            if let topic = article.topicID.flatMap(identifier) { fields["topic_id"] = topic }
            if let author = article.authorID.flatMap(identifier) { fields["author_id"] = author }
            send(Event(name: "article_open", identifiers: fields, counts: [:]))
        }
    }

    func trackArticleReadIfNeeded(_ article: Article, scrollProgress: Double) {
        guard scrollProgress.isFinite, scrollProgress >= 0.8, scrollProgress <= 1,
              let id = identifier(article.id) else { return }
        permitted { send in
            // Never infer pre-consent reading, or carry dwell time across account/choice changes.
            guard !loggedArticleReads.contains(id), let opened = articleOpenTimestamps[id] else { return }
            let elapsed = now().timeIntervalSince(opened)
            guard elapsed.isFinite, elapsed >= 0, elapsed <= 86_400 else { return }
            loggedArticleReads.insert(id)
            send(Event(name: "article_read", identifiers: ["article_id": id], counts: ["read_time_seconds": Int(elapsed)]))
        }
    }

    func trackPodcastPlay(episode: PodcastEpisode, articleId: String? = nil) {
        guard let id = identifier(articleId ?? episode.articleId ?? episode.articleSlug ?? episode.id) else { return }
        permitted { send in send(Event(name: "podcast_play", identifiers: ["article_id": id], counts: [:])) }
    }

    func trackRecommendationTap(articleId: String, reason: String) {
        guard let id = identifier(articleId) else { return }
        // The editorial explanation is free text and never enters the event sink.
        permitted { send in send(Event(name: "recommendation_tap", identifiers: ["article_id": id], counts: [:])) }
    }

    func trackNotificationOpen(articleId: String, type: String) {
        guard let id = identifier(articleId) else { return }
        let knownTypes: Set<String> = ["new_article", "new_podcast", "article", "podcast", "breaking_news", "general"]
        let kind = knownTypes.contains(type) ? type : "other"
        permitted { send in send(Event(name: "notification_open", identifiers: ["article_id": id, "notification_type": kind], counts: [:])) }
    }

    private func identifier(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.count <= 100,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return value
    }
}
