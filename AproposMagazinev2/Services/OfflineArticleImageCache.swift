import CryptoKit
import Foundation
import OSLog

/// On-disk image cache for offline saved articles (favorites / offline storage).
final class OfflineArticleImageCache {
    static let shared = OfflineArticleImageCache()

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "OfflineArticleImageCache")
    private var activeArticleIds = Set<String>()
    private let queue = DispatchQueue(label: "com.aproposmagazine.offline-article-images")

    private func withLockedState(_ work: () -> Void) {
        queue.sync(execute: work)
    }

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AproposMagazine", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AproposMagazine", isDirectory: true)
        rootDirectory = base.appendingPathComponent("offline-article-images", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func articleDirectory(for articleId: String) -> URL {
        rootDirectory.appendingPathComponent(articleId, isDirectory: true)
    }

    func displayURL(for remote: URL?, articleId: String) -> URL? {
        guard let remote else { return nil }
        // Prefer CDN while online — local file URLs are only for true offline.
        if isDeviceOnline {
            return remote
        }
        guard isArticleAvailableOffline(articleId) else { return remote }

        let candidates = [
            remote.absoluteString,
            ArticleHTMLProcessor.optimizedImageURL(from: remote.absoluteString)
        ]

        for candidate in candidates {
            if let local = localFileURL(forRemote: candidate, articleId: articleId) {
                return local
            }
        }

        return remote
    }

    func localFileURL(forRemote remoteURLString: String, articleId: String) -> URL? {
        guard let mapping = loadMapping(articleId: articleId),
              let filename = mapping[remoteURLString] else {
            return nil
        }
        let fileURL = articleDirectory(for: articleId).appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// Rewrites image `src` for offline reading.
    /// When online, returns the original HTML unchanged so CDN images keep working.
    /// When offline, embeds cached images as data-URIs (WKWebView cannot reliably
    /// load relative `file://` assets from `loadHTMLString`).
    func prepareHTMLForOfflineDisplay(_ html: String, articleId: String?) -> (html: String, baseURL: URL?) {
        guard !isDeviceOnline,
              let articleId, !articleId.isEmpty,
              isArticleAvailableOffline(articleId),
              let mapping = loadMapping(articleId: articleId),
              !mapping.isEmpty else {
            return (html, nil)
        }

        let directory = articleDirectory(for: articleId)
        var result = html

        for (remote, filename) in mapping.sorted(by: { $0.key.count > $1.key.count }) {
            let fileURL = directory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            guard result.contains(remote) else { continue }
            guard let dataURI = dataURI(forFileAt: fileURL) else { continue }
            result = result.replacingOccurrences(of: remote, with: dataURI)
        }

        return (result, nil)
    }

    private var isDeviceOnline: Bool {
        // HTMLTextView / image helpers are invoked on the main thread.
        if Thread.isMainThread {
            return MainActor.assumeIsolated { OfflineManager.shared.isOnline }
        }
        return true
    }

    private func dataURI(forFileAt fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        let ext = fileURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "png": mime = "image/png"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        case "jpg", "jpeg": mime = "image/jpeg"
        default: mime = "image/jpeg"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    func pruneOrphanedCaches(keeping articleIds: Set<String>) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for entry in entries where entry.hasDirectoryPath {
            let articleId = entry.lastPathComponent
            if !articleIds.contains(articleId) {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private func isArticleAvailableOffline(_ articleId: String) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "offline_articles"),
              let articles = try? JSONDecoder().decode([Article].self, from: data) else {
            return false
        }
        return articles.contains { $0.id == articleId }
    }

    func scheduleCacheImages(for articles: [Article]) {
        for article in articles {
            scheduleCacheImages(for: article)
        }
    }

    func scheduleCacheImages(for article: Article) {
        let articleId = article.id
        var shouldStart = false
        withLockedState {
            shouldStart = !activeArticleIds.contains(articleId)
            if shouldStart {
                activeArticleIds.insert(articleId)
            }
        }
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            defer {
                if let self {
                    self.withLockedState {
                        self.activeArticleIds.remove(articleId)
                    }
                }
            }
            await self?.cacheImages(for: article)
        }
    }

    func cacheImages(for article: Article) async {
        let articleId = article.id
        let directory = articleDirectory(for: articleId)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Kunne ikke oprette offline-billedmappe: \(error.localizedDescription, privacy: .public)")
            return
        }

        var mapping = loadMapping(articleId: articleId) ?? [:]
        let urlStrings = Self.imageURLStrings(for: article)

        await withTaskGroup(of: (String, String)?.self) { group in
            for urlString in urlStrings {
                if mapping[urlString] != nil,
                   fileManager.fileExists(atPath: directory.appendingPathComponent(mapping[urlString]!).path) {
                    continue
                }

                group.addTask {
                    guard let filename = await self.downloadImage(from: urlString, to: directory) else {
                        return nil
                    }
                    return (urlString, filename)
                }
            }

            for await result in group {
                guard let (remote, filename) = result else { continue }
                mapping[remote] = filename
            }
        }

        saveMapping(mapping, articleId: articleId)
        logger.debug("Offline-billeder cachet for artikel \(articleId, privacy: .public): \(mapping.count, privacy: .public) filer")
    }

    func removeImages(for articleId: String) {
        withLockedState {
            activeArticleIds.remove(articleId)
        }
        let directory = articleDirectory(for: articleId)
        try? fileManager.removeItem(at: directory)
    }

    func removeAllCachedImages() {
        withLockedState {
            activeArticleIds.removeAll()
        }
        try? fileManager.removeItem(at: rootDirectory)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func totalCacheSizeBytes() -> Int64 {
        directorySize(at: rootDirectory)
    }

    private static func imageURLStrings(for article: Article) -> [String] {
        var urls = Set<String>()

        func add(_ urlString: String?) {
            guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty,
                  urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else {
                return
            }
            urls.insert(urlString)
            urls.insert(ArticleHTMLProcessor.optimizedImageURL(from: urlString))
        }

        add(article.mobileImageURL?.absoluteString)
        add(article.thumbURL?.absoluteString)
        add(article.coverURL?.absoluteString)

        var mutable = article
        add(mutable.thumbnailURL)

        if let content = article.content, !content.isEmpty {
            let cleaned = content.replacingOccurrences(
                of: "<style[\\s\\S]*?</style>",
                with: "",
                options: .regularExpression
            )
            let processed = ArticleHTMLProcessor.process(cleaned)
            for url in ArticleHTMLProcessor.imageURLs(in: processed) {
                add(url)
            }
            for url in ArticleHTMLProcessor.imageURLs(in: cleaned) {
                add(url)
            }
        }

        return Array(urls)
    }

    private func downloadImage(from urlString: String, to directory: URL) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty else { return nil }

            let ext = fileExtension(for: response, fallbackURL: url)
            let filename = cacheFilename(for: urlString, extension: ext)
            let destination = directory.appendingPathComponent(filename)
            try data.write(to: destination, options: .atomic)
            return filename
        } catch {
            logger.debug("Offline-billede download fejlede: \(urlString, privacy: .public)")
            return nil
        }
    }

    private func cacheFilename(for urlString: String, extension ext: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).\(ext)"
    }

    private func fileExtension(for response: URLResponse, fallbackURL: URL) -> String {
        if let mimeType = response.mimeType {
            switch mimeType {
            case "image/jpeg", "image/jpg": return "jpg"
            case "image/png": return "png"
            case "image/webp": return "webp"
            case "image/gif": return "gif"
            default: break
            }
        }

        let pathExt = fallbackURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "gif"].contains(pathExt) {
            return pathExt == "jpeg" ? "jpg" : pathExt
        }
        return "jpg"
    }

    private func mappingURL(for articleId: String) -> URL {
        articleDirectory(for: articleId).appendingPathComponent("mapping.json")
    }

    private func loadMapping(articleId: String) -> [String: String]? {
        let url = mappingURL(for: articleId)
        guard let data = try? Data(contentsOf: url),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return mapping
    }

    private func saveMapping(_ mapping: [String: String], articleId: String) {
        let url = mappingURL(for: articleId)
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
