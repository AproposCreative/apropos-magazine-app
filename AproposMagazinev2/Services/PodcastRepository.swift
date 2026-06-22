import Combine
import Foundation

@MainActor
protocol PodcastProviding {
    func episode(for article: Article) -> PodcastEpisode?
    func episodeMetadata(for article: Article) -> PodcastEpisode?
    func latestPodcastPairs(from articles: [Article], limit: Int) -> [PodcastArticlePair]
    func latestPodcastPairsIncludingPending(from articles: [Article], limit: Int) -> [PodcastArticlePair]
}

@MainActor
final class PodcastRepository: PodcastProviding, ObservableObject {
    static let shared = PodcastRepository(
        manifestService: PodcastManifestService.shared,
        initialEpisodes: PodcastLinks.bundledFallbackEpisodes
    )

    @Published private(set) var episodes: [PodcastEpisode]

    private let manifestService: PodcastManifestService

    private init(
        manifestService: PodcastManifestService,
        initialEpisodes: [PodcastEpisode]
    ) {
        self.manifestService = manifestService
        let cached = manifestService.cachedEpisodes()
        self.episodes = cached.isEmpty ? initialEpisodes : cached
    }

    func refreshManifest(force: Bool = false) async {
        let refreshed = await manifestService.refreshEpisodes(force: force)
        episodes = refreshed
        OfflineManager.shared.savePodcastsForOffline(OfflineManager.shared.getOfflineArticles())
        prefetchLatestEpisodesIfNeeded()
    }

    /// Warms the on-disk cache with the most recent episodes so first playback
    /// starts instantly. Gated by feature flags and network conditions.
    private func prefetchLatestEpisodesIfNeeded() {
        let urls = Self.episodesToPrefetch(
            from: episodes,
            diskCacheEnabled: FeatureFlags.podcastDiskCacheEnabled,
            prefetchEnabled: FeatureFlags.podcastPrefetchEnabled,
            wifiOnly: FeatureFlags.podcastPrefetchWiFiOnly,
            allowsHeavyDownloads: OfflineManager.shared.allowsHeavyDownloads,
            limit: FeatureFlags.podcastPrefetchLimit
        )

        for url in urls {
            PodcastAudioCache.shared.scheduleBackgroundDownload(from: url)
        }
    }

    /// Pure selection logic for prefetch — decides which audio URLs to warm.
    /// Extracted as a `nonisolated static` function so it can be unit-tested
    /// without the main actor, network, or singletons.
    /// Manifest episodes are newest-first, so the top `limit` playable ones win.
    nonisolated static func episodesToPrefetch(
        from episodes: [PodcastEpisode],
        diskCacheEnabled: Bool,
        prefetchEnabled: Bool,
        wifiOnly: Bool,
        allowsHeavyDownloads: Bool,
        limit: Int
    ) -> [URL] {
        guard diskCacheEnabled, prefetchEnabled else { return [] }
        if wifiOnly, !allowsHeavyDownloads { return [] }
        guard limit > 0 else { return [] }

        return episodes
            .filter { $0.hasPlayableAudioURL }
            .prefix(limit)
            .compactMap { $0.audioURL }
    }

    func episode(for article: Article) -> PodcastEpisode? {
        let candidates = episodes.filter { episode in
            matches(episode: episode, article: article)
                && episode.hasPlayableAudioURL
        }
        // Prefer a human/NotebookLM podcast over an AI narration when both exist.
        let preferred = candidates.first(where: { !$0.isAINarration }) ?? candidates.first
        return preferred.map { enrich($0, with: article) }
    }

    func episodeMetadata(for article: Article) -> PodcastEpisode? {
        episodes.first(where: { episode in
            matches(episode: episode, article: article)
        })
        .map { enrich($0, with: article) }
    }

    func episode(forSlug slug: String) -> PodcastEpisode? {
        guard let normalizedSlug = normalized(slug) else { return nil }
        return episodes.first { episode in
            normalized(episode.articleSlug) == normalizedSlug
                || normalized(episode.id) == normalizedSlug
        }
    }

    func latestPodcastPairs(from articles: [Article], limit: Int = 5) -> [PodcastArticlePair] {
        articles
            .sorted { $0.feedSortDate > $1.feedSortDate }
            .compactMap { article in
                guard let episode = episode(for: article) else { return nil }
                return PodcastArticlePair(article: article, episode: episode)
            }
            .prefix(limit)
            .map { $0 }
    }

    func resumablePair(from articles: [Article]) -> PodcastArticlePair? {
        guard let episodeId = PodcastPlaybackProgressStore.lastPlayedEpisodeId(),
              PodcastPlaybackProgressStore.hasResumableProgress(for: episodeId),
              let episode = episodes.first(where: { $0.id == episodeId && $0.hasPlayableAudioURL }) else {
            return nil
        }

        if let articleId = PodcastPlaybackProgressStore.lastPlayedArticleId(),
           let article = articles.first(where: { $0.id == articleId }) {
            return PodcastArticlePair(article: article, episode: enrich(episode, with: article))
        }

        if let article = PodcastEpisode.matchingArticle(for: episode, in: articles) {
            return PodcastArticlePair(article: article, episode: enrich(episode, with: article))
        }

        return nil
    }

    func latestPodcastPairsIncludingPending(from articles: [Article], limit: Int = 5) -> [PodcastArticlePair] {
        articles
            .sorted { $0.feedSortDate > $1.feedSortDate }
            .compactMap { article in
                guard let episode = episodeMetadata(for: article) else { return nil }
                return PodcastArticlePair(article: article, episode: episode)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func matches(episode: PodcastEpisode, article: Article) -> Bool {
        if let articleId = episode.articleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !articleId.isEmpty,
           article.id.caseInsensitiveCompare(articleId) == .orderedSame {
            return true
        }

        guard let episodeSlug = normalized(episode.articleSlug),
              let articleSlug = normalized(article.slug) else {
            return titleMatches(episode: episode, article: article)
        }

        if episodeSlug == articleSlug {
            return true
        }

        return titleMatches(episode: episode, article: article)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func titleMatches(episode: PodcastEpisode, article: Article) -> Bool {
        guard let episodeTitle = normalized(episode.title),
              let articleTitle = normalized(article.name) else {
            return false
        }

        return articleTitle == episodeTitle
            || articleTitle.contains(episodeTitle)
            || episodeTitle.contains(articleTitle)
    }

    private func enrich(_ episode: PodcastEpisode, with article: Article) -> PodcastEpisode {
        let artwork = episode.artworkURL ?? article.mobileImageURL ?? article.thumbURL ?? article.coverURL
        return PodcastEpisode(
            id: episode.id,
            articleId: episode.articleId,
            articleSlug: episode.articleSlug,
            title: episode.title,
            subtitle: episode.subtitle,
            audioURL: episode.audioURL,
            productionSourceURL: episode.productionSourceURL,
            duration: episode.duration,
            artworkURL: artwork,
            hosts: episode.hosts,
            publishedDate: episode.publishedDate,
            isAINarration: episode.isAINarration
        )
    }
}
