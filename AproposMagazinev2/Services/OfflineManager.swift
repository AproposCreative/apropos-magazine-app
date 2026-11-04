import Foundation
import Network
import SwiftUI
import Combine
import CryptoKit

@MainActor
final class OfflineManager: ObservableObject {
    @Published var isOnline = true
    @Published var isExpensiveConnection = false
    @Published var isConstrainedConnection = false
    @Published var syncInProgress = false
    @Published var lastSyncDate: Date?
    @Published private(set) var offlineRevision = UUID()
    var allowsHeavyDownloads: Bool { isOnline && !isExpensiveConnection && !isConstrainedConnection }
    static let shared = OfflineManager()
    private let monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "OfflineManager.NetworkMonitor")
    private var audioCacheObserver: AudioCacheObservation?
    private var bodyStatusObservation: AnyCancellable?
    private var bodyStatusRefresh: Task<Void, Never>?
    private let coordinatorProvider: @MainActor () -> FavoritesOfflineCoordinator?
    private let recoverAudioDownloads: @MainActor () -> Void
    private let resolveAudioAsset: @MainActor (PodcastEpisode, String?) -> PodcastAudioAsset?
    private var coordinator: FavoritesOfflineCoordinator? { coordinatorProvider() }

    private init() {
        coordinatorProvider = { FavoritesRuntime.shared.offline }
        recoverAudioDownloads = { PodcastAudioCache.shared.retryPinnedDownloads() }
        resolveAudioAsset = { PodcastRepository.shared.audioAsset(for: $0, articleID: $1) }
        // Unit/smoke startup never starts connectivity/background services.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !LocalSmokeMode.isEnabled else { monitor = nil; return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        audioCacheObserver = AudioCacheObservation { [weak self] in
            Task { @MainActor [weak self] in self?.refreshAudioStatus() }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isExpensiveConnection = path.isExpensive
                self?.isConstrainedConnection = path.isConstrained
            }
        }
        monitor.start(queue: monitorQueue)
    }
    /// The same observable presentation adapter with fully local ownership.
    /// No shared runtime, network monitor or audio service is touched.
    init(coordinator: FavoritesOfflineCoordinator,
         audioAsset: @escaping @MainActor (PodcastEpisode, String?) -> PodcastAudioAsset? = { _, _ in nil },
         recoverAudioDownloads: @escaping @MainActor () -> Void = {}) {
        coordinatorProvider = { coordinator }
        self.recoverAudioDownloads = recoverAudioDownloads
        resolveAudioAsset = audioAsset
        monitor = nil
        observeBodyStatus(coordinator)
    }
    deinit { monitor?.cancel() }

    /// Immutable ownership avoids crossing an actor boundary with NSObject's
    /// non-Sendable token during manager deinit. It removes only its own handle.
    private final class AudioCacheObservation {
        private let token: NSObjectProtocol
        init(_ changed: @escaping @Sendable () -> Void) {
            token = NotificationCenter.default.addObserver(forName: .podcastAudioCacheDidChange,
                object: nil, queue: .main) { _ in changed() }
        }
        deinit { NotificationCenter.default.removeObserver(token) }
    }

    static func makeFavoritesCoordinator(model: FavoritesModel) -> FavoritesOfflineCoordinator {
        let coordinator = makeFavoritesCoordinator(model: model, bodies: BodyStorage(),
            images: { OfflineArticleImageCache.shared }, audio: { PodcastAudioCache.shared },
            permitsBody: { ArticleAvailabilityService.model.permitsBody($0) },
            audioAsset: { PodcastRepository.shared.audioAsset(for: $0) }, scheduleRetry: { delay, action in
                let task = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                    guard !Task.isCancelled else { return }
                    action()
                }
                return { task.cancel() }
            })
        // The live observer remains outside the fully injected composition.
        shared.observeBodyStatus(coordinator)
        return coordinator
    }

    /// The production adapter wiring with local stores/providers for hermetic
    /// filesystem checks. Merely composing this overload starts no singleton.
    static func makeFavoritesCoordinator(model: FavoritesModel, bodies: BodyStorage,
        images: @escaping @MainActor () -> OfflineArticleImageCache,
        audio: @escaping @MainActor () -> PodcastAudioCache,
        permitsBody: @escaping @MainActor (Article) -> Bool,
        audioAsset: @escaping @MainActor (Article) -> PodcastAudioAsset?,
        scheduleRetry: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> FavoritesOfflineCoordinator.Cancel
    ) -> FavoritesOfflineCoordinator {
        FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { try bodies.read($0) }, write: { try bodies.write($0, article: $1) },
                contains: { try bodies.contains($0) }, probe: { key, complete in bodies.probe(key, complete: complete) },
                remove: { try bodies.remove($0) }),
            permitsBody: permitsBody, effects: .init(cacheImages: { article, key in
                images().scheduleCacheImages(for: article, contentKey: key)
            }, audioAsset: audioAsset, audioIsCached: { audio().isDownloaded(for: $0) }, pinAudio: { key, lease, asset in
                audio().pinAndDownload(pinKey: key, leaseID: lease, asset: asset)
            }, releaseAudio: { key, lease, asset in
                audio().releasePinKeepingBytes(pinKey: key, leaseID: lease, onlyIfAsset: asset)
            }, scheduleRetry: scheduleRetry, audioState: { asset in
                switch audio().downloadState(for: asset) {
                case .notDownloaded, .waiting: return .waiting
                case .checking: return .checking
                case .downloading: return .downloading
                case .available: return .available
                case .failed: return .failed
                case .storageLimit: return .storageLimit
                case .disabled: return .disabled
                }
            }, audioProgress: { audio().downloadProgress(for: $0) },
            removeImages: { images().removeContent($0) },
            removeAudio: { audio().removeUnpinnedAudio(for: [$0]) }))
    }

    private func observeBodyStatus(_ coordinator: FavoritesOfflineCoordinator) {
        bodyStatusObservation = coordinator.bodyChanges.sink { [weak self] in
            self?.queueBodyStatusRefresh()
        }
    }

    private func queueBodyStatusRefresh() {
        guard bodyStatusRefresh == nil else { return }
        // captureAccess may revoke a previous lease while a view is evaluating.
        // Defer only the redraw, never the coordinator's synchronous revocation.
        bodyStatusRefresh = Task { @MainActor [weak self] in
            guard let self else { return }
            self.bodyStatusRefresh = nil
            self.offlineRevision = UUID()
        }
    }

    func refreshAudioStatus() { queueBodyStatusRefresh() }

    /// @Published delivers before its wrapped value commits. Defer this one
    /// lifecycle event, then read actual online/scene state rather than the
    /// earlier emitted value. No retry state, timer or repeating work is kept.
    @discardableResult
    func performAfterOnlinePublication(isActive: @escaping @MainActor () -> Bool,
                                       perform: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self, isActive(), self.isOnline else { return }
            perform()
        }
    }

    /// Called by explicit online/foreground/user recovery events, never by a
    /// status redraw. Current membership is reconciled before retry admission.
    func recoverSavedAudioDownloads() {
        guard isOnline, let original = coordinator else { return }
        let generation = original.libraryMembershipIdentity.generation
        original.synchronizeCurrentMembership()
        guard isOnline, coordinator === original, original.libraryMembershipIdentity.generation == generation else { return }
        recoverAudioDownloads()
        refreshAudioStatus()
    }

    func captureAccess(articleID: String) -> FavoritesOfflineCoordinator.AccessTicket? { coordinator?.captureAccess(articleID: articleID) }
    func isCurrentAccess(_ ticket: FavoritesOfflineCoordinator.AccessTicket) -> Bool { coordinator?.isCurrent(ticket) == true }
    var currentAccessTickets: [FavoritesOfflineCoordinator.AccessTicket] { coordinator?.currentAccessTickets ?? [] }
    func bodyState(ticket: FavoritesOfflineCoordinator.AccessTicket) -> FavoritesOfflineCoordinator.BodyState? {
        coordinator?.bodyState(ticket: ticket)
    }
    var libraryBodySummary: FavoritesOfflineCoordinator.LibraryBodySummary? { coordinator?.libraryBodySummary }
    var libraryOfflineSummary: FavoritesOfflineCoordinator.LibraryOfflineSummary? { coordinator?.libraryOfflineSummary }
    func audioState(ticket: FavoritesOfflineCoordinator.AccessTicket) -> FavoritesOfflineCoordinator.AudioState? {
        coordinator?.audioState(ticket: ticket)
    }
    func audioProgress(ticket: FavoritesOfflineCoordinator.AccessTicket) -> Double? {
        coordinator?.audioProgress(ticket: ticket)
    }
    var libraryMembershipIdentity: FavoritesOfflineCoordinator.LibraryMembershipIdentity? { coordinator?.libraryMembershipIdentity }
    @discardableResult
    func prepareLibraryBodyStatus(force: Bool = false) -> FavoritesOfflineCoordinator.LibraryRefreshHandle? {
        coordinator?.prepareLibraryBodyStatus(force: force)
    }
    func cancelLibraryBodyStatus(_ handle: FavoritesOfflineCoordinator.LibraryRefreshHandle) {
        coordinator?.cancelLibraryBodyStatus(handle)
    }
    @discardableResult
    func prepareBodyStatus(ticket: FavoritesOfflineCoordinator.AccessTicket, force: Bool = false) -> Bool {
        coordinator?.prepareBodyStatus(ticket: ticket, force: force) ?? false
    }
    @discardableResult
    func requestBody(ticket: FavoritesOfflineCoordinator.AccessTicket, candidate: Article? = nil,
                     fetch: @escaping FavoritesOfflineCoordinator.FetchBody) -> Bool {
        coordinator?.requestBody(ticket: ticket, candidate: candidate, fetch: fetch) ?? false
    }
    @discardableResult
    func retryBody(ticket: FavoritesOfflineCoordinator.AccessTicket,
                   fetch: @escaping FavoritesOfflineCoordinator.FetchBody) -> Bool {
        coordinator?.retryBody(ticket: ticket, fetch: fetch) ?? false
    }
    @discardableResult
    func saveArticleForOffline(_ article: Article, ticket: FavoritesOfflineCoordinator.AccessTicket) -> Bool {
        guard coordinator?.saveBody(article, ticket: ticket) == true else { return false }
        offlineRevision = UUID()
        return coordinator?.isCurrent(ticket) == true
    }
    func offlineArticle(articleID: String) -> Article? { coordinator?.body(articleID: articleID) }
    func getOfflineArticles() -> [Article] { coordinator?.currentBodies ?? [] }
    func synchronizeCurrentMembership() { coordinator?.synchronizeCurrentMembership() }
    func removeArticleFromOffline(_ articleId: String) { coordinator?.releaseArticleAccess(articleID: articleId) }
    func removePodcastFromOffline(_ articleId: String) { coordinator?.releaseArticleAccess(articleID: articleId) }
    @discardableResult
    func savePodcastForOffline(ticket: FavoritesOfflineCoordinator.AccessTicket, asset: PodcastAudioAsset) -> Bool {
        coordinator?.cacheAudio(ticket, asset: asset) ?? false
    }
    func savePodcastsForOffline(tickets: [FavoritesOfflineCoordinator.AccessTicket]) {
        for ticket in tickets { _ = coordinator?.cacheAudio(ticket) }
    }
    func isSavedForOffline(articleId: String) -> Bool { captureAccess(articleID: articleId) != nil }
    func hasReadableOfflineBody(articleId: String, expectedRevision: String? = nil) -> Bool {
        coordinator?.hasBody(articleID: articleId, expectedRevision: expectedRevision) ?? false
    }
    func isArticleAvailableOffline(_ articleId: String) -> Bool { hasReadableOfflineBody(articleId: articleId) }
    func offlineImageContentKey(articleID: String, expectedRevision: String?) -> String? {
        guard let expectedRevision, let ticket = captureAccess(articleID: articleID), ticket.contentRevision == expectedRevision else { return nil }
        return ticket.contentKey
    }
    func isAudioDownloaded(articleID: String, expectedRevision: String? = nil, expectedAsset: PodcastAudioAsset? = nil) -> Bool {
        coordinator?.audioDownloaded(articleID: articleID, expectedRevision: expectedRevision, expectedAsset: expectedAsset) ?? false
    }
    func isAudioDownloaded(episode: PodcastEpisode?, articleID: String? = nil) -> Bool {
        guard let episode, let owner = coordinator, let asset = resolveAudioAsset(episode, articleID),
              articleID.map({ $0 == asset.canonicalArticleID }) ?? true,
              episode.articleId.map({ $0 == asset.canonicalArticleID }) ?? true,
              coordinator === owner, let ticket = owner.captureAccess(articleID: asset.canonicalArticleID),
              coordinator === owner, owner.isCurrent(ticket) else { return false }
        let downloaded = owner.audioDownloaded(articleID: asset.canonicalArticleID,
            expectedRevision: ticket.contentRevision, expectedAsset: asset)
        return downloaded && coordinator === owner && owner.isCurrent(ticket)
    }
    /// No disk access or hashing: a cold descriptor is a miss until explicitly
    /// prepared off-main. Public cached bytes alone never imply membership.
    func resolvePlaybackURL(asset: PodcastAudioAsset, articleID: String?) -> PodcastPlaybackURLResolution {
        guard let articleID, isAudioDownloaded(articleID: articleID, expectedAsset: asset) else {
            return PodcastPlaybackURLResolution(url: asset.remoteURL, cacheResult: .miss)
        }
        return PodcastAudioCache.shared.resolvePlaybackURL(for: asset)
    }
    func preparePlaybackAsset(_ asset: PodcastAudioAsset, articleID: String) async -> Bool {
        guard let owner = coordinator, let ticket = owner.captureAccess(articleID: articleID),
              owner.acceptedAudioAsset(ticket) == asset else { return false }
        let prepared = await PodcastAudioCache.shared.prepare(asset)
        guard coordinator === owner, owner.isCurrent(ticket), owner.acceptedAudioAsset(ticket) == asset else { return false }
        return prepared
    }

    // Unowned legacy snapshots/actions cannot authorize reads or server writes.
    // Keep their persisted bytes intact until an explicit migration is approved.
    func syncWhenOnline() {}
    func processPendingActions() {}
    func addPendingAction(_ action: PendingAction) {}
    func clearOfflineStorage() { coordinator?.releaseCurrentAccess() }
    func getOfflineStorageSize() -> String {
        let size = getOfflineArticles().reduce(0) { $0 + ((try? JSONEncoder().encode($1).count) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Immutable filesystem adapter. Display probes run on one utility queue;
    /// the coordinator bounds outstanding work and owns result acceptance.
    /// Explicit reads/writes keep their existing synchronous action semantics.
    final class BodyStorage: @unchecked Sendable {
        private let rootDirectory: URL?
        private let legacyDirectory: URL?
        private let probeCheck: (@Sendable (String) throws -> Bool)?
        private let probeQueue = DispatchQueue(label: "com.aproposmagazine.offline-body-status", qos: .utility)
        private let fileLock = NSLock()

        nonisolated init(directory: URL? = nil, legacyDirectory: URL? = nil,
                         probeCheck: (@Sendable (String) throws -> Bool)? = nil) {
            rootDirectory = directory
            // An injected directory is fully local unless its legacy fixture is
            // also supplied. Tests never discover the user's real old cache.
            self.legacyDirectory = legacyDirectory ?? (directory == nil ? OfflineDownloadLocations.legacyBodyDirectory : nil)
            self.probeCheck = probeCheck
        }
        private nonisolated var directory: URL {
            rootDirectory ?? OfflineDownloadLocations.bodyDirectory
        }
        private nonisolated func url(_ key: String, in root: URL? = nil) throws -> URL {
            guard key.count == 64, key.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw Failure.invalid }
            return (root ?? directory).appendingPathComponent(key).appendingPathExtension("json")
        }
        func read(_ key: String) throws -> Article? {
            fileLock.lock(); defer { fileLock.unlock() }
            let path = try url(key)
            guard FileManager.default.fileExists(atPath: path.path) else { return try migrateLegacy(key) }
            return try decodedBody(at: path, key: key).article
        }
        private nonisolated func decodedBody(at path: URL, key: String) throws -> (article: Article, data: Data) {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            let maximumBytes = FavoritesOfflineCoordinator.maximumBodyBytes + 512_000
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0,
                  size.intValue <= maximumBytes else { throw Failure.invalid }
            // The attributes are only a prefilter. A file can grow after stat;
            // one bounded read must reject that instead of allocating its tail.
            let data = try boundedRead(path, maximumBytes: maximumBytes)
            guard data.count == size.intValue else { throw Failure.invalid }
            let article = try JSONDecoder().decode(Article.self, from: data)
            try validate(article, key: key)
            return (article, data)
        }
        private nonisolated func validate(_ article: Article, key: String) throws {
            guard !article.id.isEmpty, let revision = article.bodyRevision, !revision.isEmpty,
                  let content = article.content, !content.isEmpty,
                  content.utf8.count <= FavoritesOfflineCoordinator.maximumBodyBytes else { throw Failure.invalid }
            // This is the existing coordinator descriptor, not account access.
            // The coordinator still owns membership/publication acceptance.
            let input = [article.id, revision].map { "\($0.utf8.count):\($0)" }.joined()
            let expected = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
            guard key == expected else { throw Failure.invalid }
        }
        private nonisolated func markerMatches(_ path: URL) -> Bool {
            let markerPath = path.appendingPathExtension("size")
            guard let markerAttributes = try? FileManager.default.attributesOfItem(atPath: markerPath.path),
                  markerAttributes[.type] as? FileAttributeType == .typeRegular,
                  let markerSize = markerAttributes[.size] as? NSNumber, markerSize.intValue > 0, markerSize.intValue <= 20,
                  let marker = try? boundedRead(markerPath, maximumBytes: 20), marker.count == markerSize.intValue,
                  let string = String(data: marker, encoding: .utf8), let size = Int(string),
                  size > 0, size <= FavoritesOfflineCoordinator.maximumBodyBytes + 512_000,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
                  (attributes[.size] as? NSNumber)?.intValue == size else { return false }
            return true
        }
        private nonisolated func boundedRead(_ path: URL, maximumBytes: Int) throws -> Data {
            let handle = try FileHandle(forReadingFrom: path)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard data.count <= maximumBytes else { throw Failure.invalid }
            return data
        }
        nonisolated func contains(_ key: String) throws -> Bool {
            fileLock.lock(); defer { fileLock.unlock() }
            let path = try url(key)
            guard FileManager.default.fileExists(atPath: path.path) else { return (try? migrateLegacy(key)) != nil }
            guard markerMatches(path) else { return false }
            return (try? decodedBody(at: path, key: key)) != nil
        }
        /// Only the exact requested 151 descriptor is eligible. Preserve the
        /// old bytes; no inventory scan, delete API or storage-schema change.
        private nonisolated func migrateLegacy(_ key: String) throws -> Article? {
            guard let legacyDirectory else { return nil }
            let old = try url(key, in: legacyDirectory)
            let current = try url(key)
            guard old != current, markerMatches(old) else { return nil }
            let decoded = try decodedBody(at: old, key: key)
            try OfflineDownloadLocations.prepareDirectory(directory)
            let staged = directory.appendingPathComponent(UUID().uuidString + ".body-migration")
            let stagedMarker = staged.appendingPathExtension("size")
            defer {
                try? FileManager.default.removeItem(at: staged)
                try? FileManager.default.removeItem(at: stagedMarker)
            }
            try decoded.data.write(to: staged, options: .atomic)
            try OfflineDownloadLocations.prepareFile(staged)
            try Data(String(decoded.data.count).utf8).write(to: stagedMarker, options: .atomic)
            try OfflineDownloadLocations.prepareFile(stagedMarker)
            // Another storage instance may publish after our initial lookup.
            // Hard-link publication is exclusive: migration never replaces a
            // durable winner or its receipt, even when that winner is invalid.
            do { try FileManager.default.linkItem(at: staged, to: current) }
            catch {
                if markerMatches(current) { return try decodedBody(at: current, key: key).article }
                throw error
            }
            do { try FileManager.default.linkItem(at: stagedMarker, to: current.appendingPathExtension("size")) }
            catch {
                if markerMatches(current) { return try decodedBody(at: current, key: key).article }
                throw error
            }
            guard markerMatches(current) else { throw Failure.invalid }
            return try decodedBody(at: current, key: key).article
        }
        func probe(_ key: String, complete: @escaping @MainActor (Result<Bool, Error>) -> Void) {
            probeQueue.async { [self] in
                let result = Result { try probeCheck?(key) ?? contains(key) }
                Task { @MainActor in complete(result) }
            }
        }
        func write(_ key: String, article: Article) throws {
            fileLock.lock(); defer { fileLock.unlock() }
            let path = try url(key)
            try validate(article, key: key)
            let data = try JSONEncoder().encode(article)
            guard data.count <= FavoritesOfflineCoordinator.maximumBodyBytes + 512_000 else { throw Failure.invalid }
            try store(data, at: path)
        }
        /// Explicit favorite removal owns only this validated descriptor. The
        /// old copy and size marker must go too, so migration cannot revive it.
        func remove(_ key: String) throws {
            fileLock.lock(); defer { fileLock.unlock() }
            var paths = [try url(key)]
            if let legacyDirectory {
                let legacy = try url(key, in: legacyDirectory)
                if legacy.standardizedFileURL != paths[0].standardizedFileURL { paths.append(legacy) }
            }
            var failure: Error?
            for path in paths {
                for file in [path, path.appendingPathExtension("size")] {
                    do { try FileManager.default.removeItem(at: file) }
                    catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { }
                    catch { if failure == nil { failure = error } }
                }
            }
            if let failure { throw failure }
        }

        private nonisolated func store(_ data: Data, at path: URL) throws {
            try OfflineDownloadLocations.prepareDirectory(directory)
            try data.write(to: path, options: .atomic)
            try OfflineDownloadLocations.prepareFile(path)
            let marker = path.appendingPathExtension("size")
            try Data(String(data.count).utf8).write(to: marker, options: .atomic)
            try OfflineDownloadLocations.prepareFile(marker)
        }
        private enum Failure: Error { case invalid }
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
