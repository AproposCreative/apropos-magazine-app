import Foundation
import XCTest
@testable import Apropos

/// Exercises the actual selection boundary and existing local diagnostic buffer.
/// It deliberately never constructs PodcastPlayerManager or an AVPlayer.
final class ArticlePlaybackAdmissionDiagnosticsTests: XCTestCase {
    @MainActor
    func testStaleSelectionDoesNotPlayAndPersistsExactlyOneCodeOnlyRejection() async throws {
        let fixture = DiagnosticFixture(), consent = fixture.configure()
        consent.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        defer { consent.setChoices(.off) }
        let offered = episode(), replacement = episode(revision: "private-replacement-source")
        var plays = 0

        XCTAssertFalse(ArticleListenAction.perform(offered: offered, resolve: { replacement },
            play: { _ in plays += 1 }))
        await drain()

        XCTAssertEqual(plays, 0)
        XCTAssertEqual(fixture.events, [.init(code: "operation.article_listen_selection_rejected", measurements: [:])])
        XCTAssertEqual(fixture.entries.count, 1)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fixture.entries[0].utf8)) as? [String: Any])
        XCTAssertEqual(Set(row.keys), ["code", "measurements", "recordedAtMs"])
        XCTAssertEqual(row["code"] as? String, "operation.article_listen_selection_rejected")
        XCTAssertEqual((row["measurements"] as? [String: Int])?.count, 0)
        for secret in ["private-recording", "private-article", "private-original-source", "private-replacement-source", "secret-token", "example.invalid"] {
            XCTAssertFalse(fixture.entries.joined().contains(secret))
        }
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs().count, 1)
    }

    @MainActor
    func testEverySelectionRejectionStopsForwardingAndLogsOnceWithoutExtraResolution() async {
        let fixture = DiagnosticFixture(), consent = fixture.configure()
        consent.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        defer { consent.setChoices(.off) }
        let offered = episode()

        for mode in 0..<4 {
            var enabled = mode != 0, resolutions = 0, plays = 0
            let result = ArticleListenAction.perform(offered: offered, resolve: {
                resolutions += 1
                if mode == 1 { return nil }
                if mode == 2 { return self.episode(revision: "replacement") }
                if mode == 3 { enabled = false }
                return offered
            }, isEnabled: { enabled }, play: { _ in plays += 1 })
            XCTAssertFalse(result)
            XCTAssertEqual(plays, 0)
            XCTAssertEqual(resolutions, mode == 0 ? 0 : 1,
                "Observation must not repeat a resolver or bypass the original enabled guard")
        }
        await drain()
        XCTAssertEqual(fixture.events.map(\.code), Array(repeating: "operation.article_listen_selection_rejected", count: 4))
        XCTAssertEqual(fixture.entries.count, 4)
    }

    @MainActor
    func testForwardedActionDoesNotInventManagerAdmissionOrPlaybackEvidence() async {
        let fixture = DiagnosticFixture(), consent = fixture.configure()
        consent.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        defer { consent.setChoices(.off) }
        let offered = episode()
        var plays = 0
        XCTAssertTrue(ArticleListenAction.perform(offered: offered, resolve: { offered },
            play: { _ in plays += 1 }))
        await drain()
        XCTAssertEqual(plays, 1)
        XCTAssertTrue(fixture.events.isEmpty,
            "A Void forwarding callback is not an accepted manager request or proof of audio")
        XCTAssertTrue(fixture.entries.isEmpty)
    }

    @MainActor
    func testSelectionAndAdmissionObservationsWithConsentOffNeverAccessDiagnosticStorage() async {
        let fixture = DiagnosticFixture(), consent = fixture.configure()
        consent.load()
        let reads = fixture.reads, writes = fixture.writes
        XCTAssertFalse(ArticleListenAction.perform(offered: episode(), resolve: { nil },
            play: { _ in XCTFail("Missing selection forwarded") }))
        for stage in PodcastPlaybackPolicy.AdmissionStage.allCases {
            AppDiagnostics.recordOperational(stage.diagnosticCode(accepted: false))
        }
        AppDiagnostics.recordOperational(PodcastPlaybackPolicy.AdmissionStage.presentation.diagnosticCode(accepted: true))
        await drain()
        XCTAssertEqual(fixture.reads, reads)
        XCTAssertEqual(fixture.writes, writes)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertTrue(fixture.entries.isEmpty)
    }

    @MainActor
    func testQueuedSelectionAndAdmissionEventsCannotAdoptReenabledConsent() async {
        let fixture = DiagnosticFixture(), consent = fixture.configure()
        consent.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        XCTAssertFalse(ArticleListenAction.perform(offered: episode(), resolve: { nil },
            play: { _ in XCTFail("Missing selection forwarded") }))
        AppDiagnostics.recordOperational(PodcastPlaybackPolicy.AdmissionStage.request.diagnosticCode(accepted: false))
        consent.setChoices(.off)
        consent.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        defer { consent.setChoices(.off) }
        await drain()
        XCTAssertEqual(fixture.writes, 0)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertTrue(fixture.entries.isEmpty)

        AppDiagnostics.recordOperational(PodcastPlaybackPolicy.AdmissionStage.preparation.diagnosticCode(accepted: true))
        await drain()
        XCTAssertEqual(fixture.events, [.init(code: "operation.podcast_admission_accepted", measurements: [:])])
        XCTAssertEqual(fixture.entries.count, 1,
            "Only an observation made under the new consent can enter the existing buffer")
    }

    @MainActor
    func testAdmissionStagesRoundTripAsBoundedCodesWithoutPlayedOrDynamicPayloads() async {
        let fixture = DiagnosticFixture(), consent = fixture.configure()
        consent.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        defer { consent.setChoices(.off) }
        let stages = PodcastPlaybackPolicy.AdmissionStage.allCases
        let rejected = stages.map { $0.diagnosticCode(accepted: false) }
        XCTAssertEqual(Set(rejected).count, stages.count)
        XCTAssertLessThanOrEqual(stages.count, 12)
        for stage in stages {
            XCTAssertEqual(stage.diagnosticCode(accepted: true), .podcastAdmissionAccepted)
            let code = stage.diagnosticCode(accepted: false)
            XCTAssertTrue(code.rawValue.hasPrefix("operation.podcast_admission_"))
            XCTAssertTrue(code.rawValue.hasSuffix("_rejected"))
            XCTAssertFalse(code.rawValue.contains("played"))
            XCTAssertLessThanOrEqual(code.rawValue.utf8.count, 64)
            XCTAssertTrue(TelemetryDiagnosticPolicy.operational(code).measurements.isEmpty)
            AppDiagnostics.recordOperational(code)
        }
        AppDiagnostics.recordOperational(.podcastAdmissionAccepted)
        await drain()
        XCTAssertEqual(fixture.events.map(\.code), rejected.map(\.rawValue) + ["operation.podcast_admission_accepted"])
        XCTAssertTrue(fixture.events.allSatisfy { $0.measurements.isEmpty })
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs().count, stages.count + 1)
        for raw in ["operation.podcast_admission_played", "operation.podcast_admission_entry_rejected:private-article",
                    "operation.podcast_admission_accepted?token=secret-token"] {
            XCTAssertNil(TelemetryDiagnosticPolicy.OperationalCode(rawValue: raw))
            XCTAssertNil(TelemetryDiagnosticPolicy.breadcrumb(raw))
        }
    }

    private func episode(revision: String = "private-original-source") -> PodcastEpisode {
        PodcastEpisode(id: "private-recording", articleId: "private-article", articleSlug: "private-slug",
            title: "Private title", subtitle: nil,
            audioURL: URL(string: "https://example.invalid/recording.m4a?token=secret-token"),
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil,
            sourceContentRevision: revision)
    }

    @MainActor
    private func drain() async {
        for _ in 0..<120 { await Task.yield() }
    }
}
