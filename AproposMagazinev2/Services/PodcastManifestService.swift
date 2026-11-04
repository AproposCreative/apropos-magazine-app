import Foundation

/// Service ingestion tolerates one bad row without changing the public strict
/// manifest decoder. A recoverable identity remains evidence of a conflict even
/// when the rest of that row cannot be decoded.
private struct IsolatedManifestRow: Decodable {
    let identity: String?
    let episode: PodcastEpisode?

    private enum CodingKeys: String, CodingKey { case id, articleSlug, slug }

    init(from decoder: Decoder) throws {
        let entry = try? PodcastManifestEntry(from: decoder)
        let decoded = entry?.toEpisode()
        episode = decoded.flatMap { $0.hasPlayableAudioURL ? $0 : nil }
        if let entry {
            identity = entry.id
        } else if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            identity = [CodingKeys.id, .articleSlug, .slug].compactMap { key -> String? in
                guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }.first
        } else {
            identity = nil
        }
    }
}

private struct IsolatedManifest: Decodable {
    static let maximumBytes = 8 * 1_024 * 1_024
    static let maximumRows = 4_096
    let rows: [IsolatedManifestRow]

    private enum CodingKeys: String, CodingKey { case version, updatedAt, episodes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 || version == 2 else { throw ManifestError.invalidResponse }
        _ = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        var entries = try container.nestedUnkeyedContainer(forKey: .episodes)
        if let count = entries.count, count > Self.maximumRows { throw ManifestError.invalidResponse }
        var decoded: [IsolatedManifestRow] = []
        while !entries.isAtEnd {
            guard decoded.count < Self.maximumRows else { throw ManifestError.invalidResponse }
            decoded.append(try entries.decode(IsolatedManifestRow.self))
        }
        rows = decoded
    }
}

/// Serializes disk and JSON work away from the UI actor.
private actor PodcastManifestCache {
    let url: URL

    init(url: URL) { self.url = url }

    func loadEpisodes() -> [PodcastEpisode]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    func decodeAndCache(_ data: Data) throws -> [PodcastEpisode] {
        let episodes = try decode(data)
        // A disk failure must not discard an otherwise valid fresh response.
        try? data.write(to: url, options: .atomic)
        return episodes
    }

    private func decode(_ data: Data) throws -> [PodcastEpisode] {
        guard data.count <= IsolatedManifest.maximumBytes else { throw ManifestError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode(IsolatedManifest.self, from: data).rows
        var order: [String] = []
        var accepted: [String: PodcastEpisode] = [:]
        var rejected = Set<String>()
        for row in rows {
            guard let id = row.identity, !rejected.contains(id) else { continue }
            guard let episode = row.episode else {
                rejected.insert(id)
                accepted.removeValue(forKey: id)
                continue
            }
            if let existing = accepted[id] {
                // Equality includes every playback/source and display field.
                // Never choose first/last when the same ID describes two things.
                if existing != episode {
                    rejected.insert(id)
                    accepted.removeValue(forKey: id)
                }
            } else {
                order.append(id)
                accepted[id] = episode
            }
        }
        let episodes = order.compactMap { accepted[$0] }
        // Explicit empty is authoritative; an entirely unusable response is not.
        guard rows.isEmpty || !episodes.isEmpty else { throw ManifestError.invalidResponse }
        return episodes
    }
}

private enum ManifestError: Error {
    case invalidResponse
}

@MainActor
final class PodcastManifestService {
    static let shared = PodcastManifestService()

    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    private let manifestURL: URL?
    private let cache: PodcastManifestCache
    private let fallbackEpisodes: [PodcastEpisode]
    private let fetch: Fetch
    private let now: () -> Date
    private let minimumRefreshInterval: TimeInterval
    private var inFlightRefresh: (id: UUID, task: Task<RefreshResult, Never>)?
    private var requestGeneration = 0
    private var acceptedGeneration = 0
    private var lastSuccessfulRefresh: Date?
    private var latestEpisodes: [PodcastEpisode]?

    struct RefreshResult {
        let episodes: [PodcastEpisode]
        let isFresh: Bool
        var generation: Int = 0
    }

    private convenience init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.init(
            manifestURL: PodcastLinks.manifestURL,
            cacheURL: caches.appendingPathComponent("podcast-manifest.json"),
            fallbackEpisodes: PodcastLinks.bundledFallbackEpisodes,
            fetch: { request in try await session.data(for: request) }
        )
    }

    /// Tests inject a local transport and cache path; they never create the
    /// shared production service or initialize Firebase/network flows.
    init(
        manifestURL: URL?,
        cacheURL: URL,
        fallbackEpisodes: [PodcastEpisode],
        minimumRefreshInterval: TimeInterval = 30,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping Fetch
    ) {
        self.manifestURL = manifestURL
        self.cache = PodcastManifestCache(url: cacheURL)
        self.fallbackEpisodes = fallbackEpisodes
        self.minimumRefreshInterval = minimumRefreshInterval
        self.now = now
        self.fetch = fetch
    }

    func cachedEpisodesOffMain() async -> [PodcastEpisode]? {
        await cache.loadEpisodes()
    }

    @discardableResult
    func refreshEpisodes(force: Bool = false) async -> [PodcastEpisode] {
        await refreshCatalog(force: force).episodes
    }

    func refreshCatalog(force: Bool = false) async -> RefreshResult {
        // Force bypasses freshness, never an identical request already running.
        if let refresh = inFlightRefresh {
            return await refresh.task.value
        }
        if !force, let lastSuccessfulRefresh, let latestEpisodes,
           now().timeIntervalSince(lastSuccessfulRefresh) >= 0,
           now().timeIntervalSince(lastSuccessfulRefresh) < minimumRefreshInterval {
            return RefreshResult(episodes: latestEpisodes, isFresh: true, generation: acceptedGeneration)
        }

        let id = UUID()
        requestGeneration += 1
        let generation = requestGeneration
        let task = Task {
            var result = await self.fetchEpisodesFromNetwork()
            result.generation = generation
            return result
        }
        inFlightRefresh = (id, task)
        let result = await task.value
        if inFlightRefresh?.id == id {
            inFlightRefresh = nil
            latestEpisodes = result.episodes
            acceptedGeneration = result.generation
            if result.isFresh { lastSuccessfulRefresh = now() }
        }
        return result
    }

    private func fetchEpisodesFromNetwork() async -> RefreshResult {
        if let manifestURL {
            var request = URLRequest(url: manifestURL)
            request.setValue("AproposMagazine-iOS/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await fetch(request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else { throw ManifestError.invalidResponse }
                let episodes = try await cache.decodeAndCache(data)
                return RefreshResult(episodes: episodes, isFresh: true)
            } catch {
                AppDiagnostics.recordOperational(.manifestFallbackUsed)
            }
        }
        let cached = await cache.loadEpisodes()
        return RefreshResult(episodes: latestEpisodes ?? cached ?? fallbackEpisodes, isFresh: false)
    }
}
