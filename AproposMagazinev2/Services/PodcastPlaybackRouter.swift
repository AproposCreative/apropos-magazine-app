import Foundation

enum PodcastPlaybackDestination: Identifiable, Hashable {
    case audio(episode: PodcastEpisode, url: URL)

    var id: String {
        switch self {
        case .audio(let episode, let url):
            return "audio-\(episode.id)-\(url.absoluteString)"
        }
    }
}

protocol PodcastPlaybackRouting {
    func destination(for episode: PodcastEpisode) -> PodcastPlaybackDestination?
}

final class PodcastPlaybackRouter: PodcastPlaybackRouting {
    static let shared = PodcastPlaybackRouter()

    private init() {}

    func destination(for episode: PodcastEpisode) -> PodcastPlaybackDestination? {
        guard let audioURL = episode.audioURL,
              PodcastAudioURLValidator.isPlayableAudioURL(audioURL) else {
            return nil
        }

        return .audio(episode: episode, url: audioURL)
    }
}
