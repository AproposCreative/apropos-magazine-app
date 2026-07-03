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
        // Seed with the bundled fallback immediately (no disk I/O on the main thread
        // at launch), then hydrate from the on-disk cache off the main actor.
        self.episodes = initialEpisodes
        Task { [weak self] in
            guard let self else { return }
            let cached = await self.manifestService.cachedEpisodesOffMain()
            // Only apply the cache if a network refresh hasn't already replaced episodes.
            if !cached.isEmpty, self.episodes == initialEpisodes {
                self.episodes = cached
            }
        }
    }

    func refreshManifest(force: Bool = false, allowPrefetch: Bool = true) async {
        let refreshed = await manifestService.refreshEpisodes(force: force)
        episodes = refreshed
        OfflineManager.shared.savePodcastsForOffline(OfflineManager.shared.getOfflineArticles())
        if allowPrefetch {
            prefetchLatestEpisodesIfNeeded()
        }
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
        bestEpisode(for: article, requirePlayableAudio: true)
    }

    func episodeMetadata(for article: Article) -> PodcastEpisode? {
        bestEpisode(for: article, requirePlayableAudio: false)
    }

    /// Finds the single best-matching episode for an article. Matches are ranked so
    /// an exact id/slug match always beats a loose title match. This prevents several
    /// distinct articles (e.g. multiple "…Heartland Festival 2026" pieces) from all
    /// resolving to the same generic episode and showing identical titles.
    private func bestEpisode(for article: Article, requirePlayableAudio: Bool) -> PodcastEpisode? {
        Self.bestMatch(in: episodes, for: article, requirePlayableAudio: requirePlayableAudio)
            .map { enrich($0, with: article) }
    }

    /// Pure matching logic: picks the single best episode for an article from a
    /// given list. Extracted as `nonisolated static` (same pattern as
    /// `episodesToPrefetch`) so it can be unit-tested without the main actor,
    /// network, or singletons. Returns the matched episode *before* enrichment.
    nonisolated static func bestMatch(
        in episodes: [PodcastEpisode],
        for article: Article,
        requirePlayableAudio: Bool
    ) -> PodcastEpisode? {
        let scored = episodes.compactMap { episode -> (episode: PodcastEpisode, score: Int)? in
            if requirePlayableAudio && !episode.hasPlayableAudioURL { return nil }
            guard let score = matchScore(episode: episode, article: article) else { return nil }
            return (episode, score)
        }
        guard let bestScore = scored.map(\.score).max() else { return nil }
        let best = scored.filter { $0.score == bestScore }.map(\.episode)
        // Prefer a human/NotebookLM podcast over an AI narration when both exist at the same rank.
        return best.first(where: { !$0.isAINarration }) ?? best.first
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

    /// Ranks how strongly an episode matches an article. Higher = better; `nil` = no match.
    /// 3: article id, 2: article slug, 1: exact title, 0: loose title contains.
    /// The loose `contains` tier is only ever used when no id/slug/exact-title match
    /// exists, so it can no longer hijack an article that has its own dedicated episode.
    nonisolated static func matchScore(episode: PodcastEpisode, article: Article) -> Int? {
        if let articleId = episode.articleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !articleId.isEmpty,
           article.id.caseInsensitiveCompare(articleId) == .orderedSame {
            return 3
        }

        if let episodeSlug = normalizedString(episode.articleSlug),
           let articleSlug = normalizedString(article.slug),
           episodeSlug == articleSlug {
            return 2
        }

        guard let episodeTitle = normalizedString(episode.title),
              let articleTitle = normalizedString(article.name) else {
            return nil
        }

        if episodeTitle == articleTitle { return 1 }
        if articleTitle.contains(episodeTitle) || episodeTitle.contains(articleTitle) { return 0 }
        return nil
    }

    private func normalized(_ value: String?) -> String? {
        Self.normalizedString(value)
    }

    nonisolated static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
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
