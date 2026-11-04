import Foundation

/// Shared helpers for whether article body / audio are available offline.
@MainActor
enum OfflineAvailability {
    /// Article body is available without network (offline snapshot with content).
    static func isArticleReadableOffline(_ article: Article) -> Bool {
        OfflineManager.shared.hasReadableOfflineBody(articleId: article.id, expectedRevision: article.bodyRevision)
    }

    static func isAudioDownloaded(for article: Article) -> Bool {
        OfflineManager.shared.isAudioDownloaded(articleID: article.id, expectedRevision: article.bodyRevision)
    }

    static func isAudioDownloaded(for episode: PodcastEpisode?) -> Bool {
        OfflineManager.shared.isAudioDownloaded(episode: episode)
    }

    /// Whether the listen button should be offered for this article.
    /// Offline: only when audio is already on device.
    static func canOfferListenButton(for episode: PodcastEpisode, articleID: String, isOnline: Bool) -> Bool {
        guard episode.hasPlayableAudioURL else { return false }
        if isOnline { return true }
        // The offered episode must own the current offline receipt. A download
        // of another render for the same article is not this audio file.
        return OfflineManager.shared.isAudioDownloaded(episode: episode, articleID: articleID)
    }
}
