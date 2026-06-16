import Foundation

enum PodcastLinks {
    /// Remote catalog — updated by `scripts/podcast-auto-publish.mjs`.
    /// Override via `PODCAST_MANIFEST_URL` in Secrets.plist when manifest uses a download token.
    static var manifestURL: URL? {
        if let override = SecureConfig.shared.podcastManifestURL {
            return override
        }
        return FirebaseStorageURL.mediaURL(storagePath: "podcasts/manifest.json")
    }

    /// Offline fallback is disk cache only — episode URLs come from the remote manifest.
    static let bundledFallbackEpisodes: [PodcastEpisode] = []
}
