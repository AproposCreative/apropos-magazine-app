import Foundation

/// Converts existing diagnostic call sites to a closed vocabulary. Raw errors,
/// article/episode/category/account identifiers and arbitrary text never leave this policy.
enum TelemetryDiagnosticPolicy {
    /// Operational outcomes are a closed vocabulary: no identifier, URL, raw error
    /// or additional value can be supplied at a call site.
    enum OperationalCode: String, CaseIterable, Sendable {
        case appConfigurationMissing = "operation.app_config_missing"
        case fcmFetchFailed = "operation.fcm_fetch_failed"
        case apnsRegistrationFailed = "operation.apns_register_failed"
        case activityResumeFailed = "operation.activity_resume_failed"
        case backgroundRefreshFailed = "operation.background_refresh_failed"
        case backgroundFetchFailed = "operation.background_fetch_failed"
        case contentFetchFailed = "operation.content_fetch_failed"
        case contentDecodeFailed = "operation.content_decode_failed"
        case contentFallbackUsed = "operation.content_fallback_used"
        case contentIdentityInvalid = "operation.content_identity_invalid"
        case contentUpdateRejected = "operation.content_update_rejected"
        case metadataFetchFailed = "operation.metadata_fetch_failed"
        case metadataDecodeFailed = "operation.metadata_decode_failed"
        case metadataFallbackUsed = "operation.metadata_fallback_used"
        case metadataConfigurationMissing = "operation.metadata_config_missing"
        case metadataURLInvalid = "operation.metadata_url_invalid"
        case metadataRequestRejected = "operation.metadata_request_rejected"
        case favoritesSyncFailed = "operation.favorites_sync_failed"
        case favoritesEncodeFailed = "operation.favorites_encode_failed"
        case favoritesItemInvalid = "operation.favorites_item_invalid"
        case profileIdentityInvalid = "operation.profile_identity_invalid"
        case profileLoadFailed = "operation.profile_load_failed"
        case profileSaveFailed = "operation.profile_save_failed"
        case offlineStoreFailed = "operation.offline_store_failed"
        case offlineProgressSyncFailed = "operation.offline_progress_sync_failed"
        case offlinePreferencesSyncFailed = "operation.offline_preferences_sync_failed"
        case offlineBookmarksSyncFailed = "operation.offline_bookmarks_sync_failed"
        case imageDirectoryFailed = "operation.image_directory_failed"
        case imageDownloadFailed = "operation.image_download_failed"
        case notificationPermissionFailed = "operation.notification_permission_failed"
        case notificationPermissionDenied = "operation.notification_permission_denied"
        case notificationTokenSaveFailed = "operation.notification_token_save_failed"
        case notificationTokenEncodeFailed = "operation.notification_token_encode_failed"
        case notificationTokenSendFailed = "operation.notification_token_send_failed"
        case notificationScheduleFailed = "operation.notification_schedule_failed"
        case notificationFestivalScheduleFailed = "operation.notification_festival_schedule_failed"
        case notificationSubscribeFailed = "operation.notification_subscribe_failed"
        case notificationUnsubscribeFailed = "operation.notification_unsubscribe_failed"
        case notificationSendFailed = "operation.notification_send_failed"
        case notificationTestSendFailed = "operation.notification_test_send_failed"
        case notificationTestScheduled = "operation.notification_test_scheduled"
        case notificationPodcastFallback = "operation.notification_podcast_fallback"
        case navigationEventInvalid = "operation.navigation_event_invalid"
        case navigationLinkInvalid = "operation.navigation_link_invalid"
        case navigationArticleFailed = "operation.navigation_article_failed"
        case navigationAuthorFailed = "operation.navigation_author_failed"
        case manifestFallbackUsed = "operation.manifest_fallback_used"
        case articleListenSelectionRejected = "operation.article_listen_selection_rejected"
        case podcastAdmissionAccepted = "operation.podcast_admission_accepted"
        case podcastAdmissionEntryRejected = "operation.podcast_admission_entry_rejected"
        case podcastAdmissionRequestRejected = "operation.podcast_admission_request_rejected"
        case podcastAdmissionPublicationRejected = "operation.podcast_admission_publication_rejected"
        case podcastAdmissionRecordingRejected = "operation.podcast_admission_recording_rejected"
        case podcastAdmissionReuseRejected = "operation.podcast_admission_reuse_rejected"
        case podcastAdmissionOfflineRejected = "operation.podcast_admission_offline_rejected"
        case podcastAdmissionPreparationRejected = "operation.podcast_admission_preparation_rejected"
        case podcastAdmissionSessionRejected = "operation.podcast_admission_session_rejected"
        case podcastAdmissionItemRejected = "operation.podcast_admission_item_rejected"
        case podcastAdmissionPresentationRejected = "operation.podcast_admission_presentation_rejected"
        case whatsNewMissing = "operation.whatsnew_missing"
        case whatsNewDecodeFailed = "operation.whatsnew_decode_failed"
    }

