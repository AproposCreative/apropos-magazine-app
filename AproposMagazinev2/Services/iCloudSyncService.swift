import Foundation

@MainActor
final class iCloudSyncService: ObservableObject {
    static let shared = iCloudSyncService()

    private let store = NSUbiquitousKeyValueStore.default
    private let readArticlesKey = "readArticleIds"
    private let readingProgressKey = "readingProgress"
    private let maxReadArticles = 200

    @Published private(set) var readArticleIds: [String] = []
    @Published private(set) var readingProgress: [String: Double] = [:]

    private var progressPersistTask: Task<Void, Never>?

    private init() {
        loadFromStore()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func markAsRead(articleId: String) {
        guard !articleId.isEmpty else { return }
        if !readArticleIds.contains(articleId) {
            readArticleIds.append(articleId)
            if readArticleIds.count > maxReadArticles {
                readArticleIds = Array(readArticleIds.suffix(maxReadArticles))
            }
            persistReadArticles()
        }
        if UserManager.shared.currentUser != nil {
            UserManager.shared.markArticleAsRead(articleId)
        }
    }

    func saveProgress(_ progress: Double, for articleId: String) {
        guard !articleId.isEmpty else { return }
        let clamped = min(max(progress, 0), 1)

        if let existing = readingProgress[articleId], abs(existing - clamped) < 0.02 {
            return
        }

        readingProgress[articleId] = clamped
        scheduleReadingProgressPersist()
    }

    private func scheduleReadingProgressPersist() {
        progressPersistTask?.cancel()
        progressPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            persistReadingProgress()
        }
    }

    func getProgress(for articleId: String) -> Double? {
        readingProgress[articleId]
    }

    func hasRead(articleId: String) -> Bool {
        readArticleIds.contains(articleId)
    }

    private func loadFromStore() {
        if let ids = store.array(forKey: readArticlesKey) as? [String] {
            readArticleIds = ids
        }
        if let progress = store.dictionary(forKey: readingProgressKey) as? [String: Double] {
            readingProgress = progress
        }
    }

    private func persistReadArticles() {
        store.set(readArticleIds, forKey: readArticlesKey)
        store.synchronize()
    }

    private func persistReadingProgress() {
        store.set(readingProgress, forKey: readingProgressKey)
        store.synchronize()
    }

    @objc private func handleExternalChange(_ notification: Notification) {
        loadFromStore()
        NotificationCenter.default.post(name: .iCloudReadingDataDidChange, object: nil)
    }
}

extension Notification.Name {
    static let iCloudReadingDataDidChange = Notification.Name("iCloudReadingDataDidChange")
}
