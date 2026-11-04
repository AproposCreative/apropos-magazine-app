import Foundation
import UIKit
import SDWebImage
import SwiftUI
import WidgetKit

@MainActor
class CacheManager: ObservableObject {
    static let shared = CacheManager()
    
    @Published var cacheSize: String = "0 MB"
    @Published var isClearingCache = false
    
    private let userDefaults: UserDefaults
    private let injectedAvailability: ArticleAvailabilityModel?
    private let feedPersistence: (([Article], Bool, Date) -> Void)?
    private var availability: ArticleAvailabilityModel { injectedAvailability ?? ArticleAvailabilityService.model }
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    // Cache keys
    private let articlesCacheKey = "cached_articles"
    private let imagesCacheKey = "cached_images"
    private let lastCacheUpdateKey = "last_cache_update"
    private let topicsCacheKey = "cached_topics"
    private let sectionsCacheKey = "cached_sections"
    private let authorsCacheKey = "cached_authors"
    private let starsCacheKey = "cached_stars"
    /// Bumped when feed cache stops storing full HTML bodies (metadata-only).
    private static let articlesCacheVersion = "1.3"
    
    // Cache policies
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB
    private let maxArticleAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let maxImageAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let maxMetadataAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days (topics, sections, authors, stars)

    // Cached decoded articles to avoid repeated decoding
    private var cachedArticles: [Article]?
    private var cachedArticlesAreSorted = false
    private var cachedArticlesTimestamp: Date?
    private var articleMutation = UUID()
    private let articleCacheWorker = ArticleCacheDecodeWorker()
    private let directorySizeWorker = CacheDirectorySizeWorker()
    private lazy var articleHydration = ArticleCacheHydrationCoordinator(
        version: CacheManager.articlesCacheVersion,
        maximumAge: maxArticleAge,
        read: { [weak self] in
            guard let self else { return nil }
            if let articles = self.cachedArticles, let timestamp = self.cachedArticlesTimestamp {
                return .memory(articles: articles, timestamp: timestamp, articlesAreSorted: self.cachedArticlesAreSorted)
            }
            return self.userDefaults.data(forKey: self.articlesCacheKey).map(ArticleCacheHydrationCoordinator.Source.encoded)
        },
        prepare: { [articleCacheWorker] source, policy in await articleCacheWorker.prepare(source, policy: policy) }
    )
    private let widgetSnapshotWorker = WidgetFeedSnapshotWorker()
    private lazy var widgetFeedSync = WidgetFeedSyncCoordinator(
        prepare: { [widgetSnapshotWorker] source in
            try await widgetSnapshotWorker.prepare(source)
        },
        persist: { WidgetDataStore.saveLatestArticles($0, reloadTimelines: true) },
        cacheImages: { articles in
            let prepared = await WidgetImageStore.prepareImages(for: articles)
            return WidgetFeedImageUpdate {
                WidgetImageStore.commitPreparedImages(prepared)
            }
        },
        reloadImages: { WidgetCenter.shared.reloadAllTimelines() }
    )

    init(userDefaults: UserDefaults = .standard, cacheDirectory: URL? = nil,
         availabilityModel: ArticleAvailabilityModel? = nil,
         feedPersistence: (([Article], Bool, Date) -> Void)? = nil) {
        self.userDefaults = userDefaults
        self.injectedAvailability = availabilityModel
        self.feedPersistence = feedPersistence
        // Get cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        if let location = cacheDirectory ?? paths.first?.appendingPathComponent("AproposMagazine") {
            self.cacheDirectory = location
        } else {
            // Fallback to temporary directory if cachesDirectory is not found
            self.cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AproposMagazine")
        }
        
