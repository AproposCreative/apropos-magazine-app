import Foundation

@MainActor
struct CategoryAnalytics {
    let viewModel: ArticleViewModel
    
    init(viewModel: ArticleViewModel) {
        self.viewModel = viewModel
    }
    
    // Get category statistics
    var categoryStats: [CategoryStat] {
        let stats = viewModel.topics.map { topic in
            let articles = viewModel.articles(for: topic.name)
            let favoriteCount = articles.filter { viewModel.isFavorite($0) }.count
            let averageRating = articles.compactMap { Double($0.stjerne ?? 0) }.reduce(0, +) / Double(max(articles.count, 1))
            
            return CategoryStat(
                name: topic.name,
                totalArticles: articles.count,
                favoriteCount: favoriteCount,
                averageRating: averageRating,
                lastUpdated: articles.compactMap { article in
                    var mutableArticle = article
                    return mutableArticle.publishedDate ?? mutableArticle.createdDate
                }.max()
            )
        }
        
        return stats.sorted { $0.totalArticles > $1.totalArticles }
    }
    
    // Get trending categories (categories with recent activity)
    var trendingCategories: [CategoryStat] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        return categoryStats.filter { stat in
            guard let lastUpdated = stat.lastUpdated else { return false }
            return lastUpdated > oneWeekAgo
        }.sorted { $0.lastUpdated ?? Date.distantPast > $1.lastUpdated ?? Date.distantPast }
    }
    
    // Get user's favorite categories
    var userFavoriteCategories: [CategoryStat] {
        let favoriteArticles = viewModel.articles.filter { viewModel.isFavorite($0) }
        let categoryCounts = Dictionary(grouping: favoriteArticles) { article in
            viewModel.categories(for: article).first ?? "Ukendt"
        }.mapValues { $0.count }
        
        return categoryStats.filter { stat in
            categoryCounts[stat.name] != nil
        }.sorted { categoryCounts[$0.name] ?? 0 > categoryCounts[$1.name] ?? 0 }
    }
    
    // Get category recommendations based on user behavior
    func getRecommendations() -> [CategoryStat] {
        // If user has favorites, recommend similar categories
        if !userFavoriteCategories.isEmpty {
            let favoriteCategoryNames = Set(userFavoriteCategories.map { $0.name })
            return categoryStats.filter { stat in
                !favoriteCategoryNames.contains(stat.name) && stat.totalArticles > 0
            }.prefix(3).map { $0 }
        }
        
        // Otherwise, recommend trending categories
        return Array(trendingCategories.prefix(3))
    }
    
    // Get category insights
    var insights: [CategoryInsight] {
        var insights: [CategoryInsight] = []
        
        // Most popular category
        if let mostPopular = categoryStats.first {
            insights.append(CategoryInsight(
                type: .mostPopular,
                title: "Mest populær kategori",
                description: "\(mostPopular.name) med \(mostPopular.totalArticles) artikler",
                categoryName: mostPopular.name
            ))
        }
        
        // Category with highest average rating
        if let highestRated = categoryStats.max(by: { $0.averageRating < $1.averageRating }),
           highestRated.averageRating > 0 {
            insights.append(CategoryInsight(
                type: .highestRated,
                title: "Bedst bedømt kategori",
                description: "\(highestRated.name) med \(String(format: "%.1f", highestRated.averageRating)) stjerner",
                categoryName: highestRated.name
            ))
        }
        
        // Trending category
        if let trending = trendingCategories.first {
            insights.append(CategoryInsight(
                type: .trending,
                title: "Trending kategori",
                description: "\(trending.name) har fået nye artikler",
                categoryName: trending.name
            ))
        }
        
        return insights
    }
}

struct CategoryStat {
    let name: String
    let totalArticles: Int
    let favoriteCount: Int
    let averageRating: Double
    let lastUpdated: Date?
    
    var popularityScore: Double {
        let baseScore = Double(totalArticles)
        let favoriteBonus = Double(favoriteCount) * 2.0
        let ratingBonus = averageRating * Double(totalArticles) * 0.5
        return baseScore + favoriteBonus + ratingBonus
    }
}

struct CategoryInsight {
    enum InsightType {
        case mostPopular
        case highestRated
        case trending
        case userFavorite
    }
    
    let type: InsightType
    let title: String
    let description: String
    let categoryName: String
}
