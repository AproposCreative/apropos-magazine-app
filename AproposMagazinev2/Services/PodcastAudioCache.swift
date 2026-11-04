import CryptoKit
import Foundation

enum PodcastAudioCacheResult: String { case hit, miss, disabled }
struct PodcastPlaybackURLResolution { let url: URL; let cacheResult: PodcastAudioCacheResult }
extension Notification.Name { static let podcastAudioCacheDidChange = Notification.Name("PodcastAudioCacheDidChange") }

/// Metadata locks never perform filesystem, decoding or hashing work. The serial
/// I/O queue validates/commits v2 receipts off-main. Cancellation revokes commit
/// authority immediately but retains an actual transport slot until it returns.
final class PodcastAudioCache: @unchecked Sendable {
    struct DownloadArtifact { let temporaryURL: URL; let response: URLResponse }
    enum DownloadEvent: Equatable { case saved, failed, discarded }
    enum DownloadState: Equatable {
        case notDownloaded, waiting, checking, downloading, available, failed, storageLimit, disabled
    }
    private enum CommitFailure: Error { case storageLimit }
    typealias Download = @Sendable (URL) async throws -> DownloadArtifact
    typealias ProgressDownload = @Sendable (URL, @escaping PodcastAudioDownloadTransport.Progress) async throws -> DownloadArtifact
    static let shared: PodcastAudioCache = {
        return PodcastAudioCache(cacheDirectory: OfflineDownloadLocations.audioDirectory, defaults: .standard,
            legacyCacheDirectory: OfflineDownloadLocations.legacyAudioDirectory,
            enabled: { FeatureFlags.podcastDiskCacheEnabled }, maxBytes: { Int64(max(50, min(2048, FeatureFlags.podcastDiskCacheMaxMB))) * 1024 * 1024 },
            download: { url in
                let result = try await PodcastAudioDownloadTransport.download(from: url,
                    maximumBytes: min(PodcastAudioReceipt.maximumAudioBytes, Int64(max(50, min(2048, FeatureFlags.podcastDiskCacheMaxMB))) * 1024 * 1024))
                return DownloadArtifact(temporaryURL: result.temporaryURL, response: result.response)
            }, progressDownload: { url, progress in
                let result = try await PodcastAudioDownloadTransport.download(from: url,
                    maximumBytes: min(PodcastAudioReceipt.maximumAudioBytes, Int64(max(50, min(2048, FeatureFlags.podcastDiskCacheMaxMB))) * 1024 * 1024),
                    onProgress: progress)
                return DownloadArtifact(temporaryURL: result.temporaryURL, response: result.response)
            }, onEvent: { event in
                if event == .saved { AppDiagnostics.breadcrumb("podcast_cache_saved") }
                else if event == .failed { AppDiagnostics.breadcrumb("podcast_cache_download_failed") }
            }, onIndexChange: {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .podcastAudioCacheDidChange, object: nil) }
            })
    }()
    private struct Proof {
        let receipt: PodcastAudioReceipt
        let file: URL
        var accessed: TimeInterval
    }
    private final class Validation: @unchecked Sendable {
        let asset: PodcastAudioAsset
        let generation: UUID
        var valid = true
        var downloadAfter = false
        var waiters: [CheckedContinuation<Bool, Never>] = []
        init(_ asset: PodcastAudioAsset, generation: UUID) { self.asset = asset;self.generation = generation }
    }
    private struct Request { let asset: PodcastAudioAsset; let generation: UUID }
    private struct Eviction { let key: String; let id: UUID }
    private struct EvictionBatch {
        var changed = false
        var reservations: [Eviction] = []
        var tasks: [Task<Void, Never>] = []
        var waiters: [CheckedContinuation<Bool, Never>] = []
    }
    private final class Active: @unchecked Sendable {
        let request: Request
        let id = UUID()
        var valid = true
        var task: Task<Void, Never>?
        var receivedBytes: Int64 = 0
        var expectedBytes: Int64?
        var announcedPercent: Int?
        init(_ request: Request) { self.request = request }
    }
    private let lock = NSLock()
    private let io = DispatchQueue(label: "com.aproposmagazine.audio-assets-v2.io", qos: .utility)
    private let directory: URL
    private let legacyDirectory: URL?
    private let enabled: @Sendable () -> Bool
    private let maxBytes: @Sendable () -> Int64
    private let download: Download
    private let progressDownload: ProgressDownload?
    private let onEvent: @Sendable (DownloadEvent) -> Void
    private let onIndexChange: @Sendable () -> Void
    private let maximumConcurrentDownloads: Int
    private let manager = FileManager.default
    private var generation = UUID()
    private var proofs: [String: Proof] = [:]
    private var pins: [String: (asset: PodcastAudioAsset, lease: UUID)] = [:]
    private var active: [String: Active] = [:]
    private var pending: [Request] = []
    private var validating: [String: Validation] = [:]
    private var validations: [Validation] = []
    private var waiterCount = 0
    private var revoked: Set<String> = []
    private var admissionClosed = false
    private var evicting: [String: UUID] = [:]
    // Only current pins form the refill wish list. An admitted attempt is finite:
    // neither a failed download nor memory-proof eviction can spin the refill.
    private var attemptedPins: Set<String> = []
    private var terminalStates: [String: DownloadState] = [:]
    private var statusRevision: UInt64 = 0
    private static let maximumEvictions = 1024
    private static let maximumIndexEntries = 256
    private static let maximumPins = 512
    private static let maximumPending = 64
    private static let maximumWaiters = 64

    /// defaults is retained as an injection compatibility parameter only. Only
    /// exact v2 receipts can migrate; v1 URL files/maps/pins remain untouched.
    init(cacheDirectory: URL, defaults: UserDefaults,
         legacyCacheDirectory: URL? = nil,
         enabled: @escaping @Sendable () -> Bool = { true }, maxBytes: @escaping @Sendable () -> Int64 = { 120 * 1024 * 1024 },
         maximumConcurrentDownloads: Int = 2, download: @escaping Download, progressDownload: ProgressDownload? = nil,
         onEvent: @escaping @Sendable (DownloadEvent) -> Void = { _ in }, onIndexChange: @escaping @Sendable () -> Void = {}) {
        directory = cacheDirectory.appendingPathComponent("assets-v2", isDirectory: true)
        legacyDirectory = legacyCacheDirectory.flatMap { legacy in
            legacy.standardizedFileURL == cacheDirectory.standardizedFileURL ? nil : legacy.appendingPathComponent("assets-v2", isDirectory: true)
        }
        self.enabled = enabled;self.maxBytes = maxBytes;self.maximumConcurrentDownloads = max(1, min(maximumConcurrentDownloads, 4))
        self.download = download;self.progressDownload = progressDownload;self.onEvent = onEvent;self.onIndexChange = onIndexChange
        _ = defaults
    }
    func resolvePlaybackURL(for asset: PodcastAudioAsset) -> PodcastPlaybackURLResolution {
        guard enabled() else { return .init(url: asset.remoteURL, cacheResult: .disabled) }
        return locked {
            guard !admissionClosed, evicting[asset.key] == nil, var proof = proofs[asset.key], proof.receipt.asset == asset, !revoked.contains(asset.key) else { return .init(url: asset.remoteURL, cacheResult: .miss) }
            proof.accessed = Date().timeIntervalSince1970;proofs[asset.key] = proof
            return .init(url: proof.file, cacheResult: .hit)
        }
    }
    func isDownloaded(for asset: PodcastAudioAsset) -> Bool {
        guard enabled() else { return false }
        return locked { !admissionClosed && evicting[asset.key] == nil && proofs[asset.key]?.receipt.asset == asset && !revoked.contains(asset.key) }
    }
    /// Memory-only presentation. A desired pin or successful transport alone is
    /// never proof that a complete, validated receipt is available on disk.
    func downloadState(for asset: PodcastAudioAsset) -> DownloadState {
        guard enabled() else { return .disabled }
        return locked {
            guard !admissionClosed else { return .failed }
            guard !revoked.contains(asset.key) else { return .notDownloaded }
            if evicting[asset.key] != nil { return pins.values.contains(where: { $0.asset == asset }) ? .waiting : .notDownloaded }
            if proofs[asset.key]?.receipt.asset == asset { return .available }
            if let work = active[asset.key], work.valid, work.request.generation == generation { return .downloading }
            if let work = validating[asset.key], work.valid, work.generation == generation { return .checking }
            if pending.contains(where: { $0.asset == asset && $0.generation == generation })
                || validations.contains(where: { $0.asset == asset && $0.valid && $0.generation == generation }) { return .waiting }
            if let terminal = terminalStates[asset.key] { return terminal }
            return pins.values.contains(where: { $0.asset == asset }) && !attemptedPins.contains(asset.key) ? .waiting : .notDownloaded
        }
    }

    /// Transfer progress is presentation only, never a durable receipt. Unknown
    /// lengths and unowned background warming have no percentage. Keep a fully
    /// received active file below one until its existing validated proof installs.
    func downloadProgress(for asset: PodcastAudioAsset) -> Double? {
        guard enabled() else { return nil }
        return locked {
            guard !admissionClosed, !revoked.contains(asset.key), evicting[asset.key] == nil,
                  pins.values.contains(where: { $0.asset == asset }) else { return nil }
            if proofs[asset.key]?.receipt.asset == asset { return 1 }
            guard let work = active[asset.key], work.request.asset == asset, downloadIsCurrentLocked(work),
                  let total = work.expectedBytes else { return nil }
            return min(Double(work.receivedBytes) / Double(total), Double(1).nextDown)
        }
    }

    /// One explicit recovery event permits one fresh attempt per current asset.
    /// Existing physical work remains coalesced and keeps its real slot.
    func retryPinnedDownloads() {
        guard enabled() else { return }
        let changed = locked { () -> Bool in
            let before = statusRevision
            for key in Set(pins.values.map { $0.asset.key }) where !revoked.contains(key) {
                attemptedPins.remove(key)
                if terminalStates.removeValue(forKey: key) != nil { statusRevision &+= 1 }
            }
            pumpLocked()
            return statusRevision != before
        }
        if changed { onIndexChange() }
    }
    /// Revalidates full bytes, even if status has a warm memory proof. Callers
    /// keep their original owner/asset ticket across this await before opening.
    func prepare(_ asset: PodcastAudioAsset) async -> Bool {
        guard enabled() else { return false }
        return await withCheckedContinuation { continuation in
            let result = locked { () -> (Bool, Bool) in
                let before = statusRevision
                guard !admissionClosed, !revoked.contains(asset.key), waiterCount < Self.maximumWaiters,
                      let work = validationLocked(asset, downloadAfter: false) else { return (false, false) }
                work.waiters.append(continuation);waiterCount += 1;pumpLocked();return (true, before != statusRevision)
            }
            if result.1 { onIndexChange() }
            if !result.0 { continuation.resume(returning: false) }
        }
    }
    func scheduleValidation(for asset: PodcastAudioAsset) {
        guard enabled() else { return }
        let changed = locked { () -> Bool in
            let before = statusRevision
            guard proofs[asset.key] == nil else { return false }
            _ = validationLocked(asset, downloadAfter: false);pumpLocked()
            return statusRevision != before
        }
        if changed { onIndexChange() }
    }
    func scheduleBackgroundDownload(for asset: PodcastAudioAsset) {
        guard enabled() else { return }
        let changed = locked { () -> Bool in
            let before = statusRevision
            guard proofs[asset.key] == nil, !revoked.contains(asset.key), !admissionClosed else { return false }
            if active[asset.key]?.valid == true || pending.contains(where: { $0.asset == asset }) { return false }
            if terminalStates.removeValue(forKey: asset.key) != nil { statusRevision &+= 1 }
            _ = validationLocked(asset, downloadAfter: true);pumpLocked()
            return statusRevision != before
        }
        if changed { onIndexChange() }
    }
    func pinAndDownload(pinKey: String, leaseID: UUID, asset: PodcastAudioAsset) {
        guard pinKey.hasPrefix("favorites-v1:"), pinKey.utf8.count <= 512, enabled() else { return }
        let changed = locked { () -> Bool in
            let before = statusRevision
            guard !revoked.contains(asset.key), !admissionClosed, pins[pinKey] != nil || pins.count < Self.maximumPins else { return false }
            if pins[pinKey]?.asset != asset || pins[pinKey]?.lease != leaseID {
                let previous = pins.updateValue((asset, leaseID), forKey: pinKey)
                statusRevision &+= 1
                attemptedPins.remove(asset.key)
                terminalStates.removeValue(forKey: asset.key)
                if let previous, !pins.values.contains(where: { $0.asset == previous.asset }) {
                    attemptedPins.remove(previous.asset.key)
                }
            }
            pumpLocked()
            return statusRevision != before
        }
        if changed { onIndexChange() }
    }
    func releasePinKeepingBytes(pinKey: String, leaseID: UUID, onlyIfAsset asset: PodcastAudioAsset) {
        let changed = locked { () -> Bool in
            guard let pin = pins[pinKey], pin.lease == leaseID, pin.asset == asset else { return false }
            pins.removeValue(forKey: pinKey)
            if !pins.values.contains(where: { $0.asset == asset }) {
                attemptedPins.remove(asset.key)
                if let work = active[asset.key] { work.receivedBytes = 0;work.expectedBytes = nil;work.announcedPercent = nil }
            }
            statusRevision &+= 1
            trimProofsLocked()
            pumpLocked()
            return true
        }
        if changed { onIndexChange() }
    }
    func isPinned(articleId: String) -> Bool { locked { pins[articleId] != nil } }
    func isDownloaded(forArticleId articleId: String) -> Bool {
        guard enabled() else { return false }
        return locked { !admissionClosed && (pins[articleId].map { evicting[$0.asset.key] == nil && !revoked.contains($0.asset.key) && proofs[$0.asset.key]?.receipt.asset == $0.asset } ?? false) }
    }
    func removeUnpinnedAudio(for assets: Set<PodcastAudioAsset>) {
        remove(assets, revoke: false)
    }
    func invalidate(_ assets: Set<PodcastAudioAsset>) { remove(assets, revoke: true) }
    func totalCacheSizeBytes() -> Int64 { locked { proofs.values.reduce(0) { $0 + $1.receipt.byteCount } } }
    var downloadActivity: (active: Int, waiting: Int) { locked { (active.count, pending.count + validations.filter(\.downloadAfter).count) } }
    var validationActivity: (active: Int, waiting: Int) { locked { (validating.count, validations.count) } }

    func removeAllCachedFiles() {
        let result = locked { () -> ([Task<Void, Never>], [CheckedContinuation<Bool, Never>]) in
            generation = UUID();proofs = [:];pins = [:];pending = [];attemptedPins = [];terminalStates = [:]
            statusRevision &+= 1
            let waiters = (Array(validating.values) + validations).flatMap(\.waiters)
            for work in Array(validating.values) + validations { work.valid = false;work.waiters = [] }
            validations = [];waiterCount -= waiters.count
            for work in active.values { work.valid = false }
            io.async { [self] in
                try? manager.removeItem(at: directory)
                if let legacyDirectory { try? manager.removeItem(at: legacyDirectory) }
            }
            return (active.values.compactMap(\.task), waiters)
        }
        result.0.forEach { $0.cancel() };result.1.forEach { $0.resume(returning: false) };onIndexChange()
    }
    // Legacy URL-only APIs intentionally confer no provenance or authority.
    func resolvePlaybackURL(for url: URL) -> PodcastPlaybackURLResolution { .init(url: url, cacheResult: enabled() ? .miss : .disabled) }
    func scheduleBackgroundDownload(from url: URL) {}
    func pinAndDownload(articleId: String, remoteURL: URL) {}
    func pinAndDownload(pinKey: String, leaseID: UUID, remoteURL: URL) {}
    func releasePinKeepingBytes(pinKey: String, leaseID: UUID, onlyIfURL: URL) {}
    func unpin(articleId: String, retainingURLs: Set<URL> = [], onlyIfURL: URL? = nil) {}
    func removeUnpinnedAudio(for urls: Set<URL>) {}
    func isDownloaded(for url: URL?) -> Bool { false }
    func isDownloaded(for episode: PodcastEpisode?) -> Bool { false }

    private func validationLocked(_ asset: PodcastAudioAsset, downloadAfter: Bool) -> Validation? {
        guard !admissionClosed, !revoked.contains(asset.key) else { return nil }
        let work: Validation
        if let existing = validating[asset.key], existing.valid { work = existing }
        else if let existing = validations.first(where: { $0.asset == asset && $0.valid }) { work = existing }
        else {
            // A physical validator reserves its eventual pending-download slot.
            // Otherwise late validations can lose admission behind a full queue.
            guard pending.count + validations.count + validating.count < Self.maximumPending else { return nil }
            work = Validation(asset, generation: generation);validations.append(work)
            statusRevision &+= 1
        }
        if downloadAfter && !work.downloadAfter { work.downloadAfter = true;statusRevision &+= 1 }
        return work
    }
    private func refillPinnedLocked() {
        guard !admissionClosed else { return }
        let assets = Dictionary(pins.values.map { ($0.asset.key, $0.asset) }, uniquingKeysWith: { first, _ in first })
        for key in assets.keys.sorted() {
            guard let asset = assets[key], !revoked.contains(key), evicting[key] == nil else { continue }
            if proofs[key]?.receipt.asset == asset { attemptedPins.insert(key);continue }
            guard !attemptedPins.contains(key), terminalStates[key] == nil else { continue }
            if active[key]?.valid == true || pending.contains(where: { $0.asset == asset && $0.generation == generation }) {
                attemptedPins.insert(key);continue
            }
            if validationLocked(asset, downloadAfter: true) != nil { attemptedPins.insert(key) }
        }
    }
    private func pumpLocked() {
        refillPinnedLocked()
        while validating.count < 2, let index = validations.firstIndex(where: { validating[$0.asset.key] == nil && evicting[$0.asset.key] == nil }) {
            let work = validations.remove(at: index)
            guard work.valid, work.generation == generation else { continue }
            validating[work.asset.key] = work
            statusRevision &+= 1
            io.async { [self] in
                let proof = try? readProof(work)
                finishValidation(work, proof: proof)
            }
        }
        while active.count < maximumConcurrentDownloads, let index = pending.firstIndex(where: { active[$0.asset.key] == nil && evicting[$0.asset.key] == nil }) {
            let request = pending.remove(at: index)
            guard request.generation == generation, !revoked.contains(request.asset.key), !admissionClosed else { continue }
            let work = Active(request);active[request.asset.key] = work
            statusRevision &+= 1
            work.task = Task.detached(priority: .utility) { [self, work] in
                let result: Result<DownloadArtifact, Error>
                do {
                    if let progressDownload {
                        result = .success(try await progressDownload(request.asset.remoteURL, { [weak self, weak work] received, total in
                            guard let self, let work else { return }
                            self.receiveProgress(work, received: received, total: total)
                        }))
                    } else { result = .success(try await download(request.asset.remoteURL)) }
                } catch { result = .failure(error) }
                io.async { [self] in finishDownload(work, result: result) }
            }
        }
    }
    private func receiveProgress(_ work: Active, received: Int64, total: Int64?) {
        guard enabled() else { return }
        let changed = locked { () -> Bool in
            guard downloadIsCurrentLocked(work), pins.values.contains(where: { $0.asset == work.request.asset }),
                  let total, total > 0, total <= PodcastAudioReceipt.maximumAudioBytes,
                  received >= 0, received <= total, received >= work.receivedBytes,
                  work.expectedBytes == nil || work.expectedBytes == total else { return false }
            work.expectedBytes = total;work.receivedBytes = received
            let percent = min(99, Int(received * 100 / total))
            guard work.announcedPercent != percent else { return false }
            work.announcedPercent = percent
            return true
        }
        // At most one redraw per changed integer percent; no timers, disk I/O,
        // hashing or task creation in the status query or progress callback.
        if changed { onIndexChange() }
    }
    private func finishValidation(_ work: Validation, proof: Proof?) {
        let result = locked { () -> (Bool, [CheckedContinuation<Bool, Never>], Bool) in
            guard validating[work.asset.key] === work else { return (false, [], false) }
            validating.removeValue(forKey: work.asset.key)
            statusRevision &+= 1
            let valid = work.valid && work.generation == generation && !revoked.contains(work.asset.key) && !admissionClosed && evicting[work.asset.key] == nil
            let success = valid && proof != nil
            if valid, let proof { installLocked(proof) }
            else if valid { proofs.removeValue(forKey: work.asset.key) }
            let waiters = work.waiters;work.waiters = [];waiterCount -= waiters.count
            if valid && !success && work.downloadAfter, pending.count + validations.count < Self.maximumPending,
               !pending.contains(where: { $0.asset == work.asset }) {
                pending.append(Request(asset: work.asset, generation: generation))
            }
            pumpLocked();return (success, waiters, true)
        }
        result.1.forEach { $0.resume(returning: result.0) }
        if result.2 { onIndexChange() }
    }
    private func finishDownload(_ work: Active, result: Result<DownloadArtifact, Error>) {
        let eligible = locked { downloadIsCurrentLocked(work) }
        var proof: Proof?
        var failure: DownloadState = .failed
        if eligible, case .success(let artifact) = result {
            do { proof = try commit(artifact, work: work) }
            catch CommitFailure.storageLimit { failure = .storageLimit }
            catch { }
        }
        if case .success(let artifact) = result { try? manager.removeItem(at: artifact.temporaryURL) }
        let event = locked { () -> DownloadEvent in
            guard active[work.request.asset.key] === work else { return .discarded }
            active.removeValue(forKey: work.request.asset.key)
            statusRevision &+= 1
            let valid = eligible && work.valid && work.request.generation == generation && !revoked.contains(work.request.asset.key) && !admissionClosed && evicting[work.request.asset.key] == nil
            if valid, let proof { installLocked(proof) }
            else if valid { recordTerminalStateLocked(failure, asset: work.request.asset) }
            pumpLocked();return valid ? (proof == nil ? .failed : .saved) : .discarded
        }
        if event == .saved { enforceDiskLimit() }
        onEvent(event);onIndexChange()
    }
    private func installLocked(_ proof: Proof) {
        proofs[proof.receipt.asset.key] = proof
        terminalStates.removeValue(forKey: proof.receipt.asset.key)
        statusRevision &+= 1
        trimProofsLocked()
    }
    private func trimProofsLocked() {
        let pinned = Set(pins.values.map { $0.asset.key })
        // Current saved audio is not made unavailable by an unrelated prefetch.
        // The pin cap still bounds protected proofs to at most512 descriptors.
        while proofs.count > Self.maximumIndexEntries,
              let oldest = proofs.filter({ !pinned.contains($0.key) }).min(by: { $0.value.accessed < $1.value.accessed })?.key {
            proofs.removeValue(forKey: oldest)
            statusRevision &+= 1
        }
    }
    private func recordTerminalStateLocked(_ state: DownloadState, asset: PodcastAudioAsset) {
        if terminalStates[asset.key] == nil, terminalStates.count >= Self.maximumPins,
           let old = terminalStates.keys.sorted().first(where: { key in !pins.values.contains(where: { $0.asset.key == key }) }) {
            terminalStates.removeValue(forKey: old)
        }
        if terminalStates[asset.key] != nil || terminalStates.count < Self.maximumPins {
            terminalStates[asset.key] = state
        }
    }
    private func downloadIsCurrentLocked(_ work: Active) -> Bool {
        active[work.request.asset.key] === work && work.valid && work.request.generation == generation &&
            !revoked.contains(work.request.asset.key) && !admissionClosed && evicting[work.request.asset.key] == nil
    }
    /// All deletion paths revoke the memory proof and reserve the exact key in
    /// the same lock transaction that checks pins. New pins retain their desired
    /// lease, but validation/transport cannot start until actual deletion retires.
    private func reserveEvictionsLocked(_ requested: Set<String>, respectingPins: Bool) -> EvictionBatch {
        let protected = respectingPins ? Set(pins.values.map { $0.asset.key }) : []
        let keys = requested.filter { evicting[$0] == nil && !protected.contains($0) }
        guard keys.count <= Self.maximumEvictions - evicting.count else {
            admissionClosed = true;proofs = [:];return EvictionBatch(changed: true)
        }
        var result = EvictionBatch(changed: !keys.isEmpty)
        for key in keys {
            let reservation = Eviction(key: key, id: UUID());evicting[key] = reservation.id;result.reservations.append(reservation)
            proofs.removeValue(forKey: key)
            if let work = active[key] { work.valid = false;if let task = work.task { result.tasks.append(task) } }
            if let work = validating[key] { work.valid = false;result.waiters += work.waiters;work.waiters = [] }
        }
        for work in validations where keys.contains(work.asset.key) { work.valid = false;result.waiters += work.waiters;work.waiters = [] }
        validations.removeAll { keys.contains($0.asset.key) };pending.removeAll { keys.contains($0.asset.key) }
        waiterCount -= result.waiters.count
        return result
    }
    private func announceEvictions(_ batch: EvictionBatch) {
        batch.tasks.forEach { $0.cancel() };batch.waiters.forEach { $0.resume(returning: false) }
        if batch.changed { onIndexChange() }
    }
    private func retireEvictions(_ batch: EvictionBatch) {
        let changed = locked { () -> Bool in
            let before = statusRevision
            for reservation in batch.reservations where evicting[reservation.key] == reservation.id {
                evicting.removeValue(forKey: reservation.key)
                attemptedPins.remove(reservation.key)
                statusRevision &+= 1
            }
            pumpLocked()
            return before != statusRevision
        }
        if changed { onIndexChange() }
    }
    private func remove(_ assets: Set<PodcastAudioAsset>, revoke: Bool) {
        guard !assets.isEmpty else { return }
        let batch = locked { () -> EvictionBatch in
            let keys = Set(assets.map(\.key))
            if revoke {
                for key in keys {
                    if revoked.count < Self.maximumPins || revoked.contains(key) { revoked.insert(key) }
                    else { admissionClosed = true;proofs = [:] }
                }
                pins = pins.filter { !keys.contains($0.value.asset.key) }
            }
            return reserveEvictionsLocked(keys, respectingPins: !revoke)
        }
        announceEvictions(batch)
        // pumpLocked skips the reservation even if a reentrant pin queued work
        // before this I/O block was submitted.
        io.async { [self] in
            let keys = Set(batch.reservations.map(\.key))
            for asset in assets where keys.contains(asset.key) { removeDisk(asset) }
            retireEvictions(batch)
        }
    }
    private func receiptURL(_ asset: PodcastAudioAsset) -> URL { directory.appendingPathComponent(asset.key + ".json") }
    private func regularSize(_ url: URL) throws -> Int64 {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? NSNumber else { throw PodcastAudioReceipt.Failure.invalid }
        return size.int64Value
    }
    private func readProof(_ asset: PodcastAudioAsset, in root: URL) throws -> Proof {
        let url = root.appendingPathComponent(asset.key + ".json")
        let size = try regularSize(url)
        guard size > 0, size <= PodcastAudioReceipt.maximumBytes else { throw PodcastAudioReceipt.Failure.invalid }
        let receipt = try PodcastAudioReceipt.decode(boundedData(url), expectedAsset: asset)
        guard receipt.byteCount <= max(0, maxBytes()) else { throw PodcastAudioReceipt.Failure.invalid }
        let file = root.appendingPathComponent(receipt.fileName)
        guard try regularSize(file) == receipt.byteCount, try digest(file, expectedBytes: receipt.byteCount) == receipt.sha256 else { throw PodcastAudioReceipt.Failure.invalid }
        return Proof(receipt: receipt, file: file, accessed: Date().timeIntervalSince1970)
    }
    private func validationIsCurrent(_ work: Validation) -> Bool {
        guard enabled() else { return false }
        return locked { validationIsCurrentLocked(work) }
    }
    private func validationIsCurrentLocked(_ work: Validation) -> Bool {
        validating[work.asset.key] === work && work.valid && work.generation == generation &&
            !revoked.contains(work.asset.key) && !admissionClosed && evicting[work.asset.key] == nil
    }
    /// The only migration entry is the existing bounded, off-main validator.
    /// An existing destination receipt (including an invalid one) wins: never
    /// replace it with old cache bytes. No directory scan or v1 adoption occurs.
    private func readProof(_ work: Validation) throws -> Proof {
        let asset = work.asset
        if manager.fileExists(atPath: receiptURL(asset).path) { return try readProof(asset, in: directory) }
        guard let legacyDirectory, validationIsCurrent(work) else { throw PodcastAudioReceipt.Failure.invalid }
        let legacy = try readProof(asset, in: legacyDirectory)
        guard validationIsCurrent(work), !manager.fileExists(atPath: receiptURL(asset).path) else {
            throw PodcastAudioReceipt.Failure.invalid
        }
        return try migrate(legacy, work: work)
    }
    private func migrate(_ legacy: Proof, work: Validation) throws -> Proof {
        let asset = work.asset
        try OfflineDownloadLocations.prepareDirectory(directory)
        let staging = directory.appendingPathComponent(UUID().uuidString + ".migration")
        let receiptStaging = directory.appendingPathComponent(UUID().uuidString + ".migration-receipt")
        defer { try? manager.removeItem(at: staging);try? manager.removeItem(at: receiptStaging) }
        try copyForMigration(legacy.file, to: staging, expectedBytes: legacy.receipt.byteCount)
        // Validate the actual copy too: a legacy file may change after its read.
        guard try regularSize(staging) == legacy.receipt.byteCount,
              try digest(staging, expectedBytes: legacy.receipt.byteCount) == legacy.receipt.sha256 else {
            throw PodcastAudioReceipt.Failure.invalid
        }
        try OfflineDownloadLocations.prepareFile(staging)
        let receipt = try PodcastAudioReceipt(asset: asset, byteCount: legacy.receipt.byteCount, sha256: legacy.receipt.sha256)
        try receipt.encoded().write(to: receiptStaging, options: .atomic)
        try OfflineDownloadLocations.prepareFile(receiptStaging)
        let priorFiles = try makeRoom(asset: asset, incomingBytes: receipt.byteCount,
                                     stillCurrent: { validationIsCurrentLocked(work) })
        guard validationIsCurrent(work), !manager.fileExists(atPath: receiptURL(asset).path) else {
            throw PodcastAudioReceipt.Failure.invalid
        }
        let destination = directory.appendingPathComponent(receipt.fileName)
        // Hard-link publication is atomic and refuses an existing destination;
        // both staging files live on the same volume. Keep all legacy bytes.
        try manager.linkItem(at: staging, to: destination)
        do { try manager.linkItem(at: receiptStaging, to: receiptURL(asset)) }
        catch { try? manager.removeItem(at: destination);throw error }
        for file in priorFiles where file.key == asset.key && file.url != destination { try? manager.removeItem(at: file.url) }
        return Proof(receipt: receipt, file: destination, accessed: Date().timeIntervalSince1970)
    }
    private func copyForMigration(_ source: URL, to destination: URL, expectedBytes: Int64) throws {
        guard expectedBytes > 0, expectedBytes <= PodcastAudioReceipt.maximumAudioBytes else { throw PodcastAudioReceipt.Failure.invalid }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try Data().write(to: destination, options: .withoutOverwriting)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied: Int64 = 0
        while let bytes = try input.read(upToCount: Int(min(256 * 1024, expectedBytes - copied + 1))), !bytes.isEmpty {
            // A source that grows after validation cannot cause an unbounded
            // copy. Read at most one byte beyond the accepted complete length.
            guard Int64(bytes.count) <= expectedBytes - copied else { throw PodcastAudioReceipt.Failure.invalid }
            try output.write(contentsOf: bytes)
            copied += Int64(bytes.count)
        }
        guard copied == expectedBytes else { throw PodcastAudioReceipt.Failure.invalid }
        try output.close()
    }
    private func boundedData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url);defer { try? handle.close() }
        let data = try handle.read(upToCount: PodcastAudioReceipt.maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= PodcastAudioReceipt.maximumBytes else { throw PodcastAudioReceipt.Failure.invalid }
        return data
    }
    private func digest(_ file: URL, expectedBytes: Int64) throws -> String {
        guard expectedBytes > 0, expectedBytes <= PodcastAudioReceipt.maximumAudioBytes else { throw PodcastAudioReceipt.Failure.invalid }
        let handle = try FileHandle(forReadingFrom: file);defer { try? handle.close() }
        var digest = SHA256();var count: Int64 = 0
        while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty {
            count += Int64(data.count);guard count <= expectedBytes else { throw PodcastAudioReceipt.Failure.invalid };digest.update(data: data)
        }
        guard count == expectedBytes else { throw PodcastAudioReceipt.Failure.invalid }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func commit(_ artifact: DownloadArtifact, work: Active) throws -> Proof {
        let asset = work.request.asset
        guard locked({ downloadIsCurrentLocked(work) }),
              let response = artifact.response as? HTTPURLResponse, response.statusCode == 200,
              response.value(forHTTPHeaderField: "Content-Range") == nil,
              response.url?.scheme?.lowercased() == "https" else { throw PodcastAudioReceipt.Failure.invalid }
        if let mime = response.mimeType?.lowercased(), !(mime.hasPrefix("audio/") || mime.hasPrefix("video/") || mime == "application/octet-stream") { throw PodcastAudioReceipt.Failure.invalid }
        let bytes = try regularSize(artifact.temporaryURL)
        guard bytes > 0, bytes <= PodcastAudioReceipt.maximumAudioBytes,
              response.expectedContentLength < 0 || response.expectedContentLength == bytes else { throw PodcastAudioReceipt.Failure.invalid }
        // The injected transport must satisfy the same complete, uncompressed
        // artifact contract as the default streaming transport. An invalid
        // explicit length cannot be treated as an unknown-length response.
        if let length = response.value(forHTTPHeaderField: "Content-Length") {
            guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }),
                  let declaredBytes = Int64(length), declaredBytes == bytes else { throw PodcastAudioReceipt.Failure.invalid }
        }
        if let encoding = response.value(forHTTPHeaderField: "Content-Encoding"), encoding.lowercased() != "identity" {
            throw PodcastAudioReceipt.Failure.invalid
        }
        guard bytes <= max(0, maxBytes()) else { throw CommitFailure.storageLimit }
        let receipt = try PodcastAudioReceipt(asset: asset, byteCount: bytes, sha256: digest(artifact.temporaryURL, expectedBytes: bytes))
        let priorFiles = try makeRoom(asset: asset, incomingBytes: bytes)
        guard locked({ downloadIsCurrentLocked(work) }) else { throw PodcastAudioReceipt.Failure.invalid }
        try OfflineDownloadLocations.prepareDirectory(directory)
        try OfflineDownloadLocations.prepareFile(artifact.temporaryURL)
        let destination = directory.appendingPathComponent(receipt.fileName)
        try manager.moveItem(at: artifact.temporaryURL, to: destination)
        do {
            try receipt.encoded().write(to: receiptURL(asset), options: .atomic)
            try OfflineDownloadLocations.prepareFile(receiptURL(asset))
        }
        catch { try? manager.removeItem(at: destination);throw error }
        for file in priorFiles where file.key == asset.key && file.url != destination { try? manager.removeItem(at: file.url) }
        return Proof(receipt: receipt, file: destination, accessed: Date().timeIntervalSince1970)
    }
    private func removeDisk(_ asset: PodcastAudioAsset) {
        removeDisk(asset, in: directory)
        if let legacyDirectory { removeDisk(asset, in: legacyDirectory) }
    }
    private func removeDisk(_ asset: PodcastAudioAsset, in root: URL) {
        let path = root.appendingPathComponent(asset.key + ".json")
        // Explicit removal covers the old v2 copy too, preventing resurrection
        // on a cold launch. A malformed/foreign receipt owns no deletable file.
        guard let size = try? regularSize(path), size > 0, size <= PodcastAudioReceipt.maximumBytes,
              let data = try? boundedData(path), let receipt = try? PodcastAudioReceipt.decode(data, expectedAsset: asset) else { return }
        let file = root.appendingPathComponent(receipt.fileName)
        if (try? regularSize(file)) != nil { try? manager.removeItem(at: file) }
        try? manager.removeItem(at: path)
    }
    private func diskFiles() throws -> [(key: String, size: Int64, url: URL)] {
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) else { return [] }
        var files: [(key: String, size: Int64, url: URL)] = [];var count = 0
        for case let url as URL in enumerator {
            count += 1
            guard count <= 1024 else { throw PodcastAudioReceipt.Failure.invalid }
            guard PodcastAudioReceipt.extensions.contains(url.pathExtension), let key = url.lastPathComponent.split(separator: "-").first.map(String.init), key.utf8.count == 64,
                  key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), let size = try? regularSize(url), size >= 0 else { continue }
            files.append((key, size, url))
        }
        return files
    }
    /// Refuse an admission that would exceed the byte budget even after all
    /// unpinned files are evicted. Existing protected bytes are never sacrificed.
    private func makeRoom(asset: PodcastAudioAsset, incomingBytes: Int64,
                          stillCurrent: () -> Bool = { true }) throws -> [(key: String, size: Int64, url: URL)] {
        let files = try diskFiles()
        let prior = files.filter { $0.key != asset.key }
        // The budget callback is injectable and may acquire a new pin. Read it
        // before the atomic pin decision/reservation, never while holding lock.
        let limit = max(0, maxBytes())
        let batch = try locked { () throws -> EvictionBatch in
            guard !admissionClosed, stillCurrent() else { throw PodcastAudioReceipt.Failure.invalid }
            let protected = Set(pins.values.map { $0.asset.key }).union(evicting.keys).union([asset.key])
            let candidates = prior.map { ($0.key, $0.size) } + [(asset.key, incomingBytes)]
            let evicted = Set(Self.keysToEvict(files: candidates, accessTimes: proofs.mapValues(\.accessed), pinnedKeys: protected, maxBytes: limit))
            var remaining = incomingBytes
            for file in prior where !evicted.contains(file.key) {
                let sum = remaining.addingReportingOverflow(file.size)
                guard !sum.overflow else { throw CommitFailure.storageLimit };remaining = sum.partialValue
            }
            guard remaining <= limit else { throw CommitFailure.storageLimit }
            guard evicted.count <= Self.maximumEvictions - evicting.count else { throw PodcastAudioReceipt.Failure.invalid }
            return reserveEvictionsLocked(evicted, respectingPins: true)
        }
        announceEvictions(batch)
        defer { retireEvictions(batch) }
        let keys = Set(batch.reservations.map(\.key))
        for file in prior where keys.contains(file.key) {
            try? manager.removeItem(at: file.url);try? manager.removeItem(at: directory.appendingPathComponent(file.key + ".json"))
        }
        return files
    }
    private func enforceDiskLimit() {
        let files: [(key: String, size: Int64, url: URL)]
        do { files = try diskFiles() }
        catch { locked { admissionClosed = true;proofs = [:] };onIndexChange();return }
        let limit = max(0, maxBytes())
        let batch = locked { () -> EvictionBatch in
            let protected = Set(pins.values.map { $0.asset.key }).union(evicting.keys)
            let evicted = Set(Self.keysToEvict(files: files.map { ($0.key, $0.size) }, accessTimes: proofs.mapValues(\.accessed), pinnedKeys: protected, maxBytes: limit))
            return reserveEvictionsLocked(evicted, respectingPins: true)
        }
        announceEvictions(batch)
        defer { retireEvictions(batch) }
        let keys = Set(batch.reservations.map(\.key))
        for file in files where keys.contains(file.key) {
            try? manager.removeItem(at: file.url)
            try? manager.removeItem(at: directory.appendingPathComponent(file.key + ".json"))
        }
    }
    private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock();defer { lock.unlock() };return try body() }

    static func keysToEvict(files: [(key: String, size: Int64)], accessTimes: [String: TimeInterval], pinnedKeys: Set<String>, maxBytes: Int64) -> [String] {
        var total: Int64 = 0
        for entry in files {
            let sum = total.addingReportingOverflow(max(0, entry.size))
            if sum.overflow {
                // An unrepresentable inventory cannot establish a smaller safe
                // eviction set. Refuse to retain unpinned data on that estimate.
                return files.filter { !pinnedKeys.contains($0.key) }.map(\.key)
            }
            total = sum.partialValue
        }
        let limit = max(0, maxBytes)
        guard total > limit else { return [] }
        var remaining = total - limit;var result: [String] = []
        for file in files.filter({ !pinnedKeys.contains($0.key) }).sorted(by: {
            let a = accessTimes[$0.key] ?? 0, b = accessTimes[$1.key] ?? 0;return a == b ? $0.key < $1.key : a < b
        }) where remaining > 0 {
            result.append(file.key);remaining -= min(remaining, max(0, file.size))
        }
        return result
    }
}
