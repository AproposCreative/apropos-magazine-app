import ActivityKit
import Foundation

@MainActor
final class PodcastLiveActivityService {
    static let shared = PodcastLiveActivityService()

    private var currentActivity: Activity<PodcastActivityAttributes>?

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func startActivity(episode: PodcastEpisode) {
        guard isSupported else { return }
        endActivity()

        let authorName = episode.hosts.first ?? "Apropos Podcast"
        let attributes = PodcastActivityAttributes(showName: "Apropos Podcast")
        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: episode.title,
            authorName: authorName,
            isPlaying: true,
            elapsed: 0,
            duration: 1,
            artworkURL: episode.artworkURL
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

    func updateActivity(isPlaying: Bool, elapsed: TimeInterval, duration: TimeInterval, episode: PodcastEpisode?) {
        guard let activity = currentActivity ?? Activity<PodcastActivityAttributes>.activities.first else { return }
        currentActivity = activity

        let title = episode?.title ?? activity.content.state.episodeTitle
        let author = episode?.hosts.first ?? activity.content.state.authorName
        let artwork = episode?.artworkURL ?? activity.content.state.artworkURL
        let safeDuration = max(duration, 1)

        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: title,
            authorName: author,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: safeDuration,
            artworkURL: artwork
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity() {
        guard let activity = currentActivity ?? Activity<PodcastActivityAttributes>.activities.first else { return }
        currentActivity = nil

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
