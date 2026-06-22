import Foundation

struct PodcastEpisode: Identifiable, Hashable {
    let id: String
    let articleId: String?
    let articleSlug: String?
    let title: String
    let subtitle: String?
    let audioURL: URL?
    let productionSourceURL: URL?
    let duration: String?
    let artworkURL: URL?
    let hosts: [String]
    let publishedDate: Date?
    /// True when the audio is an AI-generated narration (vs. a human/NotebookLM podcast).
    /// Defaulted so existing initializers keep working.
    var isAINarration: Bool = false

    var hasPlayableAudioURL: Bool {
        guard let audioURL else { return false }
        return PodcastAudioURLValidator.isPlayableAudioURL(audioURL)
    }
}

struct PodcastArticlePair: Identifiable, Hashable {
    let article: Article
    let episode: PodcastEpisode

    var id: String {
        article.id
    }
}
