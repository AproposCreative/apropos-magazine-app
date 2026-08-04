import ActivityKit
import Foundation

@MainActor
final class PodcastLiveActivityService {
    static let shared = PodcastLiveActivityService()

    private var currentActivity: Activity<PodcastActivityAttributes>?
    private var currentArtworkArticleId: String?

    private init() {}

    /// Live Activities are disabled — native Now Playing is the single lock-screen player.
    var isSupported: Bool { false }

    func dismissUnsupportedActivitiesIfNeeded() {
        guard !DeviceCapabilities.hasDynamicIsland else { return }
        endActivity()
    }

    func startActivity(episode: PodcastEpisode, articleId: String? = nil) {
        guard isSupported else {
            endActivity()
            return
        }

        endActivity()

        let artworkContext = resolveArtwork(for: episode, articleId: articleId)
        currentArtworkArticleId = artworkContext.articleId

        Task {
            if let articleId = artworkContext.articleId, let remoteURL = artworkContext.url {
                await WidgetImageStore.cacheImage(forArticleId: articleId, remoteURL: remoteURL)
            }

            let authorName = episode.hosts.first ?? "Apropos Podcast"
            let attributes = PodcastActivityAttributes(showName: "Apropos Podcast")
            let state = PodcastActivityAttributes.ContentState(
                episodeTitle: episode.title,
                authorName: authorName,
                isPlaying: true,
                elapsed: 0,
                duration: 1,
                artworkURL: artworkContext.url,
                artworkArticleId: artworkContext.articleId
            )

            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                currentActivity = nil
            }
        }
    }

    func updateActivity(
        isPlaying: Bool,
        elapsed: TimeInterval,
        duration: TimeInterval,
        episode: PodcastEpisode?,
        articleId: String? = nil
    ) {
        guard isSupported else { return }
        guard let activity = currentActivity ?? Activity<PodcastActivityAttributes>.activities.first else { return }
        currentActivity = activity

        let title = episode?.title ?? activity.content.state.episodeTitle
        let author = episode?.hosts.first ?? activity.content.state.authorName

        var artwork = episode?.artworkURL ?? activity.content.state.artworkURL
        var artworkArticleId = articleId ?? currentArtworkArticleId ?? activity.content.state.artworkArticleId

        if artwork == nil, let episode {
            let artworkContext = resolveArtwork(for: episode, articleId: articleId ?? currentArtworkArticleId)
            artwork = artworkContext.url
            artworkArticleId = artworkContext.articleId
        }

        if let articleId = artworkArticleId,
           let remoteURL = artwork,
           articleId != currentArtworkArticleId || activity.content.state.artworkURL == nil {
            currentArtworkArticleId = articleId
            Task {
                await WidgetImageStore.cacheImage(forArticleId: articleId, remoteURL: remoteURL)
            }
        }

        let safeDuration = max(duration, 1)

        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: title,
            authorName: author,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: safeDuration,
            artworkURL: artwork,
            artworkArticleId: artworkArticleId
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity() {
        currentArtworkArticleId = nil
        guard let activity = currentActivity ?? Activity<PodcastActivityAttributes>.activities.first else { return }
        currentActivity = nil

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func resolveArtwork(for episode: PodcastEpisode, articleId: String?) -> (url: URL?, articleId: String?) {
        if let url = episode.artworkURL {
            let resolvedArticleId = articleId ?? episode.articleId
            return (url, resolvedArticleId)
        }

        let resolvedArticleId = articleId ?? episode.articleId
        if let articles = CacheManager.shared.getCachedArticles() {
            if let article = findArticle(in: articles, episode: episode, articleId: resolvedArticleId) {
                let url = article.mobileImageURL ?? article.thumbURL ?? article.coverURL
                return (url, article.id)
            }
        }

        return (nil, resolvedArticleId)
    }

    private func findArticle(in articles: [Article], episode: PodcastEpisode, articleId: String?) -> Article? {
        if let articleId,
           let match = articles.first(where: { $0.id.caseInsensitiveCompare(articleId) == .orderedSame }) {
            return match
        }

        if let slug = episode.articleSlug?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !slug.isEmpty,
           let match = articles.first(where: {
               $0.slug?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == slug
           }) {
            return match
        }

        let episodeTitle = episode.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !episodeTitle.isEmpty else { return nil }
        return articles.first {
            $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == episodeTitle
        }
    }
}
