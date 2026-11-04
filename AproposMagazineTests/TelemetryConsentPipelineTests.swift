import Foundation
import XCTest
import FirebaseCore
@testable import Apropos

/// Actual consent persistence -> generation ticket -> event gate, with inert sinks.
/// No Firebase app, telemetry SDK, background service or network is initialized.
final class TelemetryConsentPipelineTests: XCTestCase {
    private typealias Choices = TelemetryConsentModel.Choices
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let off = Choices(analyticsEnabled: false, diagnosticsEnabled: false)
    private let both = Choices(analyticsEnabled: true, diagnosticsEnabled: true)

    private func record(analytics: Bool = true, localDiagnostics: Bool = true,
                        schema: Int = 1, policy: Int = 1, at: Date? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": schema, "policyVersion": policy,
            "analyticsEnabled": analytics, "localDiagnosticsEnabled": localDiagnostics,
            "recordedAtMs": Int64(((at ?? now).timeIntervalSince1970 * 1000).rounded(.down))
        ])
    }

    private func fixture(_ payload: Data? = nil) -> ConsentPipelineFixture {
        ConsentPipelineFixture(payload: payload, now: now)
    }

    private func assertBlocked(_ fixture: ConsentPipelineFixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(fixture.model.captureTicket(for: .analytics), file: file, line: line)
        XCTAssertNil(fixture.model.captureTicket(for: .diagnostics), file: file, line: line)
        XCTAssertEqual(fixture.model.snapshot().choices, off, file: file, line: line)
    }

    func testMissingLegacyCorruptUnsupportedAndFutureRecordsNeverReachEitherSink() throws {
        let candidates: [Data?] = [nil, Data("{".utf8), Data("true".utf8),
            Data(#"{"analyticsEnabled":true,"crashReportsEnabled":true}"#.utf8),
            Data(#"{"schemaVersion":1,"policyVersion":1,"analyticsEnabled":true,"diagnosticsEnabled":true,"recordedAtMs":1700000000000}"#.utf8),
            try record(schema: 2), try record(policy: 2), try record(at: now.addingTimeInterval(1))]
        for payload in candidates {
            let f = fixture(payload)
            f.model.changeContext(to: nil)
            f.model.load()
            assertBlocked(f)
            XCTAssertFalse(f.emitCurrent(.analytics, label: "private-article"))
            XCTAssertFalse(f.emitCurrent(.diagnostics, label: "private-error"))
            XCTAssertTrue(f.sinks.events.isEmpty)
            XCTAssertTrue(f.storage.committedWrites.isEmpty, "Loading unproven data must not silently create opt-in")
        }
    }

    func testExplicitCurrentRecordEnablesOnlyItsChosenPurposeAfterContextResolution() throws {
        let f = fixture(try record(analytics: true, localDiagnostics: false))
        f.model.load()
        XCTAssertNil(f.model.captureTicket(for: .analytics), "Restored consent cannot attach events to an unresolved account context")
        f.model.changeContext(to: nil)
        XCTAssertTrue(f.emitCurrent(.analytics, label: "guest-article"))
        XCTAssertFalse(f.emitCurrent(.diagnostics, label: "local-error"))
        XCTAssertEqual(f.sinks.events, ["analytics:guest-article"])
        XCTAssertTrue(f.model.snapshot().hasExplicitChoice)
        XCTAssertTrue(f.storage.committedWrites.isEmpty)
    }

    func testSavedChoicesRoundTripThroughActualCodecWithoutPersistingAccountOrCloudCrashConsent() throws {
        let f = fixture()
        f.model.changeContext(to: "reader_A")
        f.model.load()
        let saved = f.model.setChoices(both)
        XCTAssertEqual(saved.choices, both)
        XCTAssertTrue(saved.hasExplicitChoice)
        XCTAssertTrue(f.emitCurrent(.analytics, label: "article"))
        XCTAssertTrue(f.emitCurrent(.diagnostics, label: "local-log"))
        let bytes = try XCTUnwrap(f.storage.payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["schemaVersion", "policyVersion", "analyticsEnabled", "localDiagnosticsEnabled", "recordedAtMs"]))
        XCTAssertEqual(json["localDiagnosticsEnabled"] as? Bool, true)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("reader_A"));XCTAssertFalse(text.contains("crashReportsEnabled"))
        let restarted = fixture(bytes)
        restarted.model.changeContext(to: "reader_B")
        restarted.model.load()
        XCTAssertEqual(restarted.model.snapshot().choices, both)
        XCTAssertTrue(restarted.emitCurrent(.analytics, label: "new-context"))
        XCTAssertTrue(restarted.emitCurrent(.diagnostics, label: "new-local-log"))
    }

    func testReadFailureRemainsDeniedUntilAnExplicitSuccessfulSaveInsteadOfSilentlyRetryingOldConsent() throws {
        let f = fixture(try record())
        f.storage.failReads = true
        f.model.changeContext(to: nil)
        XCTAssertEqual(f.model.load().state, .readFailed)
        assertBlocked(f)
        f.storage.failReads = false
        f.model.load()
        assertBlocked(f)
        XCTAssertEqual(f.storage.readCount, 1)
        let recovered = f.model.setChoices(Choices(analyticsEnabled: true, diagnosticsEnabled: false))
        XCTAssertEqual(recovered.state, .ready)
        XCTAssertTrue(f.emitCurrent(.analytics, label: "explicit-retry"))
        XCTAssertFalse(f.emitCurrent(.diagnostics, label: "still-disabled"))
    }

    func testFailedOptInWriteCannotEnableEitherPurposeOrClaimAnExplicitSavedChoice() {
        let f = fixture()
        f.model.changeContext(to: nil)
        f.model.load()
        f.storage.failWrites = true
        XCTAssertEqual(f.model.setChoices(both).state, .writeFailed)
        assertBlocked(f)
        XCTAssertFalse(f.model.snapshot().hasExplicitChoice)
        XCTAssertTrue(f.storage.committedWrites.isEmpty)
        XCTAssertFalse(f.emitCurrent(.analytics, label: "not-saved"))
        XCTAssertFalse(f.emitCurrent(.diagnostics, label: "not-saved"))
        f.storage.failWrites = false
        XCTAssertEqual(f.model.setChoices(both).state, .ready)
        XCTAssertTrue(f.emitCurrent(.analytics, label: "saved"))
        XCTAssertTrue(f.emitCurrent(.diagnostics, label: "saved"))
    }

    func testWithdrawalWithWriteFailureRevokesOldTicketsAndCannotBeUndoneByAnotherLoad() throws {
        let f = fixture(try record())
        f.model.changeContext(to: "reader_A")
        f.model.load()
        let oldAnalytics = try XCTUnwrap(f.model.captureTicket(for: .analytics))
        let oldDiagnostics = try XCTUnwrap(f.model.captureTicket(for: .diagnostics))
        let previousClears = f.sinks.clearCount
        f.storage.failWrites = true
        XCTAssertEqual(f.model.setChoices(off).state, .writeFailed)
        assertBlocked(f)
        XCTAssertGreaterThan(f.sinks.clearCount, previousClears)
        XCTAssertFalse(f.emit(oldAnalytics, label: "late-old-article"))
        XCTAssertFalse(f.emit(oldDiagnostics, label: "late-old-local-error"))
        f.storage.failWrites = false
        f.model.load()
        assertBlocked(f)
        XCTAssertTrue(f.sinks.events.isEmpty)
        XCTAssertEqual(f.model.setChoices(off).state, .ready)
        XCTAssertEqual(f.model.snapshot().choices, off)
    }

    func testWithdrawThenReenableRejectsEveryOldGenerationEvenWhenChoicesAreIdenticalAgain() throws {
        let f = fixture()
        f.model.changeContext(to: "reader_A")
        f.model.load()
        f.model.setChoices(both)
        let a = try XCTUnwrap(f.model.captureTicket(for: .analytics)), d = try XCTUnwrap(f.model.captureTicket(for: .diagnostics))
        f.model.setChoices(off)
        f.model.setChoices(both)
        XCTAssertFalse(f.emit(a, label: "late-before-withdrawal"))
        XCTAssertFalse(f.emit(d, label: "late-before-withdrawal"))
        XCTAssertTrue(f.emitCurrent(.analytics, label: "new-opt-in"))
        XCTAssertTrue(f.emitCurrent(.diagnostics, label: "new-local-opt-in"))
        XCTAssertEqual(f.sinks.events, ["analytics:new-opt-in", "diagnostics:new-local-opt-in"])
    }

    func testAccountAndGuestTransitionsFenceLateEventsWithoutPuttingIdentityInStoredConsent() throws {
        let f = fixture()
        f.model.changeContext(to: "reader_A")
        f.model.load()
        f.model.setChoices(both)
        let a = try XCTUnwrap(f.model.captureTicket(for: .analytics))
        f.model.changeContext(to: "reader_B")
        XCTAssertFalse(f.emit(a, label: "late-A"))
        let b = try XCTUnwrap(f.model.captureTicket(for: .analytics))
        f.model.changeContext(to: nil)
        XCTAssertFalse(f.emit(b, label: "late-B"))
        XCTAssertTrue(f.emitCurrent(.analytics, label: "guest"))
        let json = String(decoding: try XCTUnwrap(f.storage.payload), as: UTF8.self)
        XCTAssertFalse(json.contains("reader_A"));XCTAssertFalse(json.contains("reader_B"))
        XCTAssertEqual(f.sinks.events, ["analytics:guest"])
    }

    func testDisablingOnePurposeDoesNotAuthorizeItThroughTheOtherChannel() throws {
        let f = fixture()
        f.model.changeContext(to: nil)
        f.model.load()
        f.model.setChoices(both)
        let oldAnalytics = try XCTUnwrap(f.model.captureTicket(for: .analytics))
        let oldDiagnostics = try XCTUnwrap(f.model.captureTicket(for: .diagnostics))
        f.model.setChoices(Choices(analyticsEnabled: false, diagnosticsEnabled: true))
        XCTAssertFalse(f.emit(oldAnalytics, label: "disabled-analytics"))
        XCTAssertFalse(f.emit(oldDiagnostics, label: "superseded-ticket"))
        XCTAssertFalse(f.emitCurrent(.analytics, label: "analytics-still-disabled"))
        XCTAssertTrue(f.emitCurrent(.diagnostics, label: "local-only"))
        f.model.setChoices(Choices(analyticsEnabled: true, diagnosticsEnabled: false))
        XCTAssertTrue(f.emitCurrent(.analytics, label: "analytics-only"))
        XCTAssertFalse(f.emitCurrent(.diagnostics, label: "diagnostics-now-disabled"))
        XCTAssertEqual(f.sinks.events, ["diagnostics:local-only", "analytics:analytics-only"])
    }

    func testPurposeBoundTicketsCannotBeReusedByTheOtherConcreteSink() throws {
        let f = fixture()
        f.model.changeContext(to: nil)
        f.model.load()
        f.model.setChoices(both)
        let analytics = try XCTUnwrap(f.model.captureTicket(for: .analytics))
        let diagnostics = try XCTUnwrap(f.model.captureTicket(for: .diagnostics))
        XCTAssertFalse(f.emit(analytics, channel: .diagnostics, label: "wrong-local-sink"))
        XCTAssertFalse(f.emit(diagnostics, channel: .analytics, label: "wrong-cloud-sink"))
        XCTAssertTrue(f.emit(analytics, channel: .analytics, label: "correct-analytics"))
        XCTAssertTrue(f.emit(diagnostics, channel: .diagnostics, label: "correct-local-log"))
        XCTAssertEqual(f.sinks.events, ["analytics:correct-analytics", "diagnostics:correct-local-log"])
    }

    func testARealDelayedCallbackCannotLogAfterWithdrawalReenableAndAccountChange() async throws {
        let f = fixture()
        f.model.changeContext(to: "reader_A")
        f.model.load()
        f.model.setChoices(both)
        let ticket = try XCTUnwrap(f.model.captureTicket(for: .analytics))
        let ready = expectation(description: "Local callback captured the old generation")
        let completed = expectation(description: "Local callback returned after context changed")
        let release = DispatchSemaphore(value: 0), result = ConsentPipelineResult()
        DispatchQueue.global().async {
            ready.fulfill()
            if release.wait(timeout: .now() + 5) == .success {
                result.value = f.emit(ticket, label: "late-reader-A")
            } else { result.value = true }
            completed.fulfill()
        }
        await fulfillment(of: [ready], timeout: 5)
        f.model.setChoices(off)
        f.model.changeContext(to: "reader_B")
        f.model.setChoices(both)
        release.signal()
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(result.value, false)
        XCTAssertTrue(f.sinks.events.isEmpty)
        XCTAssertTrue(f.emitCurrent(.analytics, label: "current-reader-B"))
        XCTAssertEqual(f.sinks.events, ["analytics:current-reader-B"])
    }

    @MainActor
    func testControllerConstructionAndRefreshReadOnlyTheInjectedSnapshot() {
        let f = fixture()
        var callbacks: [TelemetryConsentModel.Snapshot] = []
        let controller = TelemetryConsentController(model: f.model, onChange: { callbacks.append($0) })
        XCTAssertEqual(controller.snapshot.state, .unloaded)
        XCTAssertEqual(f.storage.readCount, 0)
        XCTAssertTrue(callbacks.isEmpty)
        f.model.changeContext(to: nil)
        f.model.load()
        controller.refresh()
        XCTAssertEqual(controller.snapshot.state, .notChosen)
        XCTAssertTrue(callbacks.isEmpty)
        controller.setAnalyticsEnabled(true)
        XCTAssertEqual(callbacks.count, 1)
        XCTAssertEqual(controller.snapshot.choices, Choices(analyticsEnabled: true, diagnosticsEnabled: false))
        controller.disableAll()
        XCTAssertEqual(callbacks.count, 2)
        XCTAssertEqual(controller.snapshot.choices, off)
    }

    @MainActor
    func testControllerPatchesFreshModelChoicesInsteadOfRestoringAStaleOtherPurpose() {
        let f = fixture()
        f.model.changeContext(to: nil)
        f.model.load()
        let controller = TelemetryConsentController(model: f.model, onChange: { _ in })
        f.model.setChoices(Choices(analyticsEnabled: false, diagnosticsEnabled: true))
        XCTAssertEqual(controller.snapshot.choices, off)
        controller.setAnalyticsEnabled(true)
        XCTAssertEqual(controller.snapshot.choices, both)
        f.model.setChoices(Choices(analyticsEnabled: false, diagnosticsEnabled: true))
        controller.setLocalDiagnosticsEnabled(false)
        XCTAssertEqual(controller.snapshot.choices, off)
    }

    @MainActor
    func testControllerSaveFailurePublishesDeniedStateAndDisableAllRetriesExplicitPersistence() {
        let f = fixture()
        f.model.changeContext(to: nil)
        f.model.load()
        var callbacks: [TelemetryConsentModel.Snapshot] = []
        let controller = TelemetryConsentController(model: f.model, onChange: { callbacks.append($0) })
        f.storage.failWrites = true
        controller.setAnalyticsEnabled(true)
        XCTAssertEqual(controller.snapshot.state, .writeFailed)
        XCTAssertEqual(controller.snapshot.choices, off)
        XCTAssertEqual(callbacks.last?.choices, off)
        XCTAssertTrue(f.storage.committedWrites.isEmpty)
        f.storage.failWrites = false
        controller.disableAll()
        XCTAssertEqual(controller.snapshot.state, .ready)
        XCTAssertEqual(controller.snapshot.choices, off)
        XCTAssertTrue(controller.snapshot.hasExplicitChoice)
        XCTAssertEqual(f.storage.committedWrites.count, 1)
        XCTAssertEqual(callbacks.count, 2)
    }

    @MainActor
    func testControllerReflectsARevocationPerformedSynchronouslyByItsAdapterCallback() {
        let f = fixture()
        f.model.changeContext(to: nil)
        f.model.load()
        let controller = TelemetryConsentController(model: f.model, onChange: { _ in f.model.setChoices(.off) })
        controller.setAnalyticsEnabled(true)
        XCTAssertEqual(controller.snapshot.choices, off)
        XCTAssertEqual(controller.snapshot, f.model.snapshot())
        XCTAssertFalse(f.emitCurrent(.analytics, label: "closed-by-adapter"))
    }

    @MainActor
    func testTheCompleteInjectedPipelineNeverInitializesFirebase() throws {
        XCTAssertNil(FirebaseApp.allApps)
        let f = fixture(try record())
        f.model.changeContext(to: nil)
        f.model.load()
        XCTAssertTrue(f.emitCurrent(.analytics, label: "local-test"))
        XCTAssertTrue(f.emitCurrent(.diagnostics, label: "local-test"))
        f.model.setChoices(off)
        f.model.changeContext(to: "reader_A")
        assertBlocked(f)
        XCTAssertNil(FirebaseApp.allApps)
    }
}

