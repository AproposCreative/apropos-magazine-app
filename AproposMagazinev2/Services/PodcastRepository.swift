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
    }

    func episode(for article: Article) -> PodcastEpisode? {
        episodes.first(where: { episode in
            matches(episode: episode, article: article)
                && episode.hasPlayableAudioURL
        })
        .map { enrich($0, with: article) }
    }

    func episodeMetadata(for article: Article) -> PodcastEpisode? {
        episodes.first(where: { episode in
            matches(episode: episode, article: article)
        })
        .map { enrich($0, with: article) }
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
            publishedDate: episode.publishedDate
        )
    }
}
