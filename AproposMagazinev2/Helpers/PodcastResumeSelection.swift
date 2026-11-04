import Foundation

/// The repository passes only currently visible, available candidates. Selection
/// itself has no singleton, disk, auth, player or service work.
@MainActor
enum PodcastResumeSelection {
    static func pair(episodes: [PodcastEpisode], articles: [Article], progress: PodcastProgressSnapshot) -> PodcastArticlePair? {
        guard let id = progress.lastPlayedEpisodeID,
              progress.hasResumableProgress(for: id) else { return nil }
        let matches = episodes.filter { $0.id == id && $0.hasPlayableAudioURL }
        guard matches.count == 1, let episode = matches.first else { return nil }
        if let articleID = progress.lastPlayedArticleID {
            guard let article = articles.first(where: { $0.id == articleID }),
                  PodcastAvailabilityModel.hasConsistentIdentity(episode, articleID: articleID) else { return nil }
            return PodcastArticlePair(article: article, episode: episode)
        }
        guard let article = PodcastEpisode.matchingArticle(for: episode, in: articles),
              PodcastAvailabilityModel.hasConsistentIdentity(episode, articleID: article.id) else { return nil }
        return PodcastArticlePair(article: article, episode: episode)
    }
}
