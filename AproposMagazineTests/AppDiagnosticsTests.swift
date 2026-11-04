import Foundation
import XCTest
@testable import Apropos

final class AppDiagnosticsTests: XCTestCase {
    @MainActor
    func testDisabledDiagnosticsNeverReadsWritesOrEmitsAndClearsLegacyBuffers() async {
        let f = DiagnosticFixture(), model = f.configure()
        f.entries = ["legacy private email@example.com"]
        model.load()
        XCTAssertTrue(f.entries.isEmpty)
        let reads = f.reads, writes = f.writes
        AppDiagnostics.breadcrumb("app_launch")
        AppDiagnostics.recordError(PrivateDiagnosticError(), context: "fcm_token")
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs(), [])
        await drain()
        XCTAssertEqual(f.reads, reads)
        XCTAssertEqual(f.writes, writes)
        XCTAssertTrue(f.events.isEmpty)
    }

    @MainActor
    func testRawErrorsAndIdentifiersBecomeOnlyControlledCodes() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("podcast_play:https://private.invalid?email=user@example.com")
        AppDiagnostics.recordError(PrivateDiagnosticError(), context: "fcm_token")
        AppDiagnostics.breadcrumb("private unknown raw error user@example.com")
        await drain()
        XCTAssertEqual(Set(f.events.map(\.code)), ["podcast_play", "error.fcm_token"])
        XCTAssertTrue(f.events.allSatisfy { $0.measurements.isEmpty })
        XCTAssertEqual(f.entries.count, 2)
        XCTAssertFalse(f.entries.joined().contains("example.com"))
        XCTAssertFalse(f.entries.joined().contains("private.invalid"))
    }

    @MainActor
    func testQueuedDiagnosticCannotSurviveWithdrawalReenableOrAnAccountChange() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("app_launch")
        model.setChoices(.off)
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("app_background")
        model.changeContext(to: "new-owner")
        AppDiagnostics.breadcrumb("app_foreground")
        await drain()
        XCTAssertEqual(f.events.map(\.code), ["app_foreground"])
        XCTAssertEqual(f.entries.count, 1)
    }

    @MainActor
    func testLocalBufferIsBoundedAndUnknownPersistedContentCannotBeReturned() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        f.entries = ["legacy raw user@example.com", "{\"code\":\"app_launch\",\"measurements\":{},\"recordedAtMs\":true}",
                     "{\"code\":\"metrickit_counts\",\"measurements\":{\"oom\":true},\"recordedAtMs\":1800000000000}"]
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs(), [])
        for _ in 0..<100 { AppDiagnostics.breadcrumb("app_launch") }
        await drain()
        XCTAssertEqual(f.entries.count, 80)
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs().count, 80)
        XCTAssertFalse(f.entries.joined().contains("example.com"))
    }

    @MainActor
    func testStorageReadReentrantWithdrawalStopsStaleWriteEmitAndRecentRead() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        f.onRead = { _ = model.setChoices(.off) }
        AppDiagnostics.breadcrumb("app_launch")
        await drain()
        XCTAssertEqual(f.writes, 0)
        XCTAssertTrue(f.entries.isEmpty)
        XCTAssertTrue(f.events.isEmpty)
        f.onRead = nil
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("app_launch")
        await drain()
        f.onRead = { _ = model.setChoices(.off) }
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs(), [])
    }

    @MainActor
    func testStorageWriteReentrantWithdrawalCannotRestoreTheClearedLocalLogOrEmit() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        f.onWrite = { _ = model.setChoices(.off) }
        AppDiagnostics.breadcrumb("app_launch")
        await drain()
        XCTAssertTrue(f.entries.isEmpty)
        XCTAssertTrue(f.events.isEmpty)
        XCTAssertEqual(model.snapshot().choices, .off)
    }

    @MainActor
    func testReplacementConfigurationRejectsAlreadyQueuedWorkForTheOldStorage() async {
        let first = DiagnosticFixture(), firstModel = first.configure()
        firstModel.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("app_launch")
        let second = DiagnosticFixture(), secondModel = second.configure()
        secondModel.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("app_foreground")
        await drain()
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertTrue(first.entries.isEmpty)
        XCTAssertEqual(second.events.map(\.code), ["app_foreground"])
    }

    @MainActor
    func testMetricIntervalsAndPurposeAreCheckedBeforeLocalPublication() async throws {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        let diagnostic = try XCTUnwrap(model.captureTicket(for: .diagnostics)), analytics = try XCTUnwrap(model.captureTicket(for: .analytics))
        let now = f.clock, since = now.addingTimeInterval(-10)
        AppDiagnostics.recordMetricCounts(["oom": 1], begin: since, end: now, since: since, ticket: diagnostic, model: model)
        for (begin, end) in [(since.addingTimeInterval(-1), now), (since, now.addingTimeInterval(1)), (now, since)] {
            AppDiagnostics.recordMetricCounts(["oom": 9], begin: begin, end: end, since: since, ticket: diagnostic, model: model)
        }
        AppDiagnostics.recordMetricCounts(["oom": 7], begin: since, end: now, since: since, ticket: analytics, model: model)
        await drain()
        XCTAssertEqual(f.events, [.init(code: "metrickit_counts", measurements: ["oom": 1])])
    }

    @MainActor
    func testMetricQueuedBeforeContextChangeCannotAdoptTheNewContextTicket() async throws {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        let old = try XCTUnwrap(model.captureTicket(for: .diagnostics)), now = f.clock
        AppDiagnostics.recordMetricCounts(["crashes": 1], begin: now, end: now, since: now, ticket: old, model: model)
        model.changeContext(to: "other-account")
        await drain()
        XCTAssertTrue(f.events.isEmpty)
    }

    @MainActor
    func testReentrantClockWithdrawalCannotReturnPreviouslyReadLines() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.breadcrumb("app_launch")
        await drain()
        XCTAssertEqual(f.entries.count, 1)
        f.onClock = {
            f.onClock = nil
            _ = model.setChoices(.off)
        }
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs(), [])
        XCTAssertTrue(f.entries.isEmpty)
    }

    @MainActor
    func testReentrantAppendClockWithdrawalStopsBeforeReadingStorage() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        let reads = f.reads
        f.onClock = {
            f.onClock = nil
            _ = model.setChoices(.off)
        }
        AppDiagnostics.breadcrumb("app_launch")
        await drain()
        XCTAssertEqual(f.reads, reads)
        XCTAssertTrue(f.entries.isEmpty)
        XCTAssertTrue(f.events.isEmpty)
    }

    @MainActor
    func testTypedOperationalEventsStaySilentWithoutCurrentLocalConsent() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.load()
        let reads = f.reads, writes = f.writes
        for code in TelemetryDiagnosticPolicy.OperationalCode.allCases { AppDiagnostics.recordOperational(code) }
        await drain()
        XCTAssertEqual(f.reads, reads)
        XCTAssertEqual(f.writes, writes)
        XCTAssertTrue(f.events.isEmpty)
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs(), [])
    }

    @MainActor
    func testTypedOperationalEventsRoundTripAsCodeOnlyLocalRows() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        for code in TelemetryDiagnosticPolicy.OperationalCode.allCases { AppDiagnostics.recordOperational(code) }
        await drain()
        XCTAssertEqual(Set(f.events.map(\.code)), Set(TelemetryDiagnosticPolicy.OperationalCode.allCases.map(\.rawValue)))
        XCTAssertTrue(f.events.allSatisfy { $0.measurements.isEmpty })
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs().count, f.events.count)
        XCTAssertTrue(f.entries.allSatisfy { !$0.contains("article_id") && !$0.contains("user_id") && !$0.contains("http") && !$0.contains("@") })
    }

    @MainActor
    func testPersistedOperationalRowsRejectUnknownCodesExtraValuesAndPrivateFields() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        f.entries = [
            #"{"code":"operation.private_account","measurements":{},"recordedAtMs":1800000000000}"#,
            #"{"code":"operation.content_fetch_failed","measurements":{"article_id":42},"recordedAtMs":1800000000000}"#,
            #"{"code":"operation.content_fetch_failed","measurements":{},"recordedAtMs":1800000000000,"message":"user@example.com"}"#
        ]
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs(), [])
        AppDiagnostics.recordOperational(.contentFetchFailed)
        await drain()
        XCTAssertEqual(f.entries.count, 1)
        XCTAssertEqual(f.events, [.init(code: "operation.content_fetch_failed", measurements: [:])])
        XCTAssertEqual(AppDiagnostics.recentBreadcrumbs().count, 1)
        XCTAssertFalse(f.entries.joined().contains("example.com"))
    }

    @MainActor
    func testOperationalCallbackTicketCannotAdoptReenabledOrAnotherAccountConsent() async {
        let f = DiagnosticFixture(), model = f.configure()
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.recordOperational(.profileLoadFailed)
        model.setChoices(.off)
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        AppDiagnostics.recordOperational(.contentDecodeFailed)
        model.changeContext(to: "other-account")
        AppDiagnostics.recordOperational(.manifestFallbackUsed)
        await drain()
        XCTAssertEqual(f.events, [.init(code: "operation.manifest_fallback_used", measurements: [:])])
        XCTAssertEqual(f.entries.count, 1)
    }

    @MainActor
    private func drain() async {
        for _ in 0..<120 { await Task.yield() }
    }
}

private final class PrivateDiagnosticError: Error, LocalizedError, @unchecked Sendable {
    var errorDescription: String? {
        XCTFail("The diagnostics adapter must not inspect raw errors")
        return "user@example.com private token"
    }
}
final class DiagnosticFixture: @unchecked Sendable {
    var entries: [String] = []
    var events: [TelemetryDiagnosticPolicy.Event] = []
    var reads = 0, writes = 0, clears = 0
    var onRead: (() -> Void)?, onWrite: (() -> Void)?, onClock: (() -> Void)?
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func configure() -> TelemetryConsentModel {
        let model = TelemetryConsentModel(storage: .init(read: { nil }, write: { _ in }), now: { self.clock },
                                          sinks: .init(clearAnalytics: {}, clearDiagnostics: { AppDiagnostics.clearBuffers() }))
        AppDiagnostics.configure(model: model, storage: .init(read: {
            self.reads += 1
            self.onRead?()
            return self.entries
        }, write: { entries in
            self.writes += 1
            self.onWrite?()
            self.entries = entries
        }, clear: {
            self.clears += 1
            self.entries = []
        }), emit: { self.events.append($0) }, now: {
            self.onClock?()
            return self.clock
        })
        model.changeContext(to: nil)
        return model
    }
}
