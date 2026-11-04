import Foundation

@MainActor
final class RecommendationService {
    static let shared = RecommendationService()
    private init() {}
    /// The caller owns the immutable input and commit ticket. No persistent
    /// recommendation cache can outlive an account/history change.
    func generateRecommendations(input: RecommendationHistoryInput) async -> [(Article, String)] {
        await Task.detached(priority: .userInitiated) {
            ReaderRecommendationPolicy.recommendations(
                articles: input.articles, favorites: input.favorites, interestTopicIDs: input.interestTopicIDs,
                readArticleIDs: input.readArticleIDs
            )
        }.value
    }

    func trackRecommendationTap(article: Article, reason: String) {
        AnalyticsService.shared.trackRecommendationTap(articleId: article.id, reason: reason)
        AnalyticsService.shared.setPendingArticleOpenSource(.recommendation)
    }

}
