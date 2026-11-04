import Foundation
import XCTest
@testable import Apropos

final class TelemetryDiagnosticPolicyTests: XCTestCase {
    func testOperationalVocabularyContainsOnlyBoundedCodesAndNoAdditionalMeasurements() {
        let codes = TelemetryDiagnosticPolicy.OperationalCode.allCases
        XCTAssertFalse(codes.isEmpty)
        XCTAssertEqual(Set(codes.map(\.rawValue)).count, codes.count)
        for code in codes {
            let event = TelemetryDiagnosticPolicy.operational(code)
            XCTAssertEqual(event.code, code.rawValue)
            XCTAssertTrue(event.measurements.isEmpty)
            XCTAssertLessThanOrEqual(event.code.utf8.count, 64)
            XCTAssertNotNil(event.code.range(of: #"^operation\.[a-z_]+$"#, options: .regularExpression))
        }
    }

    func testRawOperationalStringsCannotBypassTheTypedEventEntryPoint() {
        for code in TelemetryDiagnosticPolicy.OperationalCode.allCases {
            XCTAssertNil(TelemetryDiagnosticPolicy.breadcrumb(code.rawValue))
        }
        for raw in ["operation.private_user_id", "operation.content_fetch_failed:user@example.com", "operation.https://private.invalid"] {
            XCTAssertNil(TelemetryDiagnosticPolicy.OperationalCode(rawValue: raw))
            XCTAssertNil(TelemetryDiagnosticPolicy.breadcrumb(raw))
        }
    }

    func testExistingFixedCodesRemainControlledAndContainNoMeasurements() {
        for code in ["app_launch", "app_background", "app_foreground", "memory_warning", "metrickit_started",
                     "podcast_cache_hit", "podcast_cache_miss", "podcast_cache_disabled", "podcast_cache_saved",
                     "podcast_cache_download_failed", "podcast_item_failed", "podcast_route_old_device_unavailable"] {
            XCTAssertEqual(TelemetryDiagnosticPolicy.breadcrumb(code), .init(code: code, measurements: [:]))
        }
    }

    func testEpisodeDeeplinkSubscriptionAndStallDetailsAreRemoved() {
        let privateSuffix = "https://private.invalid/user@example.com?token=secret"
        for (prefix, code) in [("podcast_play:", "podcast_play"), ("podcast_pause:", "podcast_pause"),
                               ("podcast_resume:", "podcast_resume"), ("podcast_stall:", "podcast_stall"),
                               ("deeplink_article:", "deeplink_article"), ("deeplink_category:", "deeplink_category"),
                               ("deeplink_author:", "deeplink_author"), ("nav_article_from_notification:", "nav_article_from_notification"),
                               ("push_subscribed_", "push_subscribed"), ("metrickit_exits ", "metrickit_exits"), ("metrickit_diag ", "metrickit_diag")] {
            let event = TelemetryDiagnosticPolicy.breadcrumb(prefix + privateSuffix)
            XCTAssertEqual(event, .init(code: code, measurements: [:]))
            XCTAssertFalse(String(describing: event).contains("secret"))
            XCTAssertFalse(String(describing: event).contains("example.com"))
        }
    }

    func testUnknownAndNearlyMatchingBreadcrumbsDoNotCreateEvents() {
        for raw in ["", "private@example.com", "https://example.com", "error:raw SDK details", "app_launch:private",
                    "podcast_playback:private", "deeplink_article", "metrickit_counts:oom=1", "podcast_cache_private"] {
            XCTAssertNil(TelemetryDiagnosticPolicy.breadcrumb(raw))
        }
    }

    func testTimeToAudioKeepsOnlyBoundedIntegerMilliseconds() {
        for (raw, milliseconds) in [("0s", 0), ("1.25s", 1250), ("0.001s", 1), ("300s", 300000)] {
            XCTAssertEqual(TelemetryDiagnosticPolicy.breadcrumb("podcast_ttf_audio:" + raw),
                           .init(code: "podcast_ttf_audio", measurements: ["milliseconds": milliseconds]))
        }
    }

    func testInvalidTimeToAudioDiscardsTheValueWhileRetainingTheKnownEventCode() {
        for suffix in ["NaNs", "infs", "-1s", "301s", "1e2s", "1.1234s", " 1s", "1s\nprivate@example.com", "0.1", "https://secret.invalid"] {
            XCTAssertEqual(TelemetryDiagnosticPolicy.breadcrumb("podcast_ttf_audio:" + suffix),
                           .init(code: "podcast_ttf_audio", measurements: [:]))
        }
    }

    func testKnownErrorContextsHaveNoErrorMessagePayload() {
        for context in ["fcm_token", "apns_register", "background_fetch", "metrickit_oom", "metrickit_watchdog"] {
            XCTAssertEqual(TelemetryDiagnosticPolicy.error(context: context), .init(code: "error." + context, measurements: [:]))
        }
    }

    func testUnknownErrorContextNeverEchoesPrivateDetails() {
        for context: String? in [nil, "", "user@example.com", "fcm_token:secret", "https://private.invalid"] {
            XCTAssertEqual(TelemetryDiagnosticPolicy.error(context: context), .init(code: "error.unknown", measurements: [:]))
        }
    }

    func testMetricCountsAreLimitedToTheClosedVocabularyAndIntegerRange() {
        let counts = ["oom": 0, "watchdog": 1, "badaccess": 2, "abnormal": 3, "memory_pressure": 4,
                      "crashes": 5, "hangs": 6, "disk": 7, "cpu": 1_000_000]
        XCTAssertEqual(TelemetryDiagnosticPolicy.metrics(counts), .init(code: "metrickit_counts", measurements: counts))
    }

    func testInvalidMetricMapIsRejectedAsAWholeRatherThanPartiallyPublished() {
        for counts in [[:], ["oom": -1], ["oom": 1_000_001], ["private_account": 1], ["oom": 1, "token": 2]] {
            XCTAssertNil(TelemetryDiagnosticPolicy.metrics(counts))
        }
    }

    func testCompleteIntervalMustLieWithinTheCurrentConsentWindow() {
        let since = Date(timeIntervalSince1970: 100), begin = Date(timeIntervalSince1970: 110)
        let end = Date(timeIntervalSince1970: 120), now = Date(timeIntervalSince1970: 130)
        XCTAssertTrue(TelemetryDiagnosticPolicy.permitsInterval(begin: begin, end: end, since: since, now: now))
        XCTAssertTrue(TelemetryDiagnosticPolicy.permitsInterval(begin: since, end: now, since: since, now: now))
        XCTAssertTrue(TelemetryDiagnosticPolicy.permitsInterval(begin: since, end: since, since: since, now: now))
    }

    func testOldFutureReversedAndInvalidIntervalsAreNotPartiallyAccepted() {
        let date: (TimeInterval) -> Date = { Date(timeIntervalSince1970: $0) }
        for (begin, end, since, now) in [(90.0, 120.0, 100.0, 130.0), (110.0, 140.0, 100.0, 130.0),
                                        (120.0, 110.0, 100.0, 130.0), (110.0, 120.0, 140.0, 130.0),
                                        (0.0, 120.0, 100.0, 130.0), (-1.0, 120.0, 100.0, 130.0),
                                        (Double.nan, 120.0, 100.0, 130.0), (110.0, Double.infinity, 100.0, 130.0),
                                        (110.0, 120.0, Double.nan, 130.0), (110.0, 120.0, 100.0, Double.infinity)] {
            XCTAssertFalse(TelemetryDiagnosticPolicy.permitsInterval(begin: date(begin), end: date(end), since: date(since), now: date(now)))
        }
    }
}
