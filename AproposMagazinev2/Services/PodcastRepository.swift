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

    private let catalog = PodcastCatalogPublication()
    var episodes: [PodcastEpisode] { catalog.snapshot.episodes }
    var changes: AnyPublisher<PodcastCatalogPublication.Snapshot, Never> { catalog.changes }
    private var catalogObservation: AnyCancellable?

    private var sourceEpisodes: [PodcastEpisode] = []
    private var hasRefreshed = false
    private var acceptedGeneration = 0
    private var availabilitySubscription: AnyCancellable?
    private let manifestService: PodcastManifestService

    /// Production services stay in the composition. The repository's actual
    /// catalog publication can also be exercised with inert local ownership.
    @MainActor struct Effects {
        let availability: PodcastAvailabilityModel
        var trackEpisodes: ([PodcastEpisode]) -> Void = { _ in }
        var recordArticles: ([Article]) -> Void = { _ in }
        var permitsArticle: (Article) -> Bool = { _ in true }
        var currentSavedTickets: () -> [FavoritesOfflineCoordinator.AccessTicket] = { [] }
        var saveSavedTickets: ([FavoritesOfflineCoordinator.AccessTicket]) -> Void = { _ in }
        var catalogDidChange: () -> Void = {}
        var livePrefetch = false

        static var live: Self {
            var effects = Self(availability: PodcastAvailabilityService.model)
            effects.trackEpisodes = PodcastAvailabilityService.trackEpisodes
            effects.recordArticles = PodcastAvailabilityService.recordArticles
            effects.permitsArticle = { ArticleAvailabilityService.model.permitsBody($0) }
            effects.currentSavedTickets = { OfflineManager.shared.currentAccessTickets }
            effects.saveSavedTickets = { OfflineManager.shared.savePodcastsForOffline(tickets: $0) }
            effects.catalogDidChange = { OfflineManager.shared.synchronizeCurrentMembership() }
            effects.livePrefetch = true
            return effects
        }
    }
    private let effects: Effects

    private convenience init(
        manifestService: PodcastManifestService,
        initialEpisodes: [PodcastEpisode]
    ) {
        self.init(manifestService: manifestService, initialEpisodes: initialEpisodes, effects: .live)
    }

    init(manifestService: PodcastManifestService, initialEpisodes: [PodcastEpisode], effects: Effects) {
        self.manifestService = manifestService
        self.effects = effects
        // Hydrate before showing bundled fallback; cached empty is authoritative.
        catalogObservation = catalog.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        availabilitySubscription = effects.availability.changes.sink { [weak self] in
            self?.applyAvailability()
        }
        Task { [weak self] in
            guard let self else { return }
            let cached = await self.manifestService.cachedEpisodesOffMain()
            guard !self.hasRefreshed else { return }
            self.sourceEpisodes = cached ?? initialEpisodes
            self.effects.trackEpisodes(self.sourceEpisodes)
            if let cached { self.effects.availability.seedCachedManifest(cached) }
            self.effects.availability.recordEpisodes(self.sourceEpisodes)
            self.applyAvailability()
        }
    }

    private func applyAvailability() {
        let visible = sourceEpisodes.filter { effects.availability.allows($0) }
        catalog.replace(visible)
        // This is a new public catalog publication, not a completion using an
        // old account ticket. Reconcile current saved memberships only after
        // the repository exposes the accepted, filtered catalog.
        effects.catalogDidChange()
    }

    func refreshManifest(force: Bool = false, allowPrefetch: Bool = true) async {
        let originalOfflineTickets = effects.currentSavedTickets()
        let result = await manifestService.refreshCatalog(force: force)
        guard result.generation >= acceptedGeneration else { return }
        acceptedGeneration = result.generation
        hasRefreshed = true
        sourceEpisodes = result.episodes
        let availability = effects.availability
        effects.trackEpisodes(sourceEpisodes)
        if result.isFresh { availability.acceptManifest(sourceEpisodes) }
        else { availability.recordEpisodes(sourceEpisodes) }
        applyAvailability()
        effects.saveSavedTickets(originalOfflineTickets)
        if allowPrefetch { prefetchLatestEpisodesIfNeeded() }
    }

    /// Warms the on-disk cache with the most recent episodes so first playback
    /// starts instantly. Gated by feature flags and network conditions.
    private func prefetchLatestEpisodesIfNeeded() {
        guard effects.livePrefetch else { return }
        let diskEnabled = FeatureFlags.podcastDiskCacheEnabled
        let prefetchEnabled = FeatureFlags.podcastPrefetchEnabled
        let wifiOnly = FeatureFlags.podcastPrefetchWiFiOnly
        let heavy = OfflineManager.shared.allowsHeavyDownloads
        guard diskEnabled, prefetchEnabled, !wifiOnly || heavy else { return }
        let limit = min(64, max(0, FeatureFlags.podcastPrefetchLimit))
        var accepted: [PodcastAudioAsset] = []
        for episode in episodes {
            guard accepted.count < limit else { break }
            if let asset = effects.availability.audioAsset(for: episode, allowsAcceptedRecording: false) { accepted.append(asset) }
        }
        let assets = Self.assetsToPrefetch(from: accepted, diskCacheEnabled: diskEnabled,
            prefetchEnabled: prefetchEnabled, wifiOnly: wifiOnly, allowsHeavyDownloads: heavy, limit: limit)

        for asset in assets {
            PodcastAudioCache.shared.scheduleBackgroundDownload(for: asset)
        }
    }

    /// Pure selection logic for prefetch — decides which accepted assets to warm.
    /// Extracted as a `nonisolated static` function so it can be unit-tested
    /// without the main actor, network, or singletons.
    /// Manifest episodes are newest-first, so the top `limit` playable ones win.
    nonisolated static func assetsToPrefetch(
        from assets: [PodcastAudioAsset],
        diskCacheEnabled: Bool,
        prefetchEnabled: Bool,
        wifiOnly: Bool,
        allowsHeavyDownloads: Bool,
        limit: Int
    ) -> [PodcastAudioAsset] {
        guard diskCacheEnabled, prefetchEnabled else { return [] }
        if wifiOnly, !allowsHeavyDownloads { return [] }
        guard limit > 0 else { return [] }

        var seen = Set<PodcastAudioAsset>()
        return Array(assets.filter { $0.sourceRevision != nil
            && ArticleAudioLanguagePolicy.permitsArticleID($0.canonicalArticleID, language: .danish)
            && seen.insert($0).inserted }.prefix(min(limit, 64)))
    }

    func audioAsset(for article: Article) -> PodcastAudioAsset? {
        Self.acceptedAudioAsset(for: article, in: episodes, availability: effects.availability,
            permits: effects.permitsArticle)
    }

    static func acceptedAudioAsset(for article: Article, in episodes: [PodcastEpisode], availability: PodcastAvailabilityModel,
                                   permits: (Article) -> Bool) -> PodcastAudioAsset? {
        guard permits(article), article.hasValidContentIdentity else { return nil }
        if article.contentLanguage == .danish { availability.recordIdentities([(article.id, article.slug)]) }
        // Offline adoption needs an exact canonical association or a DA slug.
        // Streaming's title fallback and first-wins ties cannot grant this proof.
        let candidates = episodes.compactMap { episode -> (PodcastEpisode, Int)? in
            guard episode.hasPlayableAudioURL, let score = Self.matchScore(episode: episode, article: article), score >= 2 else { return nil }
            return (episode, score)
        }
        guard let score = candidates.map(\.1).max() else { return nil }
        let strongest = candidates.filter { $0.1 == score }.map(\.0)
        let human = strongest.filter { !$0.isAINarration }
        let preferred = human.isEmpty ? strongest : human
        guard preferred.count == 1, let raw = preferred.first,
              let asset = availability.audioAsset(for: raw, articleID: article.id),
              asset.isCompatible(withTextRevision: article.bodyRevision), permits(article) else { return nil }
        return asset
    }

    func audioAsset(for episode: PodcastEpisode, articleID: String? = nil) -> PodcastAudioAsset? {
        effects.availability.audioAsset(for: episode, articleID: articleID)
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
        guard effects.permitsArticle(article) else { return nil }
        effects.recordArticles([article])
        return Self.bestMatch(in: episodes, for: article, requirePlayableAudio: requirePlayableAudio)
            .map { Self.enriched($0, with: article) }
    }

    /// Pure matching logic: picks the single best episode for an article from a
    /// given list. Extracted as `nonisolated static` (same pattern as
    /// `assetsToPrefetch`) so it can be unit-tested without the main actor,
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
        Array(
            articles
                .map { ($0, $0.feedSortDate) }
                .sorted { $0.1 > $1.1 }
                .lazy
                .compactMap { article, _ in
                    guard let episode = self.episode(for: article) else { return nil }
                    return PodcastArticlePair(article: article, episode: episode)
                }
                .prefix(limit)
        )
    }

    func resumablePair(from articles: [Article], progress: PodcastProgressSnapshot) -> PodcastArticlePair? {
        guard let pair = PodcastResumeSelection.pair(episodes: episodes,
            articles: articles.filter(effects.permitsArticle), progress: progress) else { return nil }
        return PodcastArticlePair(article: pair.article, episode: Self.enriched(pair.episode, with: pair.article))
    }

    func latestPodcastPairsIncludingPending(from articles: [Article], limit: Int = 5) -> [PodcastArticlePair] {
        Array(
            articles
                .map { ($0, $0.feedSortDate) }
                .sorted { $0.1 > $1.1 }
                .lazy
                .compactMap { article, _ in
                    guard let episode = self.episodeMetadata(for: article) else { return nil }
                    return PodcastArticlePair(article: article, episode: episode)
                }
                .prefix(limit)
        )
    }

    /// Ranks how strongly an episode matches an article. Higher = better; `nil` = no match.
    /// 3: article id, 2: article slug, 1: exact title, 0: loose title contains.
    /// The loose `contains` tier is only ever used when no id/slug/exact-title match
    /// exists, so it can no longer hijack an article that has its own dedicated episode.
    nonisolated static func matchScore(episode: PodcastEpisode, article: Article) -> Int? {
        guard article.hasValidContentIdentity else { return nil }
        // A legacy Danish slug/title is not evidence of English audio. English
        // playback needs its own explicit, exact reader-article binding.
        if article.contentLanguage == .english {
            return episode.articleId == article.id ? 3 : nil
        }
        if let articleId = episode.articleId?.trimmingCharacters(in: .whitespacesAndNewlines), !articleId.isEmpty {
            return article.id == articleId ? 3 : nil
        }
        if let episodeSlug = normalizedString(episode.articleSlug) {
            return normalizedString(article.slug) == episodeSlug ? 2 : nil
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

    nonisolated static func enriched(_ episode: PodcastEpisode, with article: Article) -> PodcastEpisode {
        let artwork = episode.artworkURL ?? article.mobileImageURL ?? article.thumbURL ?? article.coverURL
        return PodcastEpisode(
            id: episode.id,
            articleId: article.id,
            articleSlug: episode.articleSlug,
            title: episode.title,
            subtitle: episode.subtitle,
            audioURL: episode.audioURL,
            productionSourceURL: episode.productionSourceURL,
            duration: episode.duration,
            artworkURL: artwork,
            hosts: episode.hosts,
            publishedDate: episode.publishedDate,
            isAINarration: episode.isAINarration,
            sourceContentRevision: episode.sourceContentRevision
        )
    }
}
