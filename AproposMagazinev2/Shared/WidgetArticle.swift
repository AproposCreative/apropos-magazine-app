import Foundation
import UIKit
import WidgetKit

struct WidgetArticle: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let thumbURL: String
    let intro: String
    let date: String
    let stjerne: Int?
    let topic: String

    init(
        id: String,
        name: String,
        slug: String,
        thumbURL: String,
        intro: String,
        date: String,
        stjerne: Int? = nil,
        topic: String = ""
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.thumbURL = thumbURL
        self.intro = intro
        self.date = date
        self.stjerne = stjerne
        self.topic = topic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        thumbURL = try container.decode(String.self, forKey: .thumbURL)
        intro = try container.decodeIfPresent(String.self, forKey: .intro) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        stjerne = try container.decodeIfPresent(Int.self, forKey: .stjerne)
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, thumbURL, intro, date, stjerne, topic
    }

    /// Shown in widget gallery / before the main app has synced feed data.
    static let galleryPreview = WidgetArticle(
        id: "widget-preview",
        name: "Seneste fra Apropos Magazine",
        slug: "widget-preview",
        thumbURL: "",
        intro: "",
        date: "",
        stjerne: 4,
        topic: "Anmeldelser"
    )
}

enum WidgetImageStore {
    private static let folderName = "WidgetImages"
    private static let cacheVersionKey = "widget_image_cache_version"
    private static let currentCacheVersion = 2

    /// Widget extensions should read cached files only — the main app downloads images.
    private static var isWidgetExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }

    private static func safeFileName(for articleId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = articleId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(sanitized)
        return value.isEmpty ? "article" : value
    }

    static func imagesDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetDataStore.appGroupID
        ) else {
            return nil
        }

        let directory = container.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func localImageURL(for articleId: String) -> URL? {
        guard let directory = imagesDirectory() else { return nil }
        let fileName = "\(safeFileName(for: articleId)).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        // Legacy filenames used the raw article id.
        let legacyURL = directory.appendingPathComponent("\(articleId).jpg")
        return FileManager.default.fileExists(atPath: legacyURL.path) ? legacyURL : nil
    }

    static func hasCachedImage(for articleId: String) -> Bool {
        localImageURL(for: articleId) != nil
    }

    static func uiImage(for article: WidgetArticle) -> UIImage? {
        uiImage(forArticleId: article.id)
    }

    static func uiImage(forArticleId articleId: String) -> UIImage? {
        guard let localURL = localImageURL(for: articleId) else { return nil }

        if let data = try? Data(contentsOf: localURL),
           let image = UIImage(data: data) {
            return image
        }

        return UIImage(contentsOfFile: localURL.path)
    }

    static func cacheImage(forArticleId articleId: String, remoteURL: URL) async {
        guard !articleId.isEmpty else { return }
        let article = WidgetArticle(
            id: articleId,
            name: "",
            slug: "",
            thumbURL: remoteURL.absoluteString,
            intro: "",
            date: ""
        )
        _ = await cacheImageIfNeeded(for: article, fetchFromNetwork: true)
    }

    static func cacheImages(for articles: [WidgetArticle], fetchFromNetwork: Bool = true) async -> [WidgetArticle] {
        migrateCacheIfNeeded()
        let shouldFetch = fetchFromNetwork && !isWidgetExtension

        return await withTaskGroup(of: WidgetArticle.self) { group in
            for article in articles {
                group.addTask {
                    await cacheImageIfNeeded(for: article, fetchFromNetwork: shouldFetch)
                }
            }

            var results: [WidgetArticle] = []
            for await article in group {
                results.append(article)
            }
            return results.sorted { lhs, rhs in
                articles.firstIndex(where: { $0.id == lhs.id }) ?? 0 <
                    articles.firstIndex(where: { $0.id == rhs.id }) ?? 0
            }
        }
    }

    private static func migrateCacheIfNeeded() {
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupID) else { return }
        guard defaults.integer(forKey: cacheVersionKey) < currentCacheVersion else { return }

        if let directory = imagesDirectory() {
            try? FileManager.default.removeItem(at: directory)
        }
        ensureImagesDirectoryExists()
        defaults.set(currentCacheVersion, forKey: cacheVersionKey)
    }

    private static func ensureImagesDirectoryExists() {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetDataStore.appGroupID
        ) else {
            return
        }

        let directory = container.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func cacheImageIfNeeded(
        for article: WidgetArticle,
        fetchFromNetwork: Bool = true
    ) async -> WidgetArticle {
        if let existing = localImageURL(for: article.id),
           let data = try? Data(contentsOf: existing),
           UIImage(data: data) != nil {
            return article
        }

        guard fetchFromNetwork,
              let remote = URL(string: article.thumbURL),
              !article.thumbURL.isEmpty,
              let directory = imagesDirectory(),
              let (data, _) = try? await URLSession.shared.data(from: remote),
              !data.isEmpty else {
            return article
        }

        let fileURL = directory.appendingPathComponent("\(safeFileName(for: article.id)).jpg")
        if let existing = localImageURL(for: article.id) {
            try? FileManager.default.removeItem(at: existing)
        }
        _ = saveNormalizedWidgetImage(data: data, to: fileURL)
        return article
    }

    @discardableResult
    private static func saveNormalizedWidgetImage(data: Data, to fileURL: URL) -> Bool {
        guard let image = UIImage(data: data) else { return false }

        let maxDimension: CGFloat = 800
        let maxSide = max(image.size.width, image.size.height)
        let normalized: UIImage

        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            normalized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            normalized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }

        guard let jpeg = normalized.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}

enum WidgetDataStore {
    static let appGroupID = "group.com.aproposmagazine.app"
    static let latestArticlesKey = "widget_latest_articles"
    static let lastSyncKey = "widget_last_sync"

    static var isAppGroupAvailable: Bool {
        UserDefaults(suiteName: appGroupID) != nil
    }

    static func saveLatestArticles(_ articles: [WidgetArticle], reloadTimelines: Bool = true) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let payload = Array(articles.prefix(5))
        guard !payload.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: latestArticlesKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        defaults.synchronize()
        if reloadTimelines {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func loadLatestArticles() -> [WidgetArticle] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return []
        }

        if let data = defaults.data(forKey: latestArticlesKey),
           let articles = try? JSONDecoder().decode([WidgetArticle].self, from: data),
           !articles.isEmpty {
            return articles
        }

        return loadFallbackArticles(from: defaults)
    }

    static func articlesForWidget(includePreviewWhenEmpty: Bool = false) -> [WidgetArticle] {
        let loaded = loadLatestArticles()
        if !loaded.isEmpty { return loaded }
        if includePreviewWhenEmpty { return [WidgetArticle.galleryPreview] }
        return []
    }

    private static func loadFallbackArticles(from defaults: UserDefaults) -> [WidgetArticle] {
        guard let data = defaults.data(forKey: "cached_articles"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let simplified = json["articles"] as? [[String: String]] else {
            return []
        }

        return simplified.prefix(5).compactMap { entry in
            guard let id = entry["id"], !id.isEmpty else { return nil }
            let stjerneValue = entry["stjerne"].flatMap(Int.init)
            return WidgetArticle(
                id: id,
                name: entry["name"] ?? "Artikel",
                slug: entry["slug"] ?? id,
                thumbURL: entry["thumbURL"] ?? "",
                intro: "",
                date: entry["lastPublished"] ?? entry["createdOn"] ?? "",
                stjerne: stjerneValue,
                topic: entry["topic"] ?? ""
            )
        }
    }
}
