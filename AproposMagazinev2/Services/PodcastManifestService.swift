import Foundation
import OSLog

@MainActor
final class PodcastManifestService {
    static let shared = PodcastManifestService()

    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "PodcastManifestService")
    private let session: URLSession
    private let cacheURL: URL
    private let decoder: JSONDecoder
    private var inFlightRefresh: Task<[PodcastEpisode], Never>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("podcast-manifest.json", isDirectory: false)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func cachedEpisodes() -> [PodcastEpisode] {
        loadCachedManifest()?.episodes.compactMap { $0.toEpisode() } ?? []
    }

    @discardableResult
    func refreshEpisodes(force: Bool = false) async -> [PodcastEpisode] {
        if let inFlightRefresh, !force {
            return await inFlightRefresh.value
        }

        let task = Task { [weak self] in
            guard let self else { return PodcastLinks.bundledFallbackEpisodes }
            return await self.fetchEpisodesFromNetwork()
        }
        inFlightRefresh = task
        let episodes = await task.value
        inFlightRefresh = nil
        return episodes
    }

    private func fetchEpisodesFromNetwork() async -> [PodcastEpisode] {
        guard let manifestURL = PodcastLinks.manifestURL else {
            logger.warning("Podcast manifest URL mangler — bruger bundled fallback.")
            return PodcastLinks.bundledFallbackEpisodes
        }

        var request = URLRequest(url: manifestURL)
        request.setValue("AproposMagazine-iOS/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.warning("Podcast manifest HTTP fejl — bruger cache/fallback.")
                return resolvedFallback()
            }

            let manifest = try decoder.decode(PodcastManifest.self, from: data)
            try data.write(to: cacheURL, options: .atomic)
            let episodes = manifest.episodes.compactMap { $0.toEpisode() }
            if episodes.isEmpty {
                logger.warning("Podcast manifest tom — bruger fallback.")
                return resolvedFallback()
            }
            AppDiagnostics.breadcrumb("podcast_manifest_loaded:\(episodes.count)")
            return episodes
        } catch {
            logger.error("Kunne ikke hente podcast manifest: \(error.localizedDescription, privacy: .public)")
            return resolvedFallback()
        }
    }

    private func resolvedFallback() -> [PodcastEpisode] {
        let cached = cachedEpisodes()
        if !cached.isEmpty { return cached }
        return PodcastLinks.bundledFallbackEpisodes
    }

    private func loadCachedManifest() -> PodcastManifest? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? decoder.decode(PodcastManifest.self, from: data)
    }
}