private enum ConsentPipelineFailure: Error { case read, write }

private final class ConsentPipelineStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    private var readFailure = false, writeFailure = false
    private var reads = 0, writes: [Data] = []
    init(_ payload: Data?) { bytes = payload }
    var payload: Data? { lock.lock();defer { lock.unlock() };return bytes }
    var failReads: Bool { get { lock.lock();defer { lock.unlock() };return readFailure } set { lock.lock();readFailure = newValue;lock.unlock() } }
    var failWrites: Bool { get { lock.lock();defer { lock.unlock() };return writeFailure } set { lock.lock();writeFailure = newValue;lock.unlock() } }
    var readCount: Int { lock.lock();defer { lock.unlock() };return reads }
    var committedWrites: [Data] { lock.lock();defer { lock.unlock() };return writes }
    func read() throws -> Data? {
        lock.lock();defer { lock.unlock() };reads += 1
        if readFailure { throw ConsentPipelineFailure.read }
        return bytes
    }
    func write(_ data: Data) throws {
        lock.lock();defer { lock.unlock() }
        if writeFailure { throw ConsentPipelineFailure.write }
        bytes = data;writes.append(data)
    }
}

private final class ConsentPipelineSinks: @unchecked Sendable {
    private let lock = NSLock()
    private var history: [String] = []
    func append(_ event: String) { lock.lock();history.append(event);lock.unlock() }
    var events: [String] { lock.lock();defer { lock.unlock() };return history.filter { !$0.hasPrefix("clear:") } }
    var clearCount: Int { lock.lock();defer { lock.unlock() };return history.filter { $0.hasPrefix("clear:") }.count }
}

