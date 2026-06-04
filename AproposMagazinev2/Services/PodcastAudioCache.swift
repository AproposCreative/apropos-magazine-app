import CryptoKit
import Foundation

enum PodcastAudioCacheResult: String {
    case hit
    case miss
    case disabled
}

struct PodcastPlaybackURLResolution {
    let url: URL
    let cacheResult: PodcastAudioCacheResult
}

/// Conservative on-disk cache for podcast audio. Never blocks initial playback.
final class PodcastAudioCache {
    static let shared = PodcastAudioCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let accessTimesKey = "podcast_audio_cache_access_v1"
    private var activeDownloadKeys = Set<String>()
    private let downloadQueue = DispatchQueue(label: "com.aproposmagazine.podcast-audio-cache")

    private var maxCacheBytes: Int64 {
        Int64(max(50, FeatureFlags.podcastDiskCacheMaxMB)) * 1024 * 1024
    }

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AproposMagazine", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AproposMagazine", isDirectory: true)
        cacheDirectory = base.appendingPathComponent("podcast-audio", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func resolvePlaybackURL(for remoteURL: URL) -> PodcastPlaybackURLResolution {
        guard FeatureFlags.podcastDiskCacheEnabled else {
            return PodcastPlaybackURLResolution(url: remoteURL, cacheResult: .disabled)
        }

        if let localURL = localFileURL(for: remoteURL) {
            touchAccess(forKey: cacheKey(for: remoteURL))
            return PodcastPlaybackURLResolution(url: localURL, cacheResult: .hit)
        }

        return PodcastPlaybackURLResolution(url: remoteURL, cacheResult: .miss)
    }

    func scheduleBackgroundDownload(from remoteURL: URL) {
        guard FeatureFlags.podcastDiskCacheEnabled else { return }
        guard PodcastAudioURLValidator.isPlayableAudioURL(remoteURL) else { return }
        guard localFileURL(for: remoteURL) == nil else { return }

        let key = cacheKey(for: remoteURL)
        var shouldStart = false
        downloadQueue.sync {
            shouldStart = !activeDownloadKeys.contains(key)
            if shouldStart {
                activeDownloadKeys.insert(key)
            }
        }
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            defer {
                if let self {
                    _ = self.downloadQueue.sync {
                        self.activeDownloadKeys.remove(key)
                    }
                }
            }
            await self?.downloadAndStore(remoteURL: remoteURL, key: key)
        }
    }

    func removeAllCachedFiles() {
        downloadQueue.sync {
            activeDownloadKeys.removeAll()
        }

        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        UserDefaults.standard.removeObject(forKey: accessTimesKey)
    }

    // MARK: - Private

    private func localFileURL(for remoteURL: URL) -> URL? {
        let destination = destinationURL(for: remoteURL)
        guard fileManager.fileExists(atPath: destination.path) else { return nil }
        guard let size = try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int64,
              size > 0 else {
            return nil
        }
        return destination
    }

    private func destinationURL(for remoteURL: URL) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: remoteURL)).appendingPathExtension("m4a")
    }

    private func cacheKey(for remoteURL: URL) -> String {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func downloadAndStore(remoteURL: URL, key: String) async {
        let destination = cacheDirectory.appendingPathComponent(key).appendingPathExtension("m4a")
        let partial = cacheDirectory.appendingPathComponent(key).appendingPathExtension("part")

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? fileManager.removeItem(at: tempURL)
                return
            }

            try? fileManager.removeItem(at: partial)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)

            touchAccess(forKey: key)
            enforceMaxCacheSizeIfNeeded()
            AppDiagnostics.breadcrumb("podcast_cache_saved:\(key.prefix(8))")
            #if DEBUG
            print("[Podcast] cache saved for remote audio")
            #endif
        } catch {
            try? fileManager.removeItem(at: partial)
            AppDiagnostics.breadcrumb("podcast_cache_download_failed")
            #if DEBUG
            print("[Podcast] cache download failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func touchAccess(forKey key: String) {
        var accessTimes = UserDefaults.standard.dictionary(forKey: accessTimesKey) as? [String: TimeInterval] ?? [:]
        accessTimes[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(accessTimes, forKey: accessTimesKey)
    }

    private func enforceMaxCacheSizeIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let audioFiles = files.filter { $0.pathExtension == "m4a" }
        var totalSize: Int64 = 0
        var fileSizes: [(url: URL, size: Int64, key: String)] = []

        for file in audioFiles {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            totalSize += size
            fileSizes.append((file, size, file.deletingPathExtension().lastPathComponent))
        }

        guard totalSize > maxCacheBytes else { return }

        let accessTimes = UserDefaults.standard.dictionary(forKey: accessTimesKey) as? [String: TimeInterval] ?? [:]
        fileSizes.sort { lhs, rhs in
            let left = accessTimes[lhs.key] ?? 0
            let right = accessTimes[rhs.key] ?? 0
            return left < right
        }

        var bytesToFree = totalSize - maxCacheBytes
        var updatedAccess = accessTimes

        for entry in fileSizes where bytesToFree > 0 {
            try? fileManager.removeItem(at: entry.url)
            updatedAccess.removeValue(forKey: entry.key)
            bytesToFree -= entry.size
        }

        UserDefaults.standard.set(updatedAccess, forKey: accessTimesKey)
    }
}
