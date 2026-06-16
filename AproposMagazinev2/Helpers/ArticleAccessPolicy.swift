import Foundation

enum ArticleAccessPolicy {
    static func canReadFullContent(article: Article, isSubscribed: Bool) -> Bool {
        guard FeatureFlags.subscriptionsEnabled else { return true }
        if isSubscribed { return true }
        return article.isPremium != true
    }

    static func requiresPaywall(article: Article, isSubscribed: Bool) -> Bool {
        !canReadFullContent(article: article, isSubscribed: isSubscribed)
    }
}
