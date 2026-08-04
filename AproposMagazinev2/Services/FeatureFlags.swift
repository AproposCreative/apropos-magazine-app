import Foundation

enum FeatureFlags {
    private static let defaults: [String: Any] = [
        "perf_home_image_preload_limit": 12,
        "perf_player_background_publish_threshold": 1.0,
        "perf_player_foreground_publish_threshold": 1.0,
        "perf_enable_html_diff_guard": true,
        "perf_podcast_prefetch_enabled": true,
        "perf_podcast_prefetch_wifi_only": true,
        "perf_podcast_prefetch_limit": 3,
        "perf_podcast_forward_buffer_seconds": 10.0,
        "perf_podcast_disk_cache_enabled": true,
        "perf_podcast_disk_cache_max_mb": 120,
        "perf_podcast_cache_after_play": false,
        "subscriptions_enabled": false
    ]

    private static var store: UserDefaults {
        .standard
    }

    static func registerDefaults() {
        store.register(defaults: defaults)
    }

    static var homeImagePreloadLimit: Int {
        max(4, store.integer(forKey: "perf_home_image_preload_limit"))
    }

    static var playerBackgroundPublishThreshold: TimeInterval {
        let value = store.double(forKey: "perf_player_background_publish_threshold")
        return value > 0 ? value : 1.0
    }

    static var playerForegroundPublishThreshold: TimeInterval {
        let value = store.double(forKey: "perf_player_foreground_publish_threshold")
        return value > 0 ? value : 1.0
    }

    static var htmlDiffGuardEnabled: Bool {
        store.bool(forKey: "perf_enable_html_diff_guard")
    }

    static var podcastPrefetchEnabled: Bool {
        store.bool(forKey: "perf_podcast_prefetch_enabled")
    }

    static var podcastPrefetchWiFiOnly: Bool {
        store.bool(forKey: "perf_podcast_prefetch_wifi_only")
    }

    static var podcastPrefetchLimit: Int {
        max(1, store.integer(forKey: "perf_podcast_prefetch_limit"))
    }

    static var podcastForwardBufferSeconds: TimeInterval {
        let value = store.double(forKey: "perf_podcast_forward_buffer_seconds")
        return value > 0 ? value : 10
    }

    static var podcastDiskCacheEnabled: Bool {
        store.bool(forKey: "perf_podcast_disk_cache_enabled")
    }

    static var podcastDiskCacheMaxMB: Int {
        max(50, store.integer(forKey: "perf_podcast_disk_cache_max_mb"))
    }

    /// When true, episodes stream-played online are also written to disk cache afterwards.
    /// Off by default so offline audio is limited to prefetch + favorites.
    static var podcastCacheAfterPlay: Bool {
        store.bool(forKey: "perf_podcast_cache_after_play")
    }

    /// Enable after creating subscription products in App Store Connect.
    static var subscriptionsEnabled: Bool {
        store.bool(forKey: "subscriptions_enabled")
    }
}
