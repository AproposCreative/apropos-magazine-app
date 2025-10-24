import Foundation
import SwiftUI

@MainActor
class RecommendationEngine: ObservableObject {
    static let shared = RecommendationEngine()
    
    @Published var recommendations: [Article] = []
    @Published var isLoading = false
    
    private let userDefaults = UserDefaults.standard
    private let recommendationKey = "user_recommendations"
    private let lastUpdateKey = "recommendations_last_update"
    private var relatedArticlesCache: [String: [Article]] = [:]
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 hour
    
    private var cacheClearTimer: Timer? // Keep reference to invalidate
    
    private init() {
        loadRecommendations()
        
        // Clear cache periodically
        cacheClearTimer = Timer.scheduledTimer(withTimeInterval: cacheExpirationInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await MainActor.run {
                    self.clearCache()
                }
            }
        }
    }
    
    deinit {
        // Invalidate timer to avoid retain cycles and unexpected calls
        cacheClearTimer?.invalidate()
        cacheClearTimer = nil
        
        // Debug print for cleanup
        print("RecommendationEngine deinitialized and resources cleaned up")
        
        // If NotificationCenter observers or other listeners were added, remove here
        // (Currently none, but this is a good pattern)
    }
    
    // MARK: - Recommendation Generation
    
    func generateRecommendations(for user: UserProfile, from articles: [Article]) {
        isLoading = true
        
        Task { [weak self] in
            guard let self = self else { return }
            let recommendations = await self.calculateRecommendations(for: user, from: articles)
            self.recommendations = recommendations
            self.saveRecommendations(recommendations)
            self.isLoading = false
        }
    }
    
    private func calculateRecommendations(for user: UserProfile, from articles: [Article]) async -> [Article] {
        var scoredArticles: [(article: Article, score: Double)] = []
        
        for article in articles {
            let score = calculateArticleScore(article, for: user)
            scoredArticles.append((article: article, score: score))
        }
        
        // Sort by score and return top recommendations
        return scoredArticles
            .sorted { $0.score > $1.score }
            .prefix(10)
            .map { $0.article }
    }
    
    private func calculateArticleScore(_ article: Article, for user: UserProfile) -> Double {
        var score: Double = 0
        
        // Category preference (40% weight)
        if let topicId = article.topicID,
           user.favoriteCategories.contains(topicId) {
            score += 0.4
        }
        
        // Author preference (30% weight)
        if let authorId = article.authorID,
           user.favoriteAuthors.contains(authorId) {
            score += 0.3
        }
        
        // Recency bonus (20% weight)
        let recencyScore = calculateRecencyScore(for: article)
        score += recencyScore * 0.2
        
        // Popularity bonus (10% weight)
        let popularityScore = calculatePopularityScore(for: article)
        score += popularityScore * 0.1
        
        // Avoid already read articles
        if user.readArticles.contains(article.id) {
            score *= 0.1 // Reduce score significantly
        }
        
        return score
    }
    
    private func calculateRecencyScore(for article: Article) -> Double {
        // Simple recency scoring - newer articles get higher scores
        // This would be enhanced with actual publication dates
        return 0.8 // Placeholder
    }
    
    private func calculatePopularityScore(for article: Article) -> Double {
        // Simple popularity scoring based on rating
        return min(Double(article.rating) / 5.0, 1.0)
    }
    
    // MARK: - Specialized Recommendations
    
    func getTrendingArticles(from articles: [Article]) -> [Article] {
        return articles
            .sorted { $0.rating > $1.rating }
            .prefix(5)
            .map { $0 }
    }
    
    func getRelatedArticles(to article: Article, from articles: [Article]) -> [Article] {
        // Safety check: ensure we have valid input
        guard !articles.isEmpty else {
            return []
        }
        
        // Check cache first
        let cacheKey = "\(article.id)_\(articles.count)"
        if let cachedArticles = relatedArticlesCache[cacheKey] {
            return cachedArticles
        }
        
        var relatedArticles: [(article: Article, similarity: Double)] = []
        
        for otherArticle in articles {
            guard otherArticle.id != article.id else { continue }
            
            var similarity = calculateSimilarity(between: article, and: otherArticle)
            
            // Boost articles with higher ratings
            let rating = otherArticle.rating
            similarity += Double(rating) * 0.05 // Small boost for highly rated articles
            
            // Boost recent articles slightly (using createdOn if available)
            if let createdOn = otherArticle.createdOn {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let createdAt = formatter.date(from: createdOn) {
                    let daysSinceCreation = Date().timeIntervalSince(createdAt) / (24 * 60 * 60)
                    if daysSinceCreation < 30 { // Articles from last 30 days
                        similarity += 0.1
                    }
                }
            }
            
            relatedArticles.append((article: otherArticle, similarity: similarity))
        }
        
        let result = relatedArticles
            .sorted { $0.similarity > $1.similarity }
            .prefix(5)
            .map { $0.article }
        
        // Cache the result
        relatedArticlesCache[cacheKey] = result
        
        return result
    }
    
    private func calculateSimilarity(between article1: Article, and article2: Article) -> Double {
        var similarity: Double = 0
        
        // Category similarity (40% weight)
        if let topic1 = article1.topicID, let topic2 = article2.topicID, topic1 == topic2 {
            similarity += 0.4
        }
        
        // Author similarity (30% weight)
        if let author1 = article1.authorID, let author2 = article2.authorID, author1 == author2 {
            similarity += 0.3
        }
        
        // Topic similarity (20% weight)
        let topics1 = Set(article1.topicsIDs ?? [])
        let topics2 = Set(article2.topicsIDs ?? [])
        let topicOverlap = topics1.intersection(topics2).count
        similarity += Double(topicOverlap) * 0.2
        
        // Content similarity based on keywords (10% weight)
        let contentSimilarity = calculateContentSimilarity(between: article1, and: article2)
        similarity += contentSimilarity * 0.1
        
        return similarity
    }
    
    private func calculateContentSimilarity(between article1: Article, and article2: Article) -> Double {
        var similarity: Double = 0
        
        // Extract keywords from titles and intros with proper nil checking
        let title1 = article1.name?.lowercased() ?? ""
        let title2 = article2.name?.lowercased() ?? ""
        let intro1 = article1.intro?.lowercased() ?? ""
        let intro2 = article2.intro?.lowercased() ?? ""
        
        // Safety check: if both titles and intros are empty, return 0 similarity
        guard !title1.isEmpty || !title2.isEmpty || !intro1.isEmpty || !intro2.isEmpty else {
            return 0.0
        }
        
        // Common Danish keywords for content matching
        let keywords = ["festival", "koncert", "musik", "film", "bog", "kunst", "teater", "kultur", "anmeldelse", "interview", "live", "optræden", "show", "udstilling", "premiere", "album", "single", "tour", "tourne", "album", "ep", "mixtape", "remix", "cover", "original", "dansk", "international", "pop", "rock", "jazz", "klassisk", "elektronisk", "folk", "country", "hiphop", "rap", "soul", "r&b", "metal", "punk", "indie", "alternative"]
        
        let title1Words = Set(title1.components(separatedBy: .whitespacesAndNewlines))
        let title2Words = Set(title2.components(separatedBy: .whitespacesAndNewlines))
        let intro1Words = Set(intro1.components(separatedBy: .whitespacesAndNewlines))
        let intro2Words = Set(intro2.components(separatedBy: .whitespacesAndNewlines))
        
        // Count keyword matches
        var keywordMatches = 0
        for keyword in keywords {
            if title1Words.contains(keyword) && (title2Words.contains(keyword) || intro2Words.contains(keyword)) {
                keywordMatches += 1
            }
            if intro1Words.contains(keyword) && (title2Words.contains(keyword) || intro2Words.contains(keyword)) {
                keywordMatches += 1
            }
        }
        
        // Normalize similarity score
        similarity = min(Double(keywordMatches) / 10.0, 1.0)
        
        return similarity
    }
    
    func getPersonalizedFeed(for user: UserProfile, from articles: [Article]) async -> [Article] {
        // Mix of recommendations and trending content
        let recommended = await calculateRecommendations(for: user, from: articles)
        let trending = getTrendingArticles(from: articles)
        
        var personalizedFeed: [Article] = []
        
        // Add 60% recommended, 40% trending
        let recommendedCount = min(6, recommended.count)
        let trendingCount = min(4, trending.count)
        
        personalizedFeed.append(contentsOf: recommended.prefix(recommendedCount))
        personalizedFeed.append(contentsOf: trending.prefix(trendingCount))
        
        return personalizedFeed
    }
    
    // MARK: - Festival & Event Recommendations
    
    func getFestivalRecommendations(from articles: [Article]) -> [Article] {
        let festivalKeywords = ["festival", "koncert", "live", "optræden", "show"]
        
        return articles.filter { article in
            let title = article.name?.lowercased() ?? ""
            let intro = article.intro?.lowercased() ?? ""
            let content = article.content?.lowercased() ?? ""
            
            return festivalKeywords.contains { keyword in
                title.contains(keyword) || intro.contains(keyword) || content.contains(keyword)
            }
        }
    }
    
    func getSeasonalRecommendations(from articles: [Article]) -> [Article] {
        let currentMonth = Calendar.current.component(.month, from: Date())
        
        // Simple seasonal categorization
        let seasonalKeywords: [String] = {
            switch currentMonth {
            case 12, 1, 2: return ["vinter", "jul", "nytår", "kold"]
            case 3, 4, 5: return ["forår", "vår", "blomst", "ny"]
            case 6, 7, 8: return ["sommer", "festival", "sol", "varm"]
            case 9, 10, 11: return ["efterår", "høst", "regne", "kold"]
            default: return []
            }
        }()
        
        return articles.filter { article in
            let title = article.name?.lowercased() ?? ""
            let intro = article.intro?.lowercased() ?? ""
            
            return seasonalKeywords.contains { keyword in
                title.contains(keyword) || intro.contains(keyword)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveRecommendations(_ recommendations: [Article]) {
        if let data = try? JSONEncoder().encode(recommendations) {
            userDefaults.set(data, forKey: recommendationKey)
            userDefaults.set(Date(), forKey: lastUpdateKey)
        }
    }
    
    private func loadRecommendations() {
        guard let data = userDefaults.data(forKey: recommendationKey),
              let recommendations = try? JSONDecoder().decode([Article].self, from: data) else {
            return
        }
        
        self.recommendations = recommendations
    }
    
    func shouldUpdateRecommendations() -> Bool {
        guard let lastUpdate = userDefaults.object(forKey: lastUpdateKey) as? Date else {
            return true
        }
        
        let hoursSinceUpdate = Date().timeIntervalSince(lastUpdate) / 3600
        return hoursSinceUpdate > 24 // Update daily
    }
    
    private func clearCache() {
        relatedArticlesCache.removeAll()
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func withRecommendations() -> some View {
        self.environmentObject(RecommendationEngine.shared)
    }
}

// MARK: - Recommendation Views

struct RecommendationSection: View {
    let title: String
    let articles: [Article]
    let onArticleTap: (Article) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(articles) { article in
                        RecommendationCard(article: article)
                            .onTapGesture {
                                onArticleTap(article)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct RecommendationCard: View {
    let article: Article
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            var mutableArticle = article
            if let url = URL(string: mutableArticle.thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    SkeletonView()
                }
                .frame(width: 200, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Title
            Text(mutableArticle.name ?? "")
                .font(.headline)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // Category
            if let topicId = mutableArticle.topicID {
                Text(topicId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .frame(width: 200)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

