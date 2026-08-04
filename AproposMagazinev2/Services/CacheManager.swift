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
    
    private let userDefaults = UserDefaults.standard
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
    
    private init() {
        // Get cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        if let aproposCacheDir = paths.first?.appendingPathComponent("AproposMagazine") {
            cacheDirectory = aproposCacheDir
        } else {
            // Fallback to temporary directory if cachesDirectory is not found
            cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AproposMagazine")
        }
        
        // Create cache directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
        }
        
        Task {
            await updateCacheSize()
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

    func syncWidgetFeed(from articles: [Article]) {
        guard !articles.isEmpty else { return }

        let topics = getCachedTopics() ?? []
        let payload = Article.sortedByCreatedNewestFirst(articles).prefix(5).map { article in
            WidgetArticle(
                id: article.id,
                name: article.name ?? "Artikel",
                slug: article.slug ?? article.id,
                thumbURL: {
                    if let url = article.thumbURL ?? article.mobileImageURL ?? article.coverURL {
                        return url.absoluteString
                    }
                    return ""
                }(),
                intro: article.intro ?? "",
                date: article.lastPublished ?? article.createdOn ?? article.date ?? "",
                stjerne: article.stjerne,
                topic: topicName(for: article, topics: topics)
            )
        }

        let widgetArticles = Array(payload)
        WidgetDataStore.saveLatestArticles(widgetArticles, reloadTimelines: true)

        Task.detached(priority: .utility) {
            let cached = await WidgetImageStore.cacheImages(for: widgetArticles, fetchFromNetwork: true)
            await MainActor.run {
                WidgetDataStore.saveLatestArticles(cached, reloadTimelines: true)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
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
    
    func cacheArticles(_ articles: [Article]) {
        let publishedArticles = articles
            .filter(\.isPubliclyPublished)
            .map { $0.strippingBodyContent() }
        let cacheData = CacheData(
            articles: publishedArticles,
            timestamp: Date(),
            version: Self.articlesCacheVersion
        )

        do {
            let data = try JSONEncoder().encode(cacheData)

            // Save to standard UserDefaults (for main app)
            userDefaults.set(data, forKey: articlesCacheKey)
            userDefaults.set(Date(), forKey: lastCacheUpdateKey)
            cachedArticles = publishedArticles
            syncWidgetFeed(from: publishedArticles)

            // ALSO save to App Group UserDefaults (for Notification Service Extension)
            // This allows the extension to check if articles are already published
            guard let appGroupDefaults = UserDefaults(suiteName: "group.com.aproposmagazine.app") else {
                return
            }

            // Create simplified cache data for extension (id, name, lastPublished, createdOn)
            // Name is included for fallback search when article_id is missing from notifications
            let cachedTopics = getCachedTopics() ?? []
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
                "timestamp": Date().timeIntervalSince1970,
                "version": Self.articlesCacheVersion
            ]

            do {
                guard JSONSerialization.isValidJSONObject(simplifiedCacheData) else {
                    return
                }
                let simplifiedData = try JSONSerialization.data(withJSONObject: simplifiedCacheData)
                appGroupDefaults.set(simplifiedData, forKey: articlesCacheKey)
                appGroupDefaults.set(Date(), forKey: lastCacheUpdateKey)
                appGroupDefaults.synchronize()
            } catch {
            }

        } catch {
        }
    }
    
    func getCachedArticles() -> [Article]? {
        func loadArticles(from data: Data) throws -> [Article]? {
            let cacheData = try JSONDecoder().decode(CacheData.self, from: data)
            guard cacheData.version == Self.articlesCacheVersion else {
                clearArticlesCache()
                return nil
            }

            let age = Date().timeIntervalSince(cacheData.timestamp)
            guard age < maxArticleAge else {
                clearArticlesCache()
                return nil
            }

            cachedArticles = cacheData.articles.filter(\.isPubliclyPublished)
            return cachedArticles
        }

        // Return in-memory articles without re-decoding from disk.
        if let cachedArticles {
            return cachedArticles
        }
        
        // Attempt to load from UserDefaults if no cached articles in memory
        guard let data = userDefaults.data(forKey: articlesCacheKey) else {
            return nil
        }
        
        do {
            return try loadArticles(from: data)
        } catch {
            clearArticlesCache()
            return nil
        }
    }
    
    func clearArticlesCache() {
        userDefaults.removeObject(forKey: articlesCacheKey)
        userDefaults.removeObject(forKey: lastCacheUpdateKey)
        cachedArticles = nil
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
        
        // Remove old articles cache if expired
        if let data = userDefaults.data(forKey: articlesCacheKey) {
            do {
                let cacheData = try JSONDecoder().decode(CacheData.self, from: data)
                let age = Date().timeIntervalSince(cacheData.timestamp)
                if age > maxArticleAge {
                    clearArticlesCache()
                }
            } catch {
                clearArticlesCache()
            }
        }
    }
    
    private func calculateCacheSize() async -> Int64 {
        var size: Int64 = 0
        
        do {
            // contentsOfDirectory is synchronous; no await needed
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for url in contents {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resourceValues.fileSize {
                        size += Int64(fileSize)
                    }
                } catch {
                    continue
                }
            }
        } catch {
        }
        
        return size
    }
    
    // MARK: - Preloading
    
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
        let totalSize = await calculateCacheSize()
        let articleCount = getCachedArticles()?.count ?? 0
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
            
            // Clear articles cache
            clearArticlesCache()
            
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

struct CacheData: Codable {
    let articles: [Article]
    let timestamp: Date
    let version: String
}

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