private struct ConsentPipelineFixture: Sendable {
    let storage: ConsentPipelineStorage
    let sinks: ConsentPipelineSinks
    let model: TelemetryConsentModel
    init(payload: Data?, now: Date) {
        let storage = ConsentPipelineStorage(payload), sinks = ConsentPipelineSinks()
        self.storage = storage;self.sinks = sinks
        model = TelemetryConsentModel(storage: .init(read: { try storage.read() }, write: { try storage.write($0) }),
                                      now: { now }, sinks: .init(clearAnalytics: { sinks.append("clear:analytics") }, clearDiagnostics: { sinks.append("clear:diagnostics") }))
    }
    func emitCurrent(_ channel: TelemetryConsentModel.Channel, label: String) -> Bool {
        guard let ticket = model.captureTicket(for: channel) else { return false }
        return emit(ticket, channel: channel, label: label)
    }
    func emit(_ ticket: TelemetryConsentModel.Ticket, channel: TelemetryConsentModel.Channel = .analytics, label: String) -> Bool {
        let prefix = channel == .analytics ? "analytics" : "diagnostics"
        return model.withPermission(ticket, for: channel) { sinks.append("\(prefix):\(label)") }
    }
}

private final class ConsentPipelineResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    var value: Bool? {
        get { lock.lock();defer { lock.unlock() };return stored }
        set { lock.lock();stored = newValue;lock.unlock() }
    }
}
