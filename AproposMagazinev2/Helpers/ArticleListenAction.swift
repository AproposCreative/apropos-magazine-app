import Foundation

/// Revalidates the exact offered recording at the action boundary. Catalog,
/// publication or offline access can change between drawing and tapping.
@MainActor
enum ArticleListenAction {
    @discardableResult
    static func perform(offered: PodcastEpisode, resolve: () -> PodcastEpisode?,
                        isEnabled: () -> Bool = { true },
                        play: (PodcastEpisode) -> Void) -> Bool {
        guard isEnabled(), let current = resolve(), sameRecording(offered, current), isEnabled() else {
            AppDiagnostics.recordOperational(.articleListenSelectionRejected)
            return false
        }
        play(current)
        return true
    }
    /// Display metadata can refresh while a tap or local-file verification is
    /// pending. Every recording, ownership and source field remains exact.
    static func sameRecording(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode) -> Bool {
        lhs.id == rhs.id && lhs.articleId == rhs.articleId && lhs.articleSlug == rhs.articleSlug
            && lhs.audioURL == rhs.audioURL && lhs.productionSourceURL == rhs.productionSourceURL
            && lhs.isAINarration == rhs.isAINarration && lhs.sourceContentRevision == rhs.sourceContentRevision
    }

}
