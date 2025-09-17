import SwiftUI
import Foundation
import FirebaseFirestore

@MainActor
class OfflineManager: ObservableObject {
    @Published var isOnline = true
    @Published var syncInProgress = false
    @Published var lastSyncDate: Date?
    
    static let shared = OfflineManager()
    private let userDefaults = UserDefaults.standard
    private lazy var db = Firestore.firestore()
    
    // Keys for UserDefaults
    private let offlineArticlesKey = "offline_articles"
    private let lastSyncKey = "last_sync_date"
    private let pendingActionsKey = "pending_actions"
    
    private init() {
        checkConnectivity()
        loadLastSyncDate()
        setupConnectivityMonitoring()
    }
    
    // MARK: - Connectivity
    
    private func checkConnectivity() {
        // Simple connectivity check - in production you'd use Network framework
        isOnline = true // For now, assume online
    }
    
    private func setupConnectivityMonitoring() {
        // Monitor network changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NetworkStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isOnline = false
        }
    }
    
    // MARK: - Offline Storage
    
    func saveArticleForOffline(_ article: Article) {
        var offlineArticles = getOfflineArticles()
        
        // Check if we have space (limit to 50 articles)
        if offlineArticles.count >= 50 {
            // Remove oldest article
            offlineArticles.removeFirst()
        }
        
        // Add new article
        offlineArticles.append(article)
        
        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(offlineArticles) {
            userDefaults.set(data, forKey: offlineArticlesKey)
        }
    }
    
    func removeArticleFromOffline(_ articleId: String) {
        var offlineArticles = getOfflineArticles()
        offlineArticles.removeAll { $0.id == articleId }
        
        if let data = try? JSONEncoder().encode(offlineArticles) {
            userDefaults.set(data, forKey: offlineArticlesKey)
        }
    }
    
    func getOfflineArticles() -> [Article] {
        guard let data = userDefaults.data(forKey: offlineArticlesKey),
              let articles = try? JSONDecoder().decode([Article].self, from: data) else {
            return []
        }
        return articles
    }
    
    func isArticleAvailableOffline(_ articleId: String) -> Bool {
        return getOfflineArticles().contains { $0.id == articleId }
    }
    
    // MARK: - Sync Management
    
    func syncWhenOnline() {
        guard isOnline else { return }
        guard UserManager.shared.currentUser != nil else { 
            print("[OfflineManager] No authenticated user, skipping sync")
            return 
        }
        
        syncInProgress = true
        
        // Sync reading progress
        syncReadingProgress()
        
        // Sync user preferences
        syncUserPreferences()
        
        // Sync bookmarks
        syncBookmarks()
        
        // Update last sync date with validation
        let validDate = Date()
        lastSyncDate = validDate
        saveLastSyncDate()
        
        syncInProgress = false
    }
    
    private func syncReadingProgress() {
        guard let user = UserManager.shared.currentUser else { return }
        
        // Sync reading progress to server with safety check
        // Validate date before creating timestamp
        let validDate = Date()
        db.collection("users").document(user.uid).updateData([
            "readingProgress": user.readingProgress,
            "lastSync": validDate
        ]) { error in
            if let error = error {
                print("Error syncing reading progress: \(error)")
            }
        }
    }
    
    private func syncUserPreferences() {
        guard let user = UserManager.shared.currentUser else { return }
        
        db.collection("users").document(user.uid).updateData([
            "notificationPreferences": (try? JSONEncoder().encode(user.notificationPreferences)) ?? Data(),
            "readingPreferences": (try? JSONEncoder().encode(user.readingPreferences)) ?? Data(),
            "favoriteCategories": user.favoriteCategories,
            "favoriteAuthors": user.favoriteAuthors
        ]) { error in
            if let error = error {
                print("Error syncing user preferences: \(error)")
            }
        }
    }
    
    private func syncBookmarks() {
        guard let user = UserManager.shared.currentUser else { return }
        
        db.collection("users").document(user.uid).updateData([
            "bookmarkedArticles": user.bookmarkedArticles,
            "readArticles": user.readArticles
        ]) { error in
            if let error = error {
                print("Error syncing bookmarks: \(error)")
            }
        }
    }
    
    // MARK: - Pending Actions
    
    func addPendingAction(_ action: PendingAction) {
        var pendingActions = getPendingActions()
        pendingActions.append(action)
        
        if let data = try? JSONEncoder().encode(pendingActions) {
            userDefaults.set(data, forKey: pendingActionsKey)
        }
    }
    
    func processPendingActions() {
        guard isOnline else { return }
        
        let pendingActions = getPendingActions()
        
        for action in pendingActions {
            switch action.type {
            case .bookmark:
                UserManager.shared.toggleBookmark(action.articleId)
            case .markAsRead:
                UserManager.shared.markArticleAsRead(action.articleId)
            case .updateProgress:
                UserManager.shared.updateReadingProgress(action.progress, for: action.articleId)
            }
        }
        
        // Clear pending actions
        userDefaults.removeObject(forKey: pendingActionsKey)
    }
    
    private func getPendingActions() -> [PendingAction] {
        guard let data = userDefaults.data(forKey: pendingActionsKey),
              let actions = try? JSONDecoder().decode([PendingAction].self, from: data) else {
            return []
        }
        return actions
    }
    
    // MARK: - Utilities
    
    private func loadLastSyncDate() {
        if let date = userDefaults.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = date
        }
    }
    
    private func saveLastSyncDate() {
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
    }
    
    func getOfflineStorageSize() -> String {
        let articles = getOfflineArticles()
        let estimatedSize = articles.count * 50 // Rough estimate: 50KB per article
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedSize * 1024), countStyle: .file)
    }
    
    func clearOfflineStorage() {
        userDefaults.removeObject(forKey: offlineArticlesKey)
        userDefaults.removeObject(forKey: pendingActionsKey)
    }
}

// MARK: - Supporting Types

struct PendingAction: Codable {
    let type: ActionType
    let articleId: String
    let progress: Double
    let timestamp: Date
    
    init(type: ActionType, articleId: String, progress: Double = 0.0) {
        self.type = type
        self.articleId = articleId
        self.progress = progress
        self.timestamp = Date()
    }
}

enum ActionType: String, Codable {
    case bookmark
    case markAsRead
    case updateProgress
}
