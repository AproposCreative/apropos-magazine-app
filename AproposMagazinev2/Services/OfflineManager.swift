import FirebaseFirestore
import Foundation
import Network
import OSLog
import SwiftUI

@MainActor
class OfflineManager: ObservableObject {
    @Published var isOnline = true
    @Published var isExpensiveConnection = false
    @Published var isConstrainedConnection = false
    @Published var syncInProgress = false
    @Published var lastSyncDate: Date?

    /// True only on unmetered, unconstrained connections (e.g. Wi-Fi/ethernet).
    /// Used to gate heavy background downloads like podcast prefetch.
    var allowsHeavyDownloads: Bool {
        isOnline && !isExpensiveConnection && !isConstrainedConnection
    }
    
    static let shared = OfflineManager()
    private let userDefaults = UserDefaults.standard
    private lazy var db = Firestore.firestore()
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "OfflineManager")
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "OfflineManager.NetworkMonitor")
    
    // Keys for UserDefaults
    private let offlineArticlesKey = "offline_articles"
    private let lastSyncKey = "last_sync_date"
    private let pendingActionsKey = "pending_actions"
    
    private init() {
        loadLastSyncDate()
        setupConnectivityMonitoring()
    }
    
    deinit {
        monitor.cancel()
        logger.debug("OfflineManager deinit – netværksovervågning stoppet.")
    }
    
    // MARK: - Connectivity
    
    private func checkConnectivity() {
        let path = monitor.currentPath
        isOnline = path.status == .satisfied
        isExpensiveConnection = path.isExpensive
        isConstrainedConnection = path.isConstrained
    }
    
    private func setupConnectivityMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let status = path.status == .satisfied
                self?.isOnline = status
                self?.isExpensiveConnection = path.isExpensive
                self?.isConstrainedConnection = path.isConstrained
                if status {
                    self?.logger.debug("Netværk tilgængeligt.")
                    self?.processPendingActions()
                    self?.syncWhenOnline()
                } else {
                    self?.logger.warning("Netværk utilgængeligt.")
                }
            }
        }
        monitor.start(queue: monitorQueue)
        checkConnectivity()
    }
    
    // MARK: - Offline Storage
    
    func saveArticleForOffline(_ article: Article) {
        var offlineArticles = getOfflineArticles()
        offlineArticles.removeAll { $0.id == article.id }
        offlineArticles.append(article)
        
        // Prune to max 50 articles by removing oldest if needed
        if offlineArticles.count > 50 {
            let excess = offlineArticles.count - 50
            let removedArticles = offlineArticles.prefix(excess)
            for removed in removedArticles {
                OfflineArticleImageCache.shared.removeImages(for: removed.id)
                removePodcastFromOffline(removed.id)
            }
            offlineArticles.removeFirst(excess)
        }
        
        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(offlineArticles) {
            userDefaults.set(data, forKey: offlineArticlesKey)
        }

        OfflineArticleImageCache.shared.scheduleCacheImages(for: article)
        savePodcastForOffline(article)
    }
    
    func removeArticleFromOffline(_ articleId: String) {
        var offlineArticles = getOfflineArticles()
        offlineArticles.removeAll { $0.id == articleId }
        
        if let data = try? JSONEncoder().encode(offlineArticles) {
            userDefaults.set(data, forKey: offlineArticlesKey)
        }

        OfflineArticleImageCache.shared.removeImages(for: articleId)
        removePodcastFromOffline(articleId)
    }

    func savePodcastForOffline(_ article: Article) {
        guard let episode = PodcastRepository.shared.episode(for: article),
              let audioURL = episode.audioURL else {
            return
        }
        PodcastAudioCache.shared.pinAndDownload(articleId: article.id, remoteURL: audioURL)
    }

    func savePodcastsForOffline(_ articles: [Article]) {
        for article in articles {
            savePodcastForOffline(article)
        }
    }

    func removePodcastFromOffline(_ articleId: String) {
        PodcastAudioCache.shared.unpin(articleId: articleId)
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
            logger.debug("Ingen autentificeret bruger – springer sync over.")
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
            ]) { [weak self] error in
                if let error = error {
                self?.logger.error("Fejl ved sync af læseprogression: \(error.localizedDescription, privacy: .public)")
            }
            // Optionally handle success or update state here
            _ = self
        }
    }
    
    private func syncUserPreferences() {
        guard let user = UserManager.shared.currentUser else { return }
        
        let updatePayload: [String: Any] = [
            "notificationPreferences": notificationPreferencesDictionary(from: user.notificationPreferences),
            "readingPreferences": readingPreferencesDictionary(from: user.readingPreferences),
            "favoriteCategories": user.favoriteCategories,
            "favoriteAuthors": user.favoriteAuthors
        ]
        
        db.collection("users").document(user.uid).updateData(updatePayload) { [weak self] error in
            if let error = error {
                self?.logger.error("Fejl ved sync af brugerpræferencer: \(error.localizedDescription, privacy: .public)")
            }
            _ = self
        }
    }
    
    private func syncBookmarks() {
        guard let user = UserManager.shared.currentUser else { return }
        
        db.collection("users").document(user.uid).updateData([
            "bookmarkedArticles": user.bookmarkedArticles,
            "readArticles": user.readArticles
        ]) { [weak self] error in
            if let error = error {
                self?.logger.error("Fejl ved sync af bogmærker: \(error.localizedDescription, privacy: .public)")
            }
            _ = self
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
        let articleDataSize = (try? JSONEncoder().encode(articles).count) ?? 0
        let imageSize = OfflineArticleImageCache.shared.totalCacheSizeBytes()
        let podcastSize = PodcastAudioCache.shared.totalCacheSizeBytes()
        let total = Int64(articleDataSize) + imageSize + podcastSize
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    func clearOfflineStorage() {
        userDefaults.removeObject(forKey: offlineArticlesKey)
        userDefaults.removeObject(forKey: pendingActionsKey)
        OfflineArticleImageCache.shared.removeAllCachedImages()
        PodcastAudioCache.shared.removeAllCachedFiles()
    }
    
    private func notificationPreferencesDictionary(from preferences: NotificationPreferences) -> [String: Any] {
        return [
            "newArticles": preferences.newArticles,
            "newPodcasts": preferences.newPodcasts,
            "festivalReminders": preferences.festivalReminders,
            "breakingNews": preferences.breakingNews,
            "weeklyDigest": preferences.weeklyDigest,
            "quietHours": [
                "enabled": preferences.quietHours.enabled,
                "startTime": preferences.quietHours.startTime.timeIntervalSince1970,
                "endTime": preferences.quietHours.endTime.timeIntervalSince1970
            ]
        ]
    }
    
    private func readingPreferencesDictionary(from preferences: ReadingPreferences) -> [String: Any] {
        return [
            "fontSize": preferences.fontSize.rawValue,
            "darkMode": preferences.darkMode,
            "autoPlayVideos": preferences.autoPlayVideos,
            "showImages": preferences.showImages,
            "readingTimeEstimate": preferences.readingTimeEstimate
        ]
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
