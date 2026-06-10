import Foundation

enum PodcastPlaybackProgressStore {
    private static let keyPrefix = "podcast_progress_"
    private static let lastEpisodeIdKey = "podcast_last_episode_id"
    private static let lastArticleIdKey = "podcast_last_article_id"
    private static let minimumSavedPosition: TimeInterval = 5
    private static let completionThreshold: TimeInterval = 15

    private static var defaults: UserDefaults {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           let suite = UserDefaults(suiteName: "AproposMagazineTests") {
            return suite
        }
        return .standard
    }

    static func hasResumableProgress(for episodeId: String) -> Bool {
        position(for: episodeId) != nil
    }

    static func playButtonTitle(for episodeId: String) -> String {
        hasResumableProgress(for: episodeId) ? "Fortsæt" : "Lyt"
    }

    static func articlePlayButtonTitle(for episodeId: String) -> String {
        hasResumableProgress(for: episodeId) ? "Fortsæt lytning" : "Lyt til artiklen"
    }

    static func lastPlayedEpisodeId() -> String? {
        defaults.string(forKey: lastEpisodeIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func lastPlayedArticleId() -> String? {
        defaults.string(forKey: lastArticleIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func position(for episodeId: String) -> TimeInterval? {
        let key = storageKey(for: episodeId)
        guard defaults.object(forKey: key) != nil else { return nil }

        let value = defaults.double(forKey: key)
        return value >= minimumSavedPosition ? value : nil
    }

    static func save(episodeId: String, seconds: TimeInterval, duration: TimeInterval) {
        let bounded = max(0, seconds)
        let key = storageKey(for: episodeId)

        if duration > 0, bounded >= max(0, duration - completionThreshold) {
            defaults.removeObject(forKey: key)
            if lastPlayedEpisodeId() == episodeId {
                defaults.removeObject(forKey: lastEpisodeIdKey)
                defaults.removeObject(forKey: lastArticleIdKey)
            }
            return
        }

        guard bounded >= minimumSavedPosition else { return }
        defaults.set(bounded, forKey: key)
        defaults.set(episodeId, forKey: lastEpisodeIdKey)
    }

    static func markLastPlayed(episodeId: String, articleId: String?) {
        defaults.set(episodeId, forKey: lastEpisodeIdKey)
        if let articleId, !articleId.isEmpty {
            defaults.set(articleId, forKey: lastArticleIdKey)
        }
    }

    static func clear(episodeId: String) {
        defaults.removeObject(forKey: storageKey(for: episodeId))
    }

    private static func storageKey(for episodeId: String) -> String {
        keyPrefix + episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
