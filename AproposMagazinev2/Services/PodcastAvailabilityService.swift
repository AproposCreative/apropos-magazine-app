import Combine
import Foundation

/// Only normal app paths construct this facade. Unit tests inject the pure model.
@MainActor
enum PodcastAvailabilityService {
    private static var subscription: AnyCancellable?
    private static var cleanupSubscription: AnyCancellable?
    private static var handledUnavailableAssets = Set<PodcastAudioAsset>()
    static let model: PodcastAvailabilityModel = {
        let defaults = UserDefaults.standard
        let key = "podcastAvailabilityState_v1"
        let snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self, from: $0) } ?? .init()
        let articleModel = ArticleAvailabilityService.model
        let model = PodcastAvailabilityModel(snapshot: snapshot, withdrawnIDs: articleModel.withdrawnIDs,
            approvedRevision: { articleModel.approvedRevision(for: $0) },
            wasInvalidated: { articleModel.wasInvalidated($0) }, save: { snapshot in
            if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
        })
        cleanupSubscription = model.changes.sink {
            let denied = model.unavailableAudioAssets
            let newlyDenied = denied.subtracting(handledUnavailableAssets)
            handledUnavailableAssets = denied
            FavoritesRuntime.shared.offline?.synchronizeCurrentMembership()
            // Exact denied descriptors revoke only their own bytes/downloads
            // and private pin references; an r2 asset on the same URL survives.
            PodcastAudioCache.shared.invalidate(newlyDenied)
        }
        subscription = articleModel.changes.sink { change in
            if model.withdrawnIDs != change.withdrawnIDs { model.setWithdrawn(change.withdrawnIDs) }
            else if !change.invalidatedBodyIDs.isEmpty { model.refreshArticleRevisions() }
        }
        return model
    }()

    static func trackEpisodes(_ episodes: [PodcastEpisode]) {
        ArticleAvailabilityService.model.trackPublicationIDs(Set(episodes.filter(\.isAINarration).compactMap(\.articleId)))
    }

    static func recordEpisodes(_ episodes: [PodcastEpisode]) {
        trackEpisodes(episodes)
        model.recordEpisodes(episodes)
    }

    static func recordPlayback(_ episode: PodcastEpisode, articleID: String?) {
        trackEpisodes([episode])
        model.recordPlayback(episode, articleID: articleID)
    }

    static func recordArticles(_ articles: [Article]) {
        let identities = danishAudioIdentities(from: articles)
        guard !identities.isEmpty else { return }
        model.recordIdentities(identities)
    }

    static func recordMirror(id: String, data: [String: Any]) {
        recordMirrors([(id, data)])
    }

    static func recordMirrors(_ documents: [(id: String, data: [String: Any])]) {
        let identities = danishAudioMirrorIdentities(from: documents)
        guard !identities.isEmpty else { return }
        model.recordIdentities(identities)
    }

    /// Pure boundary shared by cache, feed and observation paths. An English
    /// slug must never join the existing Danish audio alias ledger.
    static func danishAudioIdentities(from articles: [Article]) -> [(id: String, slug: String?)] {
        articles.filter { $0.hasValidContentIdentity && $0.contentLanguage == .danish }.map { ($0.id, $0.slug) }
    }

    static func danishAudioMirrorIdentities(from documents: [(id: String, data: [String: Any])]) -> [(id: String, slug: String?)] {
        documents.compactMap { document in
            guard document.data["id"] as? String == document.id else { return nil }
            guard (try? ArticleMirrorCatalog.validate(.init(language: .danish, documents: [document],
                isFromCache: false, hasPendingWrites: false))) != nil else { return nil }
            return (document.id, (document.data["fieldData"] as? [String: Any])?["slug"] as? String)
        }
    }
}
