import Foundation
import XCTest
@testable import Apropos

final class TelemetryConsentModelTests: XCTestCase {
    func testConstructionIsInertAndEveryGateStartsClosed() {
        let f = Fixture()
        let model = f.model()
        XCTAssertEqual(f.reads, 0)
        XCTAssertEqual(f.writes, 0)
        XCTAssertEqual(f.clears, 0)
        XCTAssertEqual(model.snapshot().state, .unloaded)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertNil(model.captureTicket(for: .diagnostics))
    }

    func testExplicitStoredChoiceCannotGrantTicketsBeforeCanonicalContextIsResolved() {
        let model = Fixture(data: record()).model()
        XCTAssertEqual(model.load().state, .ready)
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertNil(model.captureTicket(for: .diagnostics))
        model.changeContext(to: nil)
        XCTAssertNotNil(model.captureTicket(for: .analytics))
        XCTAssertNotNil(model.captureTicket(for: .diagnostics))
    }

    func testMissingRecordIsNotConsentAndLoadDoesNotReadAgain() {
        let f = Fixture(), model = f.model()
        XCTAssertEqual(model.load().state, .notChosen)
        f.data = record()
        XCTAssertEqual(model.load().state, .notChosen)
        XCTAssertEqual(f.reads, 1)
        XCTAssertNil(model.captureTicket(for: .analytics))
    }

    func testLegacyUnknownOversizedAndMalformedRecordsCannotEnableCollection() {
        for data in [Data("not json".utf8), Data("[]".utf8), Data(repeating: 32, count: 2049),
                     Data("{\"analyticsEnabled\":true,\"crashReportsEnabled\":true}".utf8),
                     record(extra: ["diagnosticsEnabled": true]), record(extra: ["unexpected": "private"]),
                     record(extra: ["analyticsEnabled": 1]), record(extra: ["localDiagnosticsEnabled": "true"])] {
            let f = Fixture(data: data), model = f.model()
            XCTAssertEqual(model.load().state, .invalidRecord)
            XCTAssertFalse(model.snapshot().hasExplicitChoice)
            XCTAssertEqual(model.snapshot().choices, .off)
            XCTAssertNil(model.captureTicket(for: .analytics))
            XCTAssertNil(model.captureTicket(for: .diagnostics))
            XCTAssertEqual(f.writes, 0)
        }
    }

    func testUnsupportedSchemaAndPolicyDoNotMigrateGrants() {
        for data in [record(extra: ["schemaVersion": 2]), record(extra: ["policyVersion": 2])] {
            let model = Fixture(data: data).model()
            XCTAssertEqual(model.load().state, .unsupportedVersion)
            XCTAssertNil(model.captureTicket(for: .analytics))
        }
    }

    func testFutureZeroAndFractionalRecordTimesFailClosed() {
        for value: Any in [1_800_000_000_001 as Int64, 0, -1, 100.5] {
            let model = Fixture(data: record(extra: ["recordedAtMs": value])).model()
            XCTAssertEqual(model.load().state, .invalidRecord)
            XCTAssertEqual(model.snapshot().choices, .off)
        }
    }

    func testInvalidLoadClockDoesNotAcceptAnOtherwiseExplicitRecord() {
        for seconds in [Double.nan, .infinity, -1, 0, 9_007_199_254_741.0] {
            let f = Fixture(data: record()), model = f.model()
            f.clock = Date(timeIntervalSince1970: seconds)
            XCTAssertEqual(model.load().state, .invalidClock)
            XCTAssertNil(model.captureTicket(for: .diagnostics))
        }
    }

