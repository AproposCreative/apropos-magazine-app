import CryptoKit
import Combine
import Foundation

/// Content-addressed public bytes. A file is never favorite/owner authority.
/// Each write is fenced by its original download generation under one queue.
final class OfflineArticleImageCache: @unchecked Sendable {
    struct Artifact { let data: Data; let response: URLResponse }
    typealias Download = @Sendable (URL) async throws -> Artifact
    static let shared: OfflineArticleImageCache = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return OfflineArticleImageCache(cacheDirectory: base.appendingPathComponent("AproposMagazine/favorite-images-v1", isDirectory: true), download: { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            return Artifact(data: data, response: response)
        })
    }()
    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let download: Download
    private let online: (@MainActor () -> Bool)?
    private let preparationAccess: (@MainActor (String, String?) -> PreparationAccess)?
    private let contentKey: (@MainActor (String, String?) -> String?)?
    private let mappingReadObserver: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "com.aproposmagazine.offline-article-images")
    private var active: [String: UUID] = [:]
    private let displayEpoch = OfflineImageDisplayEpoch()
    @MainActor private let displayChangeSubject = PassthroughSubject<Void, Never>()
    @MainActor var displayChanges: AnyPublisher<Void, Never> { displayChangeSubject.eraseToAnyPublisher() }
    var displayGeneration: UUID { displayEpoch.value }
    private struct DisplayKey: Hashable, Sendable {
        let contentKey: String
        let lease: UUID
        let remote: URL
        let optimized: String
        let epoch: UUID
    }
    @MainActor private final class DisplayWaiter {
        let id = UUID()
        let access: PreparationAccess
        let cancellation: OfflineImageDisplayCancellation
        var continuation: CheckedContinuation<URL?, Never>?
        init(access: PreparationAccess, cancellation: OfflineImageDisplayCancellation, continuation: CheckedContinuation<URL?, Never>) {
            self.access = access; self.cancellation = cancellation; self.continuation = continuation
        }
        func finish(_ value: URL?) { let held = continuation; continuation = nil; held?.resume(returning: value) }
    }
    @MainActor private final class DisplayJob {
        let id = UUID()
        let key: DisplayKey
        var waiters: [DisplayWaiter]
        init(key: DisplayKey, waiter: DisplayWaiter) { self.key = key; waiters = [waiter] }
    }
    @MainActor private var activeDisplays: [UUID: DisplayJob] = [:]
    @MainActor private var pendingDisplays: [DisplayJob] = []
    @MainActor private var displayResults: [(key: DisplayKey, url: URL)] = []
    @MainActor var displayActivity: (active: Int, pending: Int) { (activeDisplays.count, pendingDisplays.count) }
    init(cacheDirectory: URL, download: @escaping Download,
         online: (@MainActor () -> Bool)? = nil,
         contentKey: (@MainActor (String, String?) -> String?)? = nil,
         preparationAccess: (@MainActor (String, String?) -> PreparationAccess)? = nil,
         mappingReadObserver: (@Sendable () -> Void)? = nil) {
        rootDirectory = cacheDirectory; self.download = download
        self.online = online; self.contentKey = contentKey; self.preparationAccess = preparationAccess
        self.mappingReadObserver = mappingReadObserver
    }
    var downloadActivity: Int { queue.sync { active.count } }
    private static func validKey(_ key: String) -> Bool { key.count == 64 && key.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
    private func directory(_ key: String) -> URL { rootDirectory.appendingPathComponent(key, isDirectory: true) }
    private func currentContentKey(articleID: String, revision: String?) -> String? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated {
            if let contentKey { return contentKey(articleID, revision) }
            return FavoritesRuntime.shared.offline?.captureAccess(articleID: articleID).flatMap { ticket in
                guard let revision, ticket.contentRevision == revision else { return nil }
                return ticket.contentKey
            }
        }
    }
    private var isDeviceOnline: Bool {
        guard Thread.isMainThread else { return true }
        return MainActor.assumeIsolated {
            if let online { return online() }
            guard FavoritesRuntime.shared.offline != nil else { return true }
            return OfflineManager.shared.isOnline
        }
    }
    func displayURL(for remote: URL?, articleId: String, expectedRevision: String? = nil) -> URL? {
        guard let remote else { return nil }
        guard Thread.isMainThread else { return remote }
        return MainActor.assumeIsolated {
            let access = capturePreparationAccess(articleID: articleId, revision: expectedRevision)
            guard let key = displayKey(remote: remote, access: access),
                  let cached = displayResults.first(where: { $0.key == key }),
                  access.isCurrent(), key.epoch == displayGeneration, !isDeviceOnline,
                  access.isCurrent(), key.epoch == displayGeneration else { return remote }
            return cached.url
        }
    }

    /// The caller captures the original lease before its Task and withholds the
    /// remote image while this bounded lookup runs. No disk work occurs on MainActor.
    @MainActor
    func prepareDisplayURL(for remote: URL?, access: PreparationAccess, force: Bool = false) async -> URL? {
        guard let remote, !Task.isCancelled else { return nil }
        guard access.isCurrent() else { return nil }
        guard let key = displayKey(remote: remote, access: access) else {
            guard access.isCurrent() else { return nil }
            let remoteOnly = access.contentKey == nil || isDeviceOnline
            guard access.isCurrent() else { return nil }
            return remoteOnly ? remote : nil
        }
        if !force, let cached = displayResults.first(where: { $0.key == key }), access.isCurrent(), key.epoch == displayGeneration,
           !isDeviceOnline, access.isCurrent(), key.epoch == displayGeneration {
            return Task.isCancelled ? nil : cached.url
        }
        let cancellation = OfflineImageDisplayCancellation()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled, access.isCurrent(), key.epoch == displayGeneration else { return nil }
            return await withCheckedContinuation { continuation in
                let waiter = DisplayWaiter(access: access, cancellation: cancellation, continuation: continuation)
                cancellation.bind(waiter.id)
                guard !cancellation.isCancelled, access.isCurrent(), key.epoch == displayGeneration else { waiter.finish(nil); return }
                if let job = activeDisplays.values.first(where: { $0.key == key }) ?? pendingDisplays.first(where: { $0.key == key }) {
                    guard job.waiters.count < 32 else { waiter.finish(nil); return }
                    job.waiters.append(waiter)
                } else {
                    if force { displayResults.removeAll { $0.key == key } }
                    if pendingDisplays.count >= 32 {
                        let displaced = pendingDisplays.removeFirst()
                        displaced.waiters.forEach { $0.finish(nil) }
                    }
                    pendingDisplays.append(DisplayJob(key: key, waiter: waiter))
                }
                pumpDisplayPreparation()
            }
        } onCancel: { [weak self] in
            cancellation.cancel()
            Task { @MainActor [weak self] in
                guard let id = cancellation.waiterID else { return }
                self?.cancelDisplayWaiter(id)
            }
        }
    }

    @MainActor private func displayKey(remote: URL, access: PreparationAccess) -> DisplayKey? {
        let epoch = displayGeneration
        guard let key = access.contentKey, let lease = access.generation, Self.validKey(key),
              access.isCurrent(), epoch == displayGeneration, !isDeviceOnline else { return nil }
        let optimized = ArticleHTMLProcessor.optimizedImageURL(from: remote.absoluteString,
                                                               targetWidth: ArticleHTMLProcessor.capturedImageWidth())
        guard access.isCurrent(), epoch == displayGeneration else { return nil }
        return DisplayKey(contentKey: key, lease: lease, remote: remote, optimized: optimized, epoch: epoch)
    }

    @MainActor private func pumpDisplayPreparation() {
        while activeDisplays.count < 4, !pendingDisplays.isEmpty {
            let job = pendingDisplays.removeFirst()
            // Reserve before invoking any injected access getter. Reentry may
            // append a waiter or start other jobs, but cannot exceed capacity.
            activeDisplays[job.id] = job
            for waiter in job.waiters {
                let allowed = !waiter.cancellation.isCancelled && waiter.access.isCurrent()
                    && job.key.epoch == displayGeneration && !isDeviceOnline
                    && waiter.access.isCurrent() && job.key.epoch == displayGeneration && !waiter.cancellation.isCancelled
                if !allowed {
                    job.waiters.removeAll { $0.id == waiter.id }
                    waiter.finish(nil)
                }
            }
            guard !job.waiters.isEmpty else { activeDisplays.removeValue(forKey: job.id); continue }
            let id = job.id, key = job.key
            queue.async { [self] in
                let result: URL?
                if key.epoch == displayGeneration {
                    let mapping = loadMappingLocked(key.contentKey)
                    result = [key.remote.absoluteString, key.optimized].compactMap { raw -> URL? in
                        guard let name = mapping[raw] else { return nil }
                        let file = directory(key.contentKey).appendingPathComponent(name)
                        return fileManager.fileExists(atPath: file.path) ? file : nil
                    }.first
                } else { result = nil }
                Task { @MainActor [weak self] in self?.completeDisplayPreparation(id, result: result) }
            }
        }
    }

    @MainActor private func completeDisplayPreparation(_ id: UUID, result: URL?) {
        guard let job = activeDisplays.removeValue(forKey: id) else { return }
        for waiter in job.waiters {
            guard !waiter.cancellation.isCancelled, waiter.access.isCurrent(),
                  job.key.epoch == displayGeneration, !isDeviceOnline, waiter.access.isCurrent(),
                  job.key.epoch == displayGeneration, !waiter.cancellation.isCancelled else { waiter.finish(nil); continue }
            let value = result ?? job.key.remote
            displayResults.removeAll { $0.key == job.key }
            displayResults.append((job.key, value))
            if displayResults.count > 128 { displayResults.removeFirst(displayResults.count - 128) }
            waiter.finish(value)
        }
        pumpDisplayPreparation()
    }

    @MainActor private func cancelDisplayWaiter(_ id: UUID) {
        for job in Array(activeDisplays.values) + pendingDisplays {
            guard let waiter = job.waiters.first(where: { $0.id == id }) else { continue }
            job.waiters.removeAll { $0.id == id }; waiter.finish(nil)
        }
        pendingDisplays.removeAll { $0.waiters.isEmpty }
        // An enqueued physical lookup owns its slot until its actual callback.
    }

    private func invalidatePreparedDisplays() {
        displayEpoch.advance()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let current = displayGeneration
            displayResults.removeAll { $0.key.epoch != current }
            let obsolete = pendingDisplays.filter { $0.key.epoch != current }
            pendingDisplays.removeAll { $0.key.epoch != current }
            obsolete.forEach { $0.waiters.forEach { $0.finish(nil) } }
            displayChangeSubject.send(())
            pumpDisplayPreparation()
        }
    }
    func prepareHTMLForOfflineDisplay(_ html: String, articleId: String?, expectedRevision: String? = nil) -> (html: String, baseURL: URL?) {
        guard !isDeviceOnline, let articleId, let key = currentContentKey(articleID: articleId, revision: expectedRevision) else { return (html, nil) }
        let result = prepareCapturedHTML(html, contentKey: key)
        guard currentContentKey(articleID: articleId, revision: expectedRevision) == key else { return (html, nil) }
        return result
    }

    /// The closure retains the original membership generation, not just public
    /// cache bytes. Returning to the same UID/revision cannot restore access.
    @MainActor
    struct PreparationAccess {
        let contentKey: String?
        let generation: UUID?
        let isCurrent: @MainActor () -> Bool
        static var remote: Self { .init(contentKey: nil, generation: nil, isCurrent: { true }) }
    }

    @MainActor
    func capturePreparationAccess(articleID: String?, revision: String?) -> PreparationAccess {
        guard !isDeviceOnline, let articleID else { return .remote }
        if let preparationAccess { return preparationAccess(articleID, revision) }
        // Legacy injected key-only adapters do not provide generation authority;
        // async callers must inject a real access snapshot to embed local bytes.
        if contentKey != nil { return .remote }
        guard let bridge = FavoritesRuntime.shared.offline else { return .remote }
        return Self.preparationAccess(bridge: bridge, articleID: articleID, revision: revision)
    }

    @MainActor
    static func preparationAccess(bridge: FavoritesOfflineCoordinator, articleID: String,
                                  revision: String?) -> PreparationAccess {
        guard let ticket = bridge.captureAccess(articleID: articleID),
              let revision, ticket.contentRevision == revision,
              bridge.isCurrent(ticket) else { return .remote }
        return PreparationAccess(contentKey: ticket.contentKey, generation: ticket.leaseID,
            isCurrent: { [weak bridge] in bridge?.isCurrent(ticket) ?? false })
    }

    /// Blocking disk/base64 work for a detached worker. This method cannot grant
    /// membership: the captured access must still be checked before rendering.
    func prepareCapturedHTML(_ html: String, contentKey key: String?) -> (html: String, baseURL: URL?) {
        guard let key, Self.validKey(key) else { return (html, nil) }
        var result = html
        var embeddedBytes = 0
        queue.sync {
            for (remote, filename) in loadMappingLocked(key).sorted(by: { $0.key.count > $1.key.count }) where result.contains(remote) {
                let file = directory(key).appendingPathComponent(filename)
                guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0, size <= 2 * 1024 * 1024, embeddedBytes + size <= 4 * 1024 * 1024 else { continue }
                // Replacing the same src repeatedly multiplies base64 bytes.
                // Bound the resulting document as well as source image bytes.
                var occurrences = 0
                var search = result.startIndex..<result.endIndex
                while let range = result.range(of: remote, range: search) {
                    occurrences += 1
                    if occurrences > 64 { break }
                    search = range.upperBound..<result.endIndex
                }
                let encodedEstimate = ((size + 2) / 3) * 4 + 64
                guard occurrences <= 64, result.utf8.count + occurrences * max(0, encodedEstimate - remote.utf8.count) <= 8 * 1024 * 1024,
                      let data = try? Data(contentsOf: file), data.count == size else { continue }
                embeddedBytes += data.count
                let mime = filename.hasSuffix(".png") ? "image/png" : filename.hasSuffix(".gif") ? "image/gif" : filename.hasSuffix(".webp") ? "image/webp" : "image/jpeg"
                result = result.replacingOccurrences(of: remote, with: "data:\(mime);base64,\(data.base64EncodedString())")
            }
        }
        return (result, nil)
    }
    func localFileURL(forRemote remote: String, contentKey: String) -> URL? {
        guard Self.validKey(contentKey) else { return nil }
        return queue.sync {
            guard let filename = loadMappingLocked(contentKey)[remote] else { return nil }
            let path = directory(contentKey).appendingPathComponent(filename)
            return fileManager.fileExists(atPath: path.path) ? path : nil
        }
    }
    func scheduleCacheImages(for article: Article, contentKey: String) {
        guard Self.validKey(contentKey) else { return }
        let ticket = UUID()
        let start = queue.sync { () -> Bool in
            guard active[contentKey] == nil else { return false }
            active[contentKey] = ticket; return true
        }
        guard start else { return }
        let imageWidth = ArticleHTMLProcessor.capturedImageWidth()
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let urls = Array(Self.imageURLStrings(for: article, targetImageWidth: imageWidth).sorted().prefix(24))
            defer { self.queue.sync { if self.active[contentKey] == ticket { self.active.removeValue(forKey: contentKey) } } }
            for raw in urls {
                guard self.queue.sync(execute: { self.active[contentKey] == ticket }) else { return }
                if self.localFileURL(forRemote: raw, contentKey: contentKey) != nil { continue }
                guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { continue }
                do {
                    let artifact = try await self.download(url)
                    guard let response = artifact.response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                          response.url?.scheme?.lowercased() == "https", !artifact.data.isEmpty, artifact.data.count <= 10 * 1024 * 1024,
                          let ext = Self.imageExtension(response.mimeType) else { continue }
                    self.queue.sync {
                        guard self.active[contentKey] == ticket else { return }
                        let filename = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined() + "." + ext
                        do {
                            try self.fileManager.createDirectory(at: self.directory(contentKey), withIntermediateDirectories: true)
                            try artifact.data.write(to: self.directory(contentKey).appendingPathComponent(filename), options: .atomic)
                            self.invalidatePreparedDisplays()
                            var mapping = self.loadMappingLocked(contentKey); mapping[raw] = filename
                            try JSONEncoder().encode(mapping).write(to: self.directory(contentKey).appendingPathComponent("mapping.json"), options: .atomic)
                        } catch { AppDiagnostics.recordOperational(.imageDownloadFailed) }
                    }
                } catch { AppDiagnostics.recordOperational(.imageDownloadFailed) }
            }
        }
    }
    /// Explicit cache eviction only; owner transitions never call global eviction.
    func removeContent(_ contentKey: String) {
        guard Self.validKey(contentKey) else { return }
        queue.sync { active.removeValue(forKey: contentKey); try? fileManager.removeItem(at: directory(contentKey)); invalidatePreparedDisplays() }
    }
    func removeAllCachedImages() {
        queue.sync { active.removeAll(); try? fileManager.removeItem(at: rootDirectory); invalidatePreparedDisplays() }
    }
    func totalCacheSizeBytes() -> Int64 {
        queue.sync {
            guard let enumerator = fileManager.enumerator(at: rootDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            return enumerator.compactMap { $0 as? URL }.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }
    private func loadMappingLocked(_ key: String) -> [String: String] {
        mappingReadObserver?()
        let path = directory(key).appendingPathComponent("mapping.json")
        guard let size = (try? path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 128 * 1024,
              let data = try? Data(contentsOf: path), let map = try? JSONDecoder().decode([String: String].self, from: data), map.count <= 48,
              map.values.allSatisfy({ value in
                  let parts = value.split(separator: ".")
                  return parts.count == 2 && Self.validKey(String(parts[0])) && ["jpg", "png", "webp", "gif"].contains(String(parts[1]))
              }) else { return [:] }
        return map
    }
    private static func imageExtension(_ mime: String?) -> String? {
        switch mime?.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        default: return nil
        }
    }
    private static func imageURLStrings(for article: Article, targetImageWidth: Int) -> [String] {
        var urls = Set<String>()

        func add(_ urlString: String?) {
            guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty,
                  urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else {
                return
            }
            urls.insert(urlString)
            urls.insert(ArticleHTMLProcessor.optimizedImageURL(from: urlString, targetWidth: targetImageWidth))
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
            let processed = ArticleHTMLProcessor.process(cleaned, targetImageWidth: targetImageWidth)
            for url in ArticleHTMLProcessor.imageURLs(in: processed) {
                add(url)
            }
            for url in ArticleHTMLProcessor.imageURLs(in: cleaned) {
                add(url)
            }
        }

        return Array(urls)
    }

}

private final class OfflineImageDisplayEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch = UUID()
    var value: UUID { lock.lock(); defer { lock.unlock() }; return epoch }
    func advance() { lock.lock(); epoch = UUID(); lock.unlock() }
}

private final class OfflineImageDisplayCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var boundID: UUID?
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var waiterID: UUID? { lock.lock(); defer { lock.unlock() }; return boundID }
    func bind(_ id: UUID) { lock.lock(); boundID = id; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
