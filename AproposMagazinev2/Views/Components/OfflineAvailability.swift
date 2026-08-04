import Foundation

/// Shared helpers for whether article body / audio are available offline.
@MainActor
enum OfflineAvailability {
    /// Article body is available without network (offline snapshot with content).
    static func isArticleReadableOffline(_ article: Article) -> Bool {
        OfflineManager.shared.hasReadableOfflineBody(articleId: article.id)
    }

    static func isAudioDownloaded(for article: Article) -> Bool {
        if PodcastAudioCache.shared.isDownloaded(forArticleId: article.id) {
            return true
        }
        return PodcastAudioCache.shared.isDownloaded(
            for: PodcastRepository.shared.episode(for: article)
        )
    }

    static func isAudioDownloaded(for episode: PodcastEpisode?) -> Bool {
        PodcastAudioCache.shared.isDownloaded(for: episode)
    }

    /// Short labels for article tag pills (“Gemt”, “Ikke downloadet”).
    static func articleStatusPillTitles(for article: Article, isOnline: Bool) -> [String] {
        let readable = isArticleReadableOffline(article)
        if readable {
            return ["Gemt"]
        }
        if !isOnline {
            return ["Ikke downloadet"]
        }
        if OfflineManager.shared.isSavedForOffline(articleId: article.id) {
            // Saved but body still downloading / empty.
            return ["Ikke downloadet"]
        }
        return []
    }

    /// Whether the listen button should be offered for this article.
    /// Offline: only when audio is already on device.
    static func canOfferListenButton(for article: Article, isOnline: Bool) -> Bool {
        guard let episode = PodcastRepository.shared.episode(for: article),
              episode.hasPlayableAudioURL else {
            return false
        }
        if isOnline { return true }
        return isAudioDownloaded(for: article)
    }
}
