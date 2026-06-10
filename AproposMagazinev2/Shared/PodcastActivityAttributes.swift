import ActivityKit
import Foundation

struct PodcastActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let episodeTitle: String
        let authorName: String
        let isPlaying: Bool
        let elapsed: TimeInterval
        let duration: TimeInterval
        let artworkURL: URL?
        let artworkArticleId: String?
    }

    let showName: String
}
