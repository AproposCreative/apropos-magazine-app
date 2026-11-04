import Foundation
import FirebaseCore
import XCTest
@testable import Apropos

/// The production event service with an injected clock/model/sink. No Firebase
/// app, SDK collection, UserDefaults, analytics or background service is started.
@MainActor
final class AnalyticsServiceTests: XCTestCase {
    func testUnconfiguredServiceRemainsInertWithoutInitializingFirebase() {
        XCTAssertNil(FirebaseApp.allApps)
        var events: [AnalyticsService.Event] = []
        let service = AnalyticsService(model: nil, now: Date.init) { events.append($0) }
        exercise(service)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testMissingLegacyAndMalformedConsentCannotReachTheEventSink() {
        for bytes: Data? in [nil, Data("{".utf8), Data(#"{"analyticsEnabled":true,"crashReportsEnabled":true}"#.utf8)] {
            let f = AnalyticsFixture(data: bytes)
            f.model.load()
            f.model.changeContext(to: nil)
            exercise(f.service)
            XCTAssertTrue(f.events.isEmpty)
        }
    }

    func testRestoredExplicitConsentWaitsForCanonicalAccountContext() throws {
        let f = AnalyticsFixture(data: try storedChoice())
        XCTAssertEqual(f.model.load().state, .ready)
        exercise(f.service)
        XCTAssertTrue(f.events.isEmpty)
        f.model.changeContext(to: nil)
        f.service.trackArticleOpen(article())
        XCTAssertEqual(f.events.map(\.name), ["article_open"])
    }

    func testLocalDiagnosticsChoiceDoesNotAuthorizeAnalyticsEvents() {
        let f = AnalyticsFixture()
        f.model.changeContext(to: nil)
        f.model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        exercise(f.service)
        XCTAssertTrue(f.events.isEmpty)
        XCTAssertNotNil(f.model.captureTicket(for: .diagnostics))
    }

    func testOpeningBeforeConsentCannotBecomeARetroactiveReadOrSource() {
        let f = AnalyticsFixture()
        f.model.load()
        f.model.changeContext(to: nil)
        f.service.setPendingArticleOpenSource(.notification)
        f.service.trackArticleOpen(article())
        f.advance(120)
        f.allowAnalytics()
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertTrue(f.events.isEmpty)
        f.service.trackArticleOpen(article())
        XCTAssertEqual(f.events.last?.identifiers["source"], "feed")
        f.advance(3)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.last?.counts, ["read_time_seconds": 3])
    }

    func testWithdrawalAndReenableClearDwellSourceAndReadDeduplication() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.service.setPendingArticleOpenSource(.notification)
        f.service.trackArticleOpen(article())
        f.advance(4)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 0.8)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.filter { $0.name == "article_read" }.count, 1)
        f.service.setPendingArticleOpenSource(.recommendation)
        f.model.setChoices(.off)
        f.advance(200)
        f.service.trackArticleOpen(article())
        f.allowAnalytics()
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.count, 2)
        f.service.trackArticleOpen(article())
        XCTAssertEqual(f.events.last?.identifiers["source"], "feed")
        f.advance(2)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.filter { $0.name == "article_read" }.count, 2)
        XCTAssertEqual(f.events.last?.counts, ["read_time_seconds": 2])
    }

    func testAccountChangePreservesDeviceChoiceButFencesPreviousReadingContext() {
        let f = AnalyticsFixture()
        f.allowAnalytics(context: "reader_A")
        f.service.trackArticleOpen(article())
        f.service.setPendingArticleOpenSource(.notification)
        f.advance(100)
        f.model.changeContext(to: "reader_B")
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.count, 1)
        f.service.trackArticleOpen(article())
        XCTAssertEqual(f.events.last?.identifiers["source"], "feed")
        f.advance(5)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.last?.counts, ["read_time_seconds": 5])
        XCTAssertFalse(String(describing: f.events).contains("reader_"))
    }

    func testChangingTheOtherPurposeCannotCarryOldReadingEvidenceIntoANewGeneration() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.service.trackArticleOpen(article())
        f.service.setPendingArticleOpenSource(.recommendation)
        f.model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.count, 1)
        f.service.trackArticleOpen(article())
        XCTAssertEqual(f.events.last?.identifiers["source"], "feed")
    }

    func testInvalidIdentifiersCannotBeTruncatedOrPassedThroughToAnyEvent() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        for id in ["", String(repeating: "a", count: 101), "private title", "user@example.com", "https://private.invalid", "article/id", "article\n", "læser"] {
            let invalid = article(id)
            f.service.trackArticleOpen(invalid)
            f.service.trackArticleReadIfNeeded(invalid, scrollProgress: 1)
            f.service.trackRecommendationTap(articleId: id, reason: "Private reason")
            f.service.trackNotificationOpen(articleId: id, type: "article")
            f.service.trackPodcastPlay(episode: episode(id))
        }
        XCTAssertTrue(f.events.isEmpty)
    }

    func testFreeTextAndInvalidOptionalMetadataNeverEnterTheSink() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.service.trackArticleOpen(article("article-1", topic: "user@example.com", author: "https://private.invalid"), source: .search)
        f.service.trackRecommendationTap(articleId: "article-1", reason: "Private reason with user@example.com")
        f.service.trackPodcastPlay(episode: episode("article-1", title: "Private episode title"))
        f.service.trackNotificationOpen(articleId: "article-1", type: "Private arbitrary notification type")
        XCTAssertEqual(f.events, [
            .init(name: "article_open", identifiers: ["article_id": "article-1", "source": "search"], counts: [:]),
            .init(name: "recommendation_tap", identifiers: ["article_id": "article-1"], counts: [:]),
            .init(name: "podcast_play", identifiers: ["article_id": "article-1"], counts: [:]),
            .init(name: "notification_open", identifiers: ["article_id": "article-1", "notification_type": "other"], counts: [:]),
        ])
        XCTAssertFalse(String(describing: f.events).contains("Private"))
        XCTAssertFalse(String(describing: f.events).contains("example.com"))
    }

    func testValidMetadataAndKnownNotificationKindsRemainControlled() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.service.setPendingArticleOpenSource(.recommendation)
        f.service.trackArticleOpen(article("article_1", topic: "topic-1", author: "author_1"))
        XCTAssertEqual(f.events.last?.identifiers, ["article_id": "article_1", "source": "recommendation", "topic_id": "topic-1", "author_id": "author_1"])
        f.service.trackNotificationOpen(articleId: "article_1", type: "new_podcast")
        XCTAssertEqual(f.events.last?.identifiers["notification_type"], "new_podcast")
    }

    func testInvalidProgressAndClockCannotCreateAReadOrConsumeItsDeduplication() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.service.trackArticleOpen(article())
        for progress in [Double.nan, .infinity, -1, 0.79, 1.01] {
            f.service.trackArticleReadIfNeeded(article(), scrollProgress: progress)
        }
        for elapsed in [Double.nan, .infinity, -1, 86_401] {
            f.clock.time = f.initialTime.addingTimeInterval(elapsed)
            f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        }
        XCTAssertEqual(f.events.count, 1)
        f.clock.time = f.initialTime.addingTimeInterval(8)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.last?.counts, ["read_time_seconds": 8])
        XCTAssertEqual(f.events.count, 2)
    }

    func testAnInvalidOpenClockDoesNotCreateLaterReadingEvidence() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.clock.time = Date(timeIntervalSince1970: .nan)
        f.service.trackArticleOpen(article())
        f.clock.time = f.initialTime
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertTrue(f.events.isEmpty)
    }

    func testWithdrawalDuringClockEvaluationCannotEmitTheOldEvent() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.clock.onRead = { f.model.setChoices(.off) }
        f.service.trackArticleOpen(article())
        XCTAssertTrue(f.events.isEmpty)
        XCTAssertEqual(f.model.snapshot().choices, .off)
    }

    func testReplacingTheModelCannotRetainThePreviousSourcesOrDwellTimes() {
        let f = AnalyticsFixture()
        f.allowAnalytics()
        f.service.trackArticleOpen(article())
        f.service.setPendingArticleOpenSource(.notification)
        let second = AnalyticsFixture()
        second.allowAnalytics(context: "reader_B")
        f.service.configure(model: second.model)
        f.service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        XCTAssertEqual(f.events.count, 1)
        f.service.trackArticleOpen(article())
        XCTAssertEqual(f.events.last?.identifiers["source"], "feed")
    }

    private func exercise(_ service: AnalyticsService) {
        service.setPendingArticleOpenSource(.notification)
        service.trackArticleOpen(article())
        service.trackArticleReadIfNeeded(article(), scrollProgress: 1)
        service.trackRecommendationTap(articleId: "article-1", reason: "Private reader interest")
        service.trackPodcastPlay(episode: episode("article-1"))
        service.trackNotificationOpen(articleId: "article-1", type: "new_article")
    }

    private func article(_ id: String = "article-1", topic: String = "", author: String? = nil) -> Article {
        Article(id: id, name: "Private article title", slug: "private-slug", content: "", intro: "", topicID: topic, authorID: author)
    }

    private func episode(_ id: String, title: String = "Private episode title") -> PodcastEpisode {
        PodcastEpisode(id: id, articleId: id, articleSlug: nil, title: title, subtitle: nil, audioURL: nil,
                       productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
    }

    private func storedChoice() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "policyVersion": 1, "analyticsEnabled": true,
                                                    "localDiagnosticsEnabled": false, "recordedAtMs": Int64(1_800_000_000_000)])
    }
}

private final class AnalyticsClock: @unchecked Sendable {
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    var onRead: (() -> Void)?
    func read() -> Date {
        let action = onRead
        onRead = nil
        action?()
        return time
    }
}

private final class AnalyticsConsentStorage: @unchecked Sendable {
    var data: Data?
    init(_ data: Data?) { self.data = data }
}

@MainActor
private final class AnalyticsFixture {
    let initialTime = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = AnalyticsClock()
    let model: TelemetryConsentModel
    private(set) var events: [AnalyticsService.Event] = []
    lazy var service = AnalyticsService(model: model, now: { [clock] in clock.read() }) { [weak self] in self?.events.append($0) }

    init(data: Data? = nil) {
        let storage = AnalyticsConsentStorage(data), clock = clock
        model = TelemetryConsentModel(storage: .init(read: { storage.data }, write: { storage.data = $0 }),
                                      now: { clock.time }, sinks: .init(clearAnalytics: {}, clearDiagnostics: {}))
    }

    func allowAnalytics(context: String? = nil) {
        model.changeContext(to: context)
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: false))
    }

    func advance(_ seconds: TimeInterval) { clock.time = clock.time.addingTimeInterval(seconds) }
}