    struct Event: Equatable, Sendable {
        let code: String
        let measurements: [String: Int]
    }
    private static let fixedCodes: Set<String> = [
        "app_launch", "app_background", "app_foreground", "memory_warning", "metrickit_started",
        "podcast_cache_hit", "podcast_cache_miss", "podcast_cache_disabled", "podcast_cache_saved",
        "podcast_cache_download_failed", "podcast_item_failed", "podcast_route_old_device_unavailable"
    ]
    private static let prefixes: [(String, String)] = [
        ("podcast_play:", "podcast_play"), ("podcast_pause:", "podcast_pause"),
        ("podcast_resume:", "podcast_resume"), ("podcast_stall:", "podcast_stall"),
        ("deeplink_article:", "deeplink_article"), ("deeplink_category:", "deeplink_category"),
        ("deeplink_author:", "deeplink_author"), ("nav_article_from_notification:", "nav_article_from_notification"),
        ("push_subscribed_", "push_subscribed"), ("metrickit_exits ", "metrickit_exits"), ("metrickit_diag ", "metrickit_diag")
    ]
    private static let errorContexts: Set<String> = [
        "fcm_token", "apns_register", "background_fetch", "metrickit_oom", "metrickit_watchdog"
    ]
    private static let metricKeys: Set<String> = [
        "oom", "watchdog", "badaccess", "abnormal", "memory_pressure", "crashes", "hangs", "disk", "cpu"
    ]

    static func operational(_ code: OperationalCode) -> Event {
        Event(code: code.rawValue, measurements: [:])
    }

    static func breadcrumb(_ raw: String) -> Event? {
        if fixedCodes.contains(raw) { return Event(code: raw, measurements: [:]) }
        if raw.hasPrefix("podcast_ttf_audio:") {
            guard raw.utf8.count <= "podcast_ttf_audio:".utf8.count + 10 else {
                return Event(code: "podcast_ttf_audio", measurements: [:])
            }
            let suffix = String(raw.dropFirst("podcast_ttf_audio:".count))
            var measurements: [String: Int] = [:]
            // A malformed number is discarded, never copied to a diagnostic field.
            if suffix.utf8.count <= 10,
               suffix.range(of: #"^[0-9]{1,3}(?:\.[0-9]{1,3})?s$"#, options: .regularExpression) != nil,
               let seconds = Double(suffix.dropLast()), seconds.isFinite, seconds >= 0, seconds <= 300 {
                measurements["milliseconds"] = Int((seconds * 1000).rounded())
            }
            return Event(code: "podcast_ttf_audio", measurements: measurements)
        }
        for (prefix, code) in prefixes where raw.hasPrefix(prefix) {
            return Event(code: code, measurements: [:])
        }
        return nil
    }

    static func error(context: String?) -> Event {
        let value = context.flatMap { errorContexts.contains($0) ? $0 : nil } ?? "unknown"
        return Event(code: "error.\(value)", measurements: [:])
    }

    static func metrics(_ counts: [String: Int]) -> Event? {
        guard !counts.isEmpty, counts.count <= metricKeys.count,
              counts.allSatisfy({ metricKeys.contains($0.key) && (0...1_000_000).contains($0.value) }) else { return nil }
        return Event(code: "metrickit_counts", measurements: counts)
    }

    static func permitsInterval(begin: Date, end: Date, since: Date, now: Date) -> Bool {
        let values = [since, begin, end, now].map(\.timeIntervalSince1970)
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return false }
        return values[0] <= values[1] && values[1] <= values[2] && values[2] <= values[3]
    }
}