    func testExplicitAnalyticsChoiceDoesNotGrantLocalDiagnosticsAndViceVersa() {
        let f = Fixture(), model = f.model()
        model.changeContext(to: nil)
        XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: false)).state, .ready)
        XCTAssertNotNil(model.captureTicket(for: .analytics))
        XCTAssertNil(model.captureTicket(for: .diagnostics))
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertNotNil(model.captureTicket(for: .diagnostics))
    }

    func testPersistenceNamesDiagnosticsScopeLocalAndRoundTripsExplicitChoice() throws {
        let f = Fixture(), model = f.model()
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(f.data)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "policyVersion", "analyticsEnabled", "localDiagnosticsEnabled", "recordedAtMs"])
        XCTAssertEqual(object["localDiagnosticsEnabled"] as? Bool, true)
        let restarted = f.model()
        XCTAssertEqual(restarted.load().choices, model.snapshot().choices)
        XCTAssertTrue(restarted.snapshot().hasExplicitChoice)
    }

    func testWithdrawalClosesBothChannelsAndOldTicketsBeforeAnyPersistenceWork() throws {
        let f = Fixture(), model = f.model()
        model.changeContext(to: nil)
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        let analytics = try XCTUnwrap(model.captureTicket(for: .analytics)), diagnostics = try XCTUnwrap(model.captureTicket(for: .diagnostics))
        f.onWrite = {
            XCTAssertNil(model.captureTicket(for: .analytics))
            XCTAssertNil(model.captureTicket(for: .diagnostics))
            XCTAssertFalse(model.withPermission(analytics) { XCTFail("late Analytics event") })
        }
        model.setChoices(.off)
        XCTAssertFalse(model.withPermission(diagnostics) { XCTFail("late diagnostic event") })
        XCTAssertEqual(model.snapshot().choices, .off)
    }

    func testReenableCannotResurrectQueuedEvidenceFromAnOlderConsentGeneration() throws {
        let model = Fixture().model()
        model.changeContext(to: nil)
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        let old = try XCTUnwrap(model.captureTicket(for: .diagnostics))
        model.setChoices(.off)
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        XCTAssertFalse(model.withPermission(old) { XCTFail("old report became eligible again") })
        let current = try XCTUnwrap(model.captureTicket(for: .diagnostics))
        var calls = 0
        XCTAssertTrue(model.withPermission(current, for: .diagnostics) { calls += 1 })
        XCTAssertEqual(calls, 1)
    }

    func testAccountContextChangeFencesEvidenceAndClearsWithoutPersistingOrGrantingConsent() throws {
        let f = Fixture(), model = f.model()
        model.load()
        XCTAssertEqual(model.changeContext(to: "A").choices, .off)
        XCTAssertEqual(f.writes, 0)
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        let ticket = try XCTUnwrap(model.captureTicket(for: .analytics)), writes = f.writes, clears = f.clears
        model.changeContext(to: "B")
        XCTAssertFalse(model.withPermission(ticket) { XCTFail("old account event") })
        XCTAssertEqual(f.writes, writes)
        XCTAssertEqual(f.clears, clears + 2)
        XCTAssertEqual(model.snapshot().choices, .init(analyticsEnabled: true, diagnosticsEnabled: true))
    }

    func testIdenticalContextAndSavedChoiceAreIdempotent() throws {
        let f = Fixture(), model = f.model(), desired = TelemetryConsentModel.Choices(analyticsEnabled: true, diagnosticsEnabled: false)
        model.setChoices(desired)
        model.changeContext(to: nil)
        let before = model.snapshot(), writes = f.writes, clears = f.clears
        let ticket = try XCTUnwrap(model.captureTicket(for: .analytics))
        XCTAssertEqual(model.setChoices(desired), before)
        XCTAssertEqual(model.changeContext(to: nil), before)
        XCTAssertEqual(f.writes, writes)
        XCTAssertEqual(f.clears, clears)
        XCTAssertTrue(model.withPermission(ticket) {})
    }

    func testWriteFailureStaysOffAndOneShotLoadCannotRestoreTheOldPersistedGrant() {
        let f = Fixture(data: record()), model = f.model()
        model.load()
        f.failWrite = true
        let failure = model.setChoices(.off)
        XCTAssertEqual(failure.state, .writeFailed)
        XCTAssertEqual(failure.choices, .off)
        XCTAssertFalse(failure.hasExplicitChoice)
        XCTAssertEqual(model.load(), failure)
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertNil(model.captureTicket(for: .diagnostics))
    }

    func testExplicitSuccessfulRetryCanRecoverAfterStorageFailure() {
        let f = Fixture(data: record()), model = f.model()
        model.load()
        f.failWrite = true
        model.setChoices(.off)
        f.failWrite = false
        XCTAssertEqual(model.setChoices(.off).state, .ready)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertTrue(model.snapshot().hasExplicitChoice)
        XCTAssertEqual(f.writes, 2)
    }

    func testReadFailureDoesNotBecomeAConsentGrantWhenStorageLaterRecovers() {
        let f = Fixture(data: record()), model = f.model()
        f.failRead = true
        XCTAssertEqual(model.load().state, .readFailed)
        f.failRead = false
        XCTAssertEqual(model.load().state, .readFailed)
        XCTAssertNil(model.captureTicket(for: .analytics))
    }

    func testBufferClearRunsWithClosedGatesAndRecursiveSnapshotReadsAreSafe() {
        let f = Fixture(), box = ModelBox()
        f.onClear = {
            XCTAssertEqual(box.value?.snapshot().choices, .off)
            XCTAssertNil(box.value?.captureTicket(for: .analytics))
            XCTAssertNil(box.value?.captureTicket(for: .diagnostics))
        }
        let model = f.model()
        box.value = model
        XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true)).state, .ready)
        XCTAssertEqual(f.clears, 2)
    }

    func testReentrantWithdrawalInsideClearPreventsTheOuterGrantFromBeingSaved() {
        let f = Fixture(), box = ModelBox()
        var once = false
        f.onClear = {
            guard !once else { return }
            once = true
            _ = box.value?.setChoices(.off)
        }
        let model = f.model()
        box.value = model
        XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true)).state, .writeFailed)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertEqual(f.writes, 0)
    }

    func testReentrantWithdrawalDuringWriteCannotReopenTheOuterGrant() {
        let f = Fixture(), box = ModelBox()
        f.onWrite = { _ = box.value?.setChoices(.off) }
        let model = f.model()
        box.value = model
        XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true)).state, .writeFailed)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertEqual(model.load().state, .writeFailed)
    }

    func testTicketCannotCrossModelOrPurposeBoundaries() throws {
        let first = Fixture().model(), second = Fixture().model()
        first.changeContext(to: nil)
        second.changeContext(to: nil)
        first.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        second.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true))
        let diagnosticTicket = try XCTUnwrap(first.captureTicket(for: .diagnostics))
        XCTAssertFalse(first.withPermission(diagnosticTicket, for: .analytics) { XCTFail("wrong purpose") })
        XCTAssertFalse(second.withPermission(diagnosticTicket) { XCTFail("wrong model") })
    }

    func testInvalidOrRegressedClockAfterWriteKeepsGatesClosed() {
        for seconds in [Double.nan, 1_799_999_999] {
            let f = Fixture(), model = f.model()
            f.onWrite = { f.clock = Date(timeIntervalSince1970: seconds) }
            XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true)).state, .invalidClock)
            XCTAssertEqual(model.snapshot().choices, .off)
            XCTAssertNil(model.captureTicket(for: .analytics))
        }
    }

    func testReentrantWithdrawalFromLoadClockCannotRestoreTheStoredGrant() {
        let f = Fixture(data: record()), box = ModelBox(), model = f.model()
        box.value = model
        model.changeContext(to: nil)
        f.onClock = { _ = box.value?.setChoices(.off) }
        XCTAssertEqual(model.load().state, .writeFailed)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertEqual(f.writes, 0)
        XCTAssertEqual(model.load().state, .writeFailed)
    }

    func testReentrantWithdrawalFromPreWriteClockPreventsSavingTheOuterGrant() {
        let f = Fixture(), box = ModelBox(), model = f.model()
        box.value = model
        model.changeContext(to: nil)
        f.onClock = { _ = box.value?.setChoices(.off) }
        XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true)).state, .writeFailed)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertEqual(f.writes, 0)
    }

    func testReentrantWithdrawalFromPostWriteClockCannotEnableTheOuterGrant() {
        let f = Fixture(), box = ModelBox(), model = f.model()
        box.value = model
        model.changeContext(to: nil)
        f.onClock = {
            if f.clockReads == 2 { _ = box.value?.setChoices(.off) }
        }
        XCTAssertEqual(model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: true)).state, .writeFailed)
        XCTAssertEqual(model.snapshot().choices, .off)
        XCTAssertEqual(f.writes, 1)
        XCTAssertNil(model.captureTicket(for: .analytics))
        XCTAssertEqual(model.load().state, .writeFailed)
    }

    private func record(extra: [String: Any] = [:]) -> Data {
        var object: [String: Any] = ["schemaVersion": 1, "policyVersion": 1, "analyticsEnabled": true,
                                     "localDiagnosticsEnabled": true, "recordedAtMs": Int64(1_800_000_000_000)]
        object.merge(extra) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

private final class ModelBox: @unchecked Sendable {
    var value: TelemetryConsentModel?
}
private final class Fixture: @unchecked Sendable {
    var data: Data?
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var reads = 0, writes = 0, clears = 0, clockReads = 0
    var failRead = false, failWrite = false
    var onClock: (() -> Void)?
    var onWrite: (() -> Void)?
    var onClear: (() -> Void)?
    init(data: Data? = nil) { self.data = data }
    func model() -> TelemetryConsentModel {
        TelemetryConsentModel(storage: .init(read: {
            self.reads += 1
            if self.failRead { throw CocoaError(.fileReadUnknown) }
            return self.data
        }, write: { data in
            self.writes += 1
            self.onWrite?()
            if self.failWrite { throw CocoaError(.fileWriteUnknown) }
            self.data = data
        }), now: {
            self.clockReads += 1
            self.onClock?()
            return self.clock
        }, sinks: .init(clearAnalytics: {
            self.clears += 1
            self.onClear?()
        }, clearDiagnostics: {
            self.clears += 1
            self.onClear?()
        }))
    }
}
