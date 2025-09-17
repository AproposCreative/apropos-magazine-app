import Foundation
import SwiftUI

struct ReadingProgress: Codable, Identifiable {
    let id: String
    let articleId: String
    let userId: String
    let progress: Double // 0.0 - 1.0
    let timeSpent: TimeInterval
    let lastPosition: CGPoint
    let lastReadAt: Date
    let readingSpeed: Double // words per minute
    let completionStatus: CompletionStatus
    
    enum CompletionStatus: String, Codable, CaseIterable {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case completed = "completed"
        case bookmarked = "bookmarked"
        
        var displayName: String {
            switch self {
            case .notStarted: return "Ikke startet"
            case .inProgress: return "I gang"
            case .completed: return "Færdig"
            case .bookmarked: return "Bookmarket"
            }
        }
    }
    
    init(articleId: String, userId: String, progress: Double = 0.0, timeSpent: TimeInterval = 0, lastPosition: CGPoint = .zero, readingSpeed: Double = 0.0) {
        self.id = UUID().uuidString
        self.articleId = articleId
        self.userId = userId
        self.progress = max(0.0, min(1.0, progress))
        self.timeSpent = timeSpent
        self.lastPosition = lastPosition
        self.lastReadAt = Date()
        self.readingSpeed = readingSpeed
        self.completionStatus = progress >= 0.9 ? .completed : (progress > 0 ? .inProgress : .notStarted)
    }
}

struct EnhancedReadingStats: Codable {
    let totalArticlesRead: Int
    let totalTimeSpent: TimeInterval
    let averageReadingSpeed: Double
    let favoriteCategories: [String]
    let readingStreak: Int
    let weeklyGoal: Int
    let weeklyProgress: Int
    
    var averageTimePerArticle: TimeInterval {
        totalArticlesRead > 0 ? totalTimeSpent / Double(totalArticlesRead) : 0
    }
    
    var weeklyGoalProgress: Double {
        weeklyGoal > 0 ? Double(weeklyProgress) / Double(weeklyGoal) : 0
    }
    
    var formattedTotalTime: String {
        let hours = Int(totalTimeSpent) / 3600
        let minutes = Int(totalTimeSpent) % 3600 / 60
        return "\(hours)t \(minutes)m"
    }
}

@MainActor
class ReadingProgressManager: ObservableObject {
    @Published var currentProgress: ReadingProgress?
    @Published var readingStats: EnhancedReadingStats?
    @Published var isLoading = false
    
    static let shared = ReadingProgressManager()
    private let userDefaults = UserDefaults.standard
    private let progressKey = "reading_progress"
    private let statsKey = "reading_stats"
    
    private init() {
        loadReadingStats()
    }
    
    // MARK: - Progress Tracking
    
    func startReading(_ article: Article) {
        guard let user = UserManager.shared.currentUser else { return }
        
        let progress = ReadingProgress(
            articleId: article.id,
            userId: user.uid
        )
        
        currentProgress = progress
        saveProgress(progress)
    }
    
    func updateProgress(_ progress: Double, for articleId: String) {
        guard let current = currentProgress,
              current.articleId == articleId else { return }
        
        let newProgress = ReadingProgress(
            articleId: articleId,
            userId: current.userId,
            progress: progress,
            timeSpent: current.timeSpent + 1, // Increment time spent
            lastPosition: current.lastPosition,
            readingSpeed: calculateReadingSpeed(for: progress, timeSpent: current.timeSpent)
        )
        
        currentProgress = newProgress
        saveProgress(newProgress)
        
        // Update UserManager
        UserManager.shared.updateReadingProgress(progress, for: articleId)
    }
    
    func markAsCompleted(_ articleId: String) {
        updateProgress(1.0, for: articleId)
        HapticManager.shared.success()
    }
    
    func bookmarkArticle(_ articleId: String) {
        guard let current = currentProgress,
              current.articleId == articleId else { return }
        
        var newProgress = current
        newProgress = ReadingProgress(
            articleId: articleId,
            userId: current.userId,
            progress: current.progress,
            timeSpent: current.timeSpent,
            lastPosition: current.lastPosition,
            readingSpeed: current.readingSpeed
        )
        
        currentProgress = newProgress
        saveProgress(newProgress)
        
        HapticManager.shared.mediumImpact()
    }
    
    // MARK: - Statistics
    
    func loadReadingStats() {
        guard let data = userDefaults.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(EnhancedReadingStats.self, from: data) else {
            // Initialize default stats
            readingStats = EnhancedReadingStats(
                totalArticlesRead: 0,
                totalTimeSpent: 0,
                averageReadingSpeed: 0,
                favoriteCategories: [],
                readingStreak: 0,
                weeklyGoal: 5,
                weeklyProgress: 0
            )
            return
        }
        
        readingStats = stats
    }
    
    func updateReadingStats() {
        guard let user = UserManager.shared.currentUser else { return }
        
        // Calculate stats from UserManager data
        let readArticles = user.readArticles.count
        _ = user.bookmarkedArticles.count
        let totalTime = user.readingProgress.values.reduce(0, +) * 60 // Convert to seconds
        
        let stats = EnhancedReadingStats(
            totalArticlesRead: readArticles,
            totalTimeSpent: totalTime,
            averageReadingSpeed: 200, // Default WPM
            favoriteCategories: user.favoriteCategories,
            readingStreak: calculateReadingStreak(),
            weeklyGoal: 5,
            weeklyProgress: calculateWeeklyProgress()
        )
        
        readingStats = stats
        saveReadingStats(stats)
    }
    
    // MARK: - Private Methods
    
    private func saveProgress(_ progress: ReadingProgress) {
        // Save to UserDefaults for now, later to Firestore
        if let data = try? JSONEncoder().encode(progress) {
            userDefaults.set(data, forKey: "\(progressKey)_\(progress.articleId)")
        }
    }
    
    private func saveReadingStats(_ stats: EnhancedReadingStats) {
        if let data = try? JSONEncoder().encode(stats) {
            userDefaults.set(data, forKey: statsKey)
        }
    }
    
    private func calculateReadingSpeed(for progress: Double, timeSpent: TimeInterval) -> Double {
        guard timeSpent > 0 else { return 0 }
        // Estimate words read based on progress and calculate WPM
        return (progress * 500) / (timeSpent / 60) // Assuming average article is 500 words
    }
    
    private func calculateReadingStreak() -> Int {
        // Simple implementation - count consecutive days with reading activity
        return 3 // Placeholder
    }
    
    private func calculateWeeklyProgress() -> Int {
        // Count articles read this week
        return UserManager.shared.currentUser?.readArticles.count ?? 0
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func readingProgress(_ article: Article) -> some View {
        self.onAppear {
            ReadingProgressManager.shared.startReading(article)
        }
    }
}
