import Foundation
import OSLog

struct ScoredRecommendation {
    let article: Article
    let score: Int
    var reason: String = ""
}

@MainActor
final class RecommendationService {
    static let shared = RecommendationService()

    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "RecommendationService")
    private let cacheKey = "cached_personalized_recommendations"
    private let cacheTimestampKey = "cached_personalized_recommendations_ts"
    private let cacheTTL: TimeInterval = 6 * 60 * 60

    private init() {}

    func loadCached() -> [(Article, String)]? {
        guard let ts = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date,
              Date().timeIntervalSince(ts) < cacheTTL,
              let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedRecommendationEntry].self, from: data) else {
            return nil
        }
        return cached.map { ($0.article, $0.reason) }
    }

    func generateRecommendations(
        articles: [Article],
        favorites: [Article],
        subscribedCategoryIds: [String],
        readArticleIds: [String]
    ) async -> [(Article, String)] {
        let scored = scoreArticles(
            articles: articles,
            favorites: favorites,
            subscribedCategoryIds: subscribedCategoryIds,
            readArticleIds: Set(readArticleIds)
        )
        let top = Array(scored.prefix(10))
        guard !top.isEmpty else { return [] }

        let reasons = await fetchReasons(for: top, favorites: favorites)
        let combined = top.enumerated().map { index, item in
            (item.article, reasons[item.article.id] ?? defaultReason(for: item.article, favorites: favorites))
        }

        cache(combined)
        return combined
    }

    private func scoreArticles(
        articles: [Article],
        favorites: [Article],
        subscribedCategoryIds: [String],
        readArticleIds: Set<String>
    ) -> [ScoredRecommendation] {
        let favoriteTopicCounts = topicFrequency(from: favorites)
        let favoriteAuthorIds = Set(favorites.compactMap(\.authorID))

        let scored: [ScoredRecommendation] = articles.compactMap { article in
            var score = 0

            let articleTopics = Set((article.topicsIDs ?? []) + [article.topicID].compactMap { $0 })
            for topic in articleTopics {
                score += (favoriteTopicCounts[topic] ?? 0) * 3
            }

            if let authorID = article.authorID, favoriteAuthorIds.contains(authorID) {
                score += 2
            }

            if let stars = article.stjerne {
                score += stars
            }

            for categoryId in subscribedCategoryIds where articleTopics.contains(categoryId) {
                score += 2
            }

            if readArticleIds.contains(article.id) {
                score -= 100
            }

            guard score > -50 else { return nil }
            return ScoredRecommendation(article: article, score: score)
        }

        return scored.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return (lhs.article.lastPublished ?? "") > (rhs.article.lastPublished ?? "")
            }
            return lhs.score > rhs.score
        }
    }

    private func topicFrequency(from articles: [Article]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for article in articles {
            for topic in (article.topicsIDs ?? []) + [article.topicID].compactMap({ $0 }) {
                counts[topic, default: 0] += 1
            }
        }
        return counts
    }

    private func fetchReasons(for recommendations: [ScoredRecommendation], favorites: [Article]) async -> [String: String] {
        let topTopics = topicFrequency(from: favorites)
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        let candidates: [[String: Any]] = recommendations.map { scored in
            [
                "id": scored.article.id,
                "title": scored.article.name ?? "Artikel",
                "topics": (scored.article.topicsIDs ?? []) + [scored.article.topicID].compactMap { $0 }
            ]
        }

        guard !candidates.isEmpty,
              let url = SecureConfig.shared.recommendationReasonsURL else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "topTopics": Array(topTopics),
            "candidates": candidates
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return [:]
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.error("Recommendation reasons request failed: \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
                return [:]
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reasons = json["reasons"] as? [String: String] else {
                return [:]
            }
            return reasons
        } catch {
            logger.error("Recommendation reasons request error: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func defaultReason(for article: Article, favorites: [Article]) -> String {
        let favoriteTopics = Set(favorites.flatMap { ($0.topicsIDs ?? []) + [$0.topicID].compactMap { $0 } })
        let articleTopics = Set((article.topicsIDs ?? []) + [article.topicID].compactMap { $0 })
        if !favoriteTopics.intersection(articleTopics).isEmpty {
            return "Fordi det matcher dine favoritemner"
        }
        if let author = article.authorName {
            return "Fordi du følger \(author)"
        }
        return "Anbefalet til dig"
    }

    func trackRecommendationTap(article: Article, reason: String) {
        AnalyticsService.shared.trackRecommendationTap(articleId: article.id, reason: reason)
        AnalyticsService.shared.setPendingArticleOpenSource(.recommendation)
    }

    private func cache(_ recommendations: [(Article, String)]) {
        let payload = recommendations.map {
            CachedRecommendationEntry(article: $0.0, reason: $0.1)
        }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        }
    }

    private struct CachedRecommendationEntry: Codable {
        let article: Article
        let reason: String
    }
}
