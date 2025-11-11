import Foundation
import UIKit
import SDWebImage
import SwiftUI

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
        cacheDirectory = paths[0].appendingPathComponent("AproposMagazine")
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
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
        print("[CacheManager] Deinitialized and cleaned up memory.")
    }
    
    @objc private func handleMemoryWarning() {
        // When memory warning is received, update cache size and perform cleanup if needed
        Task { @MainActor in
            await self.updateCacheSize()
            if let size = Int64(cacheSize.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()), size > maxCacheSize {
                self.cleanupCache()
            }
        }
    }
    
    // MARK: - Article Caching
    
    func cacheArticles(_ articles: [Article]) {
        let cacheData = CacheData(
            articles: articles,
            timestamp: Date(),
            version: "1.0"
        )
        
        if let data = try? JSONEncoder().encode(cacheData) {
            // Save to standard UserDefaults (for main app)
            userDefaults.set(data, forKey: articlesCacheKey)
            userDefaults.set(Date(), forKey: lastCacheUpdateKey)
            cachedArticles = articles
            
            // ALSO save to App Group UserDefaults (for Notification Service Extension)
            // This allows the extension to check if articles are already published
            if let appGroupDefaults = UserDefaults(suiteName: "group.com.aproposmagazine.app") {
                // Create simplified cache data for extension (id, name, lastPublished, createdOn)
                // Name is included for fallback search when article_id is missing from notifications
                let simplifiedArticles = articles.map { article in
                    [
                        "id": article.id,
                        "name": article.name ?? "",
                        "lastPublished": article.lastPublished ?? "",
                        "createdOn": article.createdOn ?? ""
                    ]
                }
                let simplifiedCacheData: [String: Any] = [
                    "articles": simplifiedArticles,
                    "timestamp": Date(),
                    "version": "1.0"
                ]
                if let simplifiedData = try? JSONSerialization.data(withJSONObject: simplifiedCacheData) {
                    appGroupDefaults.set(simplifiedData, forKey: articlesCacheKey)
                    appGroupDefaults.set(Date(), forKey: lastCacheUpdateKey)
                }
            }
        }
    }
    
    func getCachedArticles() -> [Article]? {
        if let cached = cachedArticles {
            // Check if cache is still valid
            if let data = userDefaults.data(forKey: articlesCacheKey),
               let cacheData = try? JSONDecoder().decode(CacheData.self, from: data) {
                let age = Date().timeIntervalSince(cacheData.timestamp)
                if age < maxArticleAge {
                    return cached
                } else {
                    clearArticlesCache()
                    return nil
                }
            } else {
                // Data missing or corrupted, clear cache and return nil
                clearArticlesCache()
                return nil
            }
        }
        
        guard let data = userDefaults.data(forKey: articlesCacheKey),
              let cacheData = try? JSONDecoder().decode(CacheData.self, from: data) else {
            return nil
        }
        
        // Check if cache is still valid
        let age = Date().timeIntervalSince(cacheData.timestamp)
        guard age < maxArticleAge else {
            clearArticlesCache()
            return nil
        }
        
        cachedArticles = cacheData.articles
        return cacheData.articles
    }
    
    func clearArticlesCache() {
        userDefaults.removeObject(forKey: articlesCacheKey)
        userDefaults.removeObject(forKey: lastCacheUpdateKey)
        cachedArticles = nil
    }
    
    // MARK: - Image Caching
    
    func cacheImage(_ image: UIImage, for url: URL) {
        let imageData = image.jpegData(compressionQuality: 0.8)
        let fileName = url.lastPathComponent
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        try? imageData?.write(to: fileURL)
        
        // Update cache metadata
        var cachedImages = getCachedImageURLs()
        if !cachedImages.contains(url.absoluteString) {
            cachedImages.append(url.absoluteString)
        }
        userDefaults.set(cachedImages, forKey: imagesCacheKey)
        
        Task {
            await updateCacheSize()
        }
    }
    
    func getCachedImage(for url: URL) -> UIImage? {
        let fileName = url.lastPathComponent
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return UIImage(data: imageData)
    }
    
    func getCachedImageURLs() -> [String] {
        return userDefaults.stringArray(forKey: imagesCacheKey) ?? []
    }
    
    // MARK: - Smart Cache Management
    
    func updateCacheSize() async {
        let size = await calculateCacheSize()
        cacheSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        
        // Auto-cleanup if cache is too large
        if size > maxCacheSize {
            cleanupCache()
        }
    }
    
    func cleanupCache() {
        isClearingCache = true
        
        Task {
            await performCacheCleanup()
            
            // Clear SDWebImage caches to free memory and disk space
            SDImageCache.shared.clearMemory()
            await SDImageCache.shared.clearDiskOnCompletion()
            
            self.isClearingCache = false
            await self.updateCacheSize()
        }
    }
    
    private func performCacheCleanup() async {
        // Remove old images
        let cachedURLs = getCachedImageURLs()
        let cutoffDate = Date().addingTimeInterval(-maxImageAge)
        
        for urlString in cachedURLs {
            guard let url = URL(string: urlString) else { continue }
            let fileName = url.lastPathComponent
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        // Remove old articles cache
        if let data = userDefaults.data(forKey: articlesCacheKey),
           let cacheData = try? JSONDecoder().decode(CacheData.self, from: data) {
            let age = Date().timeIntervalSince(cacheData.timestamp)
            if age > maxArticleAge {
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
                if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    size += Int64(fileSize)
                }
            }
        } catch {
            print("Error calculating cache size: \(error)")
        }
        
        return size
    }
    
    // MARK: - Preloading
    
    func preloadImages(for articles: [Article]) {
        DispatchQueue.global(qos: .utility).async {
            for article in articles.prefix(10) { // Preload first 10 articles
                var mutableArticle = article
                if let url = URL(string: mutableArticle.thumbnailURL) {
                    SDWebImageManager.shared.loadImage(
                        with: url,
                        options: [.preloadAllFrames, .refreshCached],
                        progress: nil
                    ) { _, _, _, _, _, _ in }
                }
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
        if let data = try? JSONEncoder().encode(topics) {
            userDefaults.set(data, forKey: topicsCacheKey)
            userDefaults.set(Date(), forKey: "\(topicsCacheKey)_timestamp")
        }
    }
    
    func getCachedTopics() -> [Topic]? {
        guard let data = userDefaults.data(forKey: topicsCacheKey),
              let timestamp = userDefaults.object(forKey: "\(topicsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        return try? JSONDecoder().decode([Topic].self, from: data)
    }
    
    func cacheSections(_ sections: [WebflowSection]) {
        if let data = try? JSONEncoder().encode(sections) {
            userDefaults.set(data, forKey: sectionsCacheKey)
            userDefaults.set(Date(), forKey: "\(sectionsCacheKey)_timestamp")
        }
    }
    
    func getCachedSections() -> [WebflowSection]? {
        guard let data = userDefaults.data(forKey: sectionsCacheKey),
              let timestamp = userDefaults.object(forKey: "\(sectionsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        return try? JSONDecoder().decode([WebflowSection].self, from: data)
    }
    
    func cacheAuthors(_ authors: [Author]) {
        if let data = try? JSONEncoder().encode(authors) {
            userDefaults.set(data, forKey: authorsCacheKey)
            userDefaults.set(Date(), forKey: "\(authorsCacheKey)_timestamp")
        }
    }
    
    func getCachedAuthors() -> [Author]? {
        guard let data = userDefaults.data(forKey: authorsCacheKey),
              let timestamp = userDefaults.object(forKey: "\(authorsCacheKey)_timestamp") as? Date,
              Date().timeIntervalSince(timestamp) < maxMetadataAge else {
            return nil
        }
        return try? JSONDecoder().decode([Author].self, from: data)
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
        isClearingCache = true
        
        Task {
            // Clear images from manual cache directory
            let cachedURLs = getCachedImageURLs()
            for urlString in cachedURLs {
                guard let url = URL(string: urlString) else { continue }
                let fileName = url.lastPathComponent
                let fileURL = cacheDirectory.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: fileURL)
            }
            userDefaults.removeObject(forKey: imagesCacheKey)
            
            // Clear articles cache
            clearArticlesCache()
            
            // Clear SDWebImage caches to free memory and disk space
            SDImageCache.shared.clearMemory()
            await SDImageCache.shared.clearDiskOnCompletion()
            
            self.isClearingCache = false
            await self.updateCacheSize()
            
            print("[CacheManager] All cache cleared successfully.")
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

// MARK: - SwiftUI Extensions

extension View {
    func cacheImage(_ url: URL) -> some View {
        self.onAppear {
            if CacheManager.shared.getCachedImage(for: url) == nil {
                // Image not cached, trigger download
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.refreshCached],
                    progress: nil
                ) { image, _, _, _, _, _ in
                    if let image = image {
                        CacheManager.shared.cacheImage(image, for: url)
                    }
                }
            }
        }
    }
}