        // Create cache directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        } catch {
        }
        
        // Add memory warning observer to trigger cache cleanup when needed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleMemoryWarning() {
        // When memory warning is received, update cache size and perform cleanup if needed
        Task { @MainActor in
            await self.updateCacheSize()
            // Extract digits safely from cacheSize string for comparison
            let digitsOnly = cacheSize.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let size = Int64(digitsOnly), size > maxCacheSize {
                self.cleanupCache()
            }
        }
    }
    
    // MARK: - Article Caching

    func syncWidgetFeed(from articles: [Article], articlesAreSorted: Bool = false,
                        language: ArticleContentLanguage? = nil) {
        let language = language ?? PreferencesManager.shared.articleLanguage
        // The same accepted device choice drives widget chrome and read-side
        // filtering, including an empty English feed. Existing data is retained.
        if let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupID),
           defaults.string(forKey: WidgetDataStore.interfaceLanguageKey) != language.rawValue {
            defaults.set(language.rawValue, forKey: WidgetDataStore.interfaceLanguageKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
        widgetFeedSync.sync(WidgetFeedSource(
            articles: articles.filter { $0.hasValidContentIdentity
                && $0.contentLanguage == language
                && availability.permitsBody($0) },
            topics: getCachedTopics() ?? [],
            articlesAreSorted: articlesAreSorted
        ))
    }

    func syncCachedWidgetFeed(_ original: ArticleCacheHydrationCoordinator.Capture) async {
        let outcome = await loadCapturedArticles(original)
        guard isCurrentArticleRead(original), case .ready(let prepared) = outcome, !prepared.articles.isEmpty else { return }
        syncWidgetFeed(from: prepared.articles, articlesAreSorted: prepared.articlesAreSorted)
    }

    private func topicName(for article: Article, topics: [Topic]) -> String {
        if let topicID = article.topicID,
           let topic = topics.first(where: { $0.id == topicID }) {
            return topic.name
        }

        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = topics.first(where: { $0.id == topicID }) {
                    return topic.name
                }
            }
        }

        return ""
    }
    
    func cacheArticles(_ articles: [Article], articlesAreSorted: Bool = false, timestamp: Date = Date()) {
        invalidateArticleReads()
        storeArticles(articles, articlesAreSorted: articlesAreSorted, timestamp: timestamp)
    }

    /// A denial removes metadata without granting fresh age or superseding an
    /// in-flight catalog baseline. Every read still projects current availability.
    /// Ordinary writes/clears retain their original epoch invalidation.
    func pruneUnavailableArticleMetadata() {
        guard let cachedArticles, let timestamp = cachedArticlesTimestamp else { return }
        let retained = cachedArticles.filter { availability.permitsBody($0) }
        guard retained.count != cachedArticles.count else { return }
        articleMutation = UUID()
        widgetFeedSync.invalidate()
        storeArticles(retained, articlesAreSorted: cachedArticlesAreSorted, timestamp: timestamp)
    }

    private func storeArticles(_ articles: [Article], articlesAreSorted: Bool, timestamp: Date) {
        let mutation = articleMutation
        let publishedArticles = articles
            .filter { availability.permitsBody($0) }
            .map { $0.strippingBodyContent() }
        let cacheData = CacheData(
            articles: publishedArticles,
            timestamp: timestamp,
            version: Self.articlesCacheVersion
        )

        do {
            let data = try JSONEncoder().encode(cacheData)
            guard articleMutation == mutation else { return }

            // The existing cache write remains on its platform owner. A nested
            // clear/new write cannot resume this older mutation's later effects.
            userDefaults.set(data, forKey: articlesCacheKey)
            guard articleMutation == mutation else { return }
            userDefaults.set(cacheData.timestamp, forKey: lastCacheUpdateKey)
            guard articleMutation == mutation else { return }
            cachedArticles = publishedArticles
            cachedArticlesTimestamp = cacheData.timestamp
            cachedArticlesAreSorted = articlesAreSorted
            if let feedPersistence {
                feedPersistence(publishedArticles, articlesAreSorted, timestamp)
                return
            }
            syncWidgetFeed(from: publishedArticles, articlesAreSorted: articlesAreSorted)
            guard articleMutation == mutation else { return }

            // ALSO save to App Group UserDefaults (for Notification Service Extension)
            // This allows the extension to check if articles are already published
            guard let appGroupDefaults = UserDefaults(suiteName: "group.com.aproposmagazine.app") else {
                return
            }

            // Create simplified cache data for extension (id, name, lastPublished, createdOn)
            // Name is included for fallback search when article_id is missing from notifications
            let cachedTopics = getCachedTopics() ?? []
            guard articleMutation == mutation else { return }
            let simplifiedArticles = publishedArticles.map { article -> [String: String] in
                let thumbURL = (article.thumbURL ?? article.mobileImageURL ?? article.coverURL)?.absoluteString ?? ""
                let topic = topicName(for: article, topics: cachedTopics)
                return [
                    "id": article.id,
                    "name": article.name ?? "",
                    "slug": article.slug ?? article.id,
                    "thumbURL": thumbURL,
                    "stjerne": article.stjerne.map(String.init) ?? "",
                    "topic": topic,
                    "lastPublished": article.lastPublished ?? "",
                    "createdOn": article.createdOn ?? "",
                ]
            }
            let simplifiedCacheData: [String: Any] = [
                "articles": simplifiedArticles,
                "timestamp": timestamp.timeIntervalSince1970,
                "version": Self.articlesCacheVersion
            ]

            do {
                guard JSONSerialization.isValidJSONObject(simplifiedCacheData) else {
                    return
                }
                let simplifiedData = try JSONSerialization.data(withJSONObject: simplifiedCacheData)
                guard articleMutation == mutation else { return }
                appGroupDefaults.set(simplifiedData, forKey: articlesCacheKey)
                guard articleMutation == mutation else { return }
                appGroupDefaults.set(cacheData.timestamp, forKey: lastCacheUpdateKey)
                guard articleMutation == mutation else { return }
                appGroupDefaults.synchronize()
            } catch {
            }

        } catch {
        }
    }
    
    /// A synchronous consumer may read already hydrated memory only. Cold disk
    /// decoding belongs to the captured async pipeline below.
    func getCachedArticles() -> [Article]? {
        let mutation = articleMutation
        guard let cachedArticles, let timestamp = cachedArticlesTimestamp else { return nil }
        guard Date().timeIntervalSince(timestamp) < maxArticleAge else { clearArticlesCache(); return nil }
        let allowed = cachedArticles.compactMap { availability.sanitized($0) }
        return articleMutation == mutation ? allowed : nil
    }

    func captureArticlesHydration() -> ArticleCacheHydrationCoordinator.Capture { articleHydration.capture() }
    func isCurrentArticleRead(_ original: ArticleCacheHydrationCoordinator.Capture) -> Bool { articleHydration.isCurrent(original) }

    /// Revoke before a newer feed/write/clear can publish. This also fences an
    /// older widget preparation that originated from the superseded bytes.
    func invalidateArticleReads() {
        articleMutation = UUID()
        articleHydration.invalidate()
        widgetFeedSync.invalidate()
    }

    func loadCapturedArticles(
        _ original: ArticleCacheHydrationCoordinator.Capture,
        stillPermitted: @escaping @MainActor () -> Bool = { true },
        discardInvalidCache: Bool = true
    ) async -> ArticleCacheHydrationCoordinator.Outcome {
        let outcome = await articleHydration.load(original, stillPermitted: stillPermitted)
        let allowed = stillPermitted()
        guard allowed, articleHydration.isCurrent(original) else { return .stale }
        switch outcome {
        case .ready(let prepared):
            // A cached public value cannot restore a later withdrawal or older
            // body revision. Recheck the original cache after authority reads.
            let permitted = stillPermitted()
            guard permitted, articleHydration.isCurrent(original) else { return .stale }
            // Permission getters can synchronously record another denial. Do
            // not project until the last external callback has returned.
            let articles = prepared.articles.compactMap { availability.sanitized($0) }
            cachedArticles = articles
            cachedArticlesTimestamp = prepared.timestamp
            cachedArticlesAreSorted = prepared.articlesAreSorted
            return .ready(.init(articles: articles, timestamp: prepared.timestamp, articlesAreSorted: prepared.articlesAreSorted))
        case .rejected:
            // Only the source which failed validation may be removed. A stale
            // corrupt result must never clear a later good write.
            if discardInvalidCache { clearArticlesCache() }
            return outcome
        case .missing, .stale: return outcome
        }
    }

    /// Partial reads share the actual cold decoder with startup, without
    /// clearing/renewing another language or borrowing a newer cache epoch.
    func prepareFeedUpdate(_ update: ArticleMirrorCatalog.Update,
                           original: ArticleCacheHydrationCoordinator.Capture,
                           current: @escaping @MainActor () -> [Article] = { [] },
                           stillPermitted: @escaping @MainActor () -> Bool) async throws -> ArticleFeedSnapshot.Update {
        try await ArticleFeedSnapshot.prepare(update, original: original,
            load: { [self] capture, permission in
                await loadCapturedArticles(capture, stillPermitted: permission, discardInvalidCache: false)
            }, isCurrent: { [weak self] in self?.isCurrentArticleRead($0) == true },
            current: current, now: Date.init, stillPermitted: stillPermitted)
    }

    func clearArticlesCache() {
        invalidateArticleReads()
        let mutation = articleMutation
        userDefaults.removeObject(forKey: articlesCacheKey)
        guard articleMutation == mutation else { return }
        userDefaults.removeObject(forKey: lastCacheUpdateKey)
        guard articleMutation == mutation else { return }
        cachedArticles = nil
        cachedArticlesTimestamp = nil
        cachedArticlesAreSorted = false
    }

    // MARK: - Image Caching
    //
    // Note: image bytes are cached exclusively by SDWebImage (configured in
    // AppDelegate with a 60 MB memory cap + 350 MB disk cap). We only track the
    // legacy URL list here for the cache-size UI and cleanup; nothing writes to
    // it anymore.

    func getCachedImageURLs() -> [String] {
        guard let urls = userDefaults.stringArray(forKey: imagesCacheKey) else {
            return []
        }
        return urls
    }
    
    // MARK: - Smart Cache Management
    
    func updateCacheSize() async {
        let size = await calculateCacheSize()
        await MainActor.run {
            cacheSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        
        // Auto-cleanup if cache is too large
        if size > maxCacheSize {
            cleanupCache()
        }
    }
    
    func cleanupCache() {
        Task { @MainActor in
            isClearingCache = true
        }
        
        Task {
            await performCacheCleanup()
            
            // Clear SDWebImage caches to free memory and disk space
            SDImageCache.shared.clearMemory()
            await SDImageCache.shared.clearDiskOnCompletion()
            
            await MainActor.run {
                self.isClearingCache = false
            }
            await self.updateCacheSize()
        }
    }
    
    private func performCacheCleanup() async {
        // Remove old images
        let cachedURLs = getCachedImageURLs()
        let cutoffDate = Date().addingTimeInterval(-maxImageAge)
        
        for urlString in cachedURLs {
            guard let url = URL(string: urlString) else {
                continue
            }
            let fileName = url.lastPathComponent
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let creationDate = attributes[.creationDate] as? Date, creationDate < cutoffDate {
                    try fileManager.removeItem(at: fileURL)
                }
            } catch {
                continue
            }
        }
        
        // Expiry/decode shares the bounded worker; an old cleanup result
        // cannot clear bytes accepted by a newer write while this awaited.
        let original = captureArticlesHydration()
        _ = await loadCapturedArticles(original)
    }

    private func calculateCacheSize() async -> Int64 {
        await directorySizeWorker.size(at: cacheDirectory)
    }

    // MARK: - Preloading

    /// One already prepared first-screen list. Keep the existing preload cap
    /// and SDK options; preparation owns metadata/date work, not this adapter.
    func prefetchURLs(_ candidates: [URL]) {
        let limit = FeatureFlags.homeImagePreloadLimit
        var seen = Set<String>()
        var urls: [URL] = []
        for candidate in candidates {
            if seen.insert(candidate.absoluteString).inserted { urls.append(candidate) }
            if urls.count == limit { break }
        }
        DispatchQueue.global(qos: .utility).async {
            for url in urls {
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.scaleDownLargeImages, .continueInBackground, .queryMemoryData],
                    progress: nil
                ) { _, _, _, _, _, _ in }
            }
        }
    }
    
    func preloadImages(for articles: [Article]) {
        DispatchQueue.global(qos: .utility).async {
            var urls: [URL] = []
            var seen = Set<String>()

            for article in articles.prefix(FeatureFlags.homeImagePreloadLimit) {
                var mutableArticle = article
                guard let url = URL(string: mutableArticle.thumbnailURL),
                      !url.absoluteString.isEmpty else {
                    continue
                }
                if seen.insert(url.absoluteString).inserted {
                    urls.append(url)
                }
            }

            for url in urls {
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.scaleDownLargeImages, .continueInBackground, .queryMemoryData],
                    progress: nil
                ) { _, _, _, _, _, _ in }
            }
        }
    }

    func preloadArticleDetailImages(for article: Article) {
        DispatchQueue.global(qos: .userInitiated).async {
            var seen = Set<String>()
            var urls: [URL] = []

            func add(_ urlString: String?) {
                guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !urlString.isEmpty,
                      let url = URL(string: urlString),
                      seen.insert(url.absoluteString).inserted else {
                    return
                }
                urls.append(url)
            }

            add(article.mobileImageURL?.absoluteString)
            add(article.thumbURL?.absoluteString)
            add(article.coverURL?.absoluteString)

            var mutableArticle = article
            add(mutableArticle.thumbnailURL)

            if let content = article.content, !content.isEmpty {
                let cleaned = content.replacingOccurrences(
                    of: "<style[\\s\\S]*?</style>",
                    with: "",
                    options: .regularExpression
                )
                let processed = ArticleHTMLProcessor.process(cleaned)
                for urlString in ArticleHTMLProcessor.imageURLs(in: processed) {
                    add(ArticleHTMLProcessor.optimizedImageURL(from: urlString))
                }
            }

            for url in urls {
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.highPriority, .scaleDownLargeImages, .continueInBackground, .queryMemoryData],
                    progress: nil
                ) { _, _, _, _, _, _ in }
            }
        }
    }
    
    // MARK: - Cache Status
    
    func getCacheStatus() async -> CacheStatus {
        let original = captureArticlesHydration()
        async let size = calculateCacheSize()
        let hydrated = await loadCapturedArticles(original)
        let totalSize = await size
        let articleCount = isCurrentArticleRead(original) ? (hydrated.articles?.count ?? 0) : (getCachedArticles()?.count ?? 0)
        let imageCount = getCachedImageURLs().count
        
        return CacheStatus(
            totalSize: totalSize,
            articleCount: articleCount,
            imageCount: imageCount,
            lastUpdate: userDefaults.object(forKey: lastCacheUpdateKey) as? Date
        )
    }
    
    // MARK: - Metadata Caching (Topics, Sections, Authors, Stars)
    
    func cacheTopics(_ topics: [Topic]) {
        do {
            let data = try JSONEncoder().encode(topics)
            userDefaults.set(data, forKey: topicsCacheKey)
            userDefaults.set(Date(), forKey: "\(topicsCacheKey)_timestamp")
            // Topic names are part of the widget payload, even when no article
            // changed. The coordinator suppresses a save for unchanged names.
            if let cachedArticles {
                syncWidgetFeed(from: cachedArticles, articlesAreSorted: cachedArticlesAreSorted)
            }
        } catch {
        }
    }
    
    func getCachedTopics() -> [Topic]? {
        guard let data = userDefaults.data(forKey: topicsCacheKey),
              let timestamp = userDefaults.object(forKey: "\(topicsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        do {
            return try JSONDecoder().decode([Topic].self, from: data)
        } catch {
            return nil
        }
    }
    
    func cacheSections(_ sections: [WebflowSection]) {
        do {
            let data = try JSONEncoder().encode(sections)
            userDefaults.set(data, forKey: sectionsCacheKey)
            userDefaults.set(Date(), forKey: "\(sectionsCacheKey)_timestamp")
        } catch {
        }
    }
    
    func getCachedSections() -> [WebflowSection]? {
        guard let data = userDefaults.data(forKey: sectionsCacheKey),
              let timestamp = userDefaults.object(forKey: "\(sectionsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        do {
            return try JSONDecoder().decode([WebflowSection].self, from: data)
        } catch {
            return nil
        }
    }
    
    func cacheAuthors(_ authors: [Author]) {
        do {
            let data = try JSONEncoder().encode(authors)
            userDefaults.set(data, forKey: authorsCacheKey)
            userDefaults.set(Date(), forKey: "\(authorsCacheKey)_timestamp")
        } catch {
        }
    }
    
    func getCachedAuthors() -> [Author]? {
        guard let data = userDefaults.data(forKey: authorsCacheKey),
              let timestamp = userDefaults.object(forKey: "\(authorsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        do {
            return try JSONDecoder().decode([Author].self, from: data)
        } catch {
            return nil
        }
    }
    
    func cacheStarsMapping(_ mapping: [String: String]) {
        userDefaults.set(mapping, forKey: starsCacheKey)
        userDefaults.set(Date(), forKey: "\(starsCacheKey)_timestamp")
    }
    
    func getCachedStarsMapping() -> [String: String]? {
        guard let mapping = userDefaults.dictionary(forKey: starsCacheKey) as? [String: String],
              let timestamp = userDefaults.object(forKey: "\(starsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        return mapping
    }
    
    // MARK: - Public Cache Clearing Method
    
    /// Clears all cache including articles, images, and SDWebImage caches.
    /// Prints debug statement upon completion.
    func clearAllCache() {
        // Revoke and remove article bytes before the deferred image work. A
        // fresh write after this event must survive the older clear task.
        clearArticlesCache()
        Task { @MainActor in
            isClearingCache = true
        }
        
        Task {
            // Clear images from manual cache directory
            let cachedURLs = getCachedImageURLs()
            for urlString in cachedURLs {
                guard let url = URL(string: urlString) else {
                    continue
                }
                let fileName = url.lastPathComponent
                let fileURL = cacheDirectory.appendingPathComponent(fileName)
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                }
            }
            userDefaults.removeObject(forKey: imagesCacheKey)
            
            // Clear SDWebImage caches to free memory and disk space
            SDImageCache.shared.clearMemory()
            await SDImageCache.shared.clearDiskOnCompletion()

            PodcastAudioCache.shared.removeAllCachedFiles()
            
            await MainActor.run {
                self.isClearingCache = false
            }
            await self.updateCacheSize()
        }
    }
}

// MARK: - Supporting Types

struct CacheStatus {
    let totalSize: Int64
    let articleCount: Int
    let imageCount: Int
    let lastUpdate: Date?
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedLastUpdate: String {
        guard let lastUpdate = lastUpdate else { return "Aldrig" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
    }
}
