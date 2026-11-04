import Foundation
import XCTest
@testable import Apropos

/// Actual bounded queue/files/readback; no credentials, SDK, provider or network.
@MainActor
final class ReaderDeletionCheckpointTests: XCTestCase {
    private typealias Store = ReaderTransitionRecoveryStore
    private typealias Checkpoint = Store.DeletionCheckpoint
    private typealias Request = ReaderAccountDeletionContract.Request
    private enum Injected: Error { case writeFailed, timedOut }
    private final class Disk: @unchecked Sendable {
        enum Mode { case commit, fail, falseACK, commitThenThrow }
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var mode: Mode = .commit, hold = false, started = false
        private var writes = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return writes }
        var isHeld: Bool { lock.lock(); defer { lock.unlock() }; return started }
        func configure(_ mode: Mode, hold: Bool = false) {
            lock.lock(); self.mode = mode; self.hold = hold; lock.unlock()
        }
        func release() { semaphore.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            guard url.lastPathComponent == "reader-deletion-v1.json" else {
                try data.write(to: url, options: .atomic); return
            }
            lock.lock(); let mode = mode, hold = hold; writes += 1; started = hold; lock.unlock()
            defer { lock.lock(); started = false; lock.unlock() }
            if hold, semaphore.wait(timeout: .now() + 5) != .success { throw Injected.timedOut }
            switch mode {
            case .commit: try data.write(to: url, options: .atomic)
            case .fail: throw Injected.writeFailed
            case .falseACK: break
            case .commitThenThrow:
                try data.write(to: url, options: .atomic)
                throw Injected.writeFailed
            }
        }
    }
    @MainActor private struct Fixture {
        let root: URL
        let disk: Disk
        let store: Store
        let recovery: ReaderTransitionRecovery
        let request: Request
        let digest: String
        var markerURL: URL { root.appendingPathComponent("reader-transition-v1.json") }
        var checkpointURL: URL { root.appendingPathComponent("reader-deletion-v1.json") }
        func parent() async throws -> Checkpoint {
            try await recovery.recordDeletion(request: request, phase: .parent, configurationDigest: digest)
        }
        func ledger() async throws -> Checkpoint {
            try await recovery.recordDeletion(request: request, phase: .ledger, configurationDigest: digest)
        }
    }
    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deletion-checkpoint-" + UUID().uuidString)
        let disk = Disk(), store = Store(rootDirectory: root, replace: { try disk.replace($0, $1) })
        let recovery = ReaderTransitionRecovery(store: store)
        let request = try Request(expectedUID: "reader-A", membershipEpoch: 7)
        let digest = Store.deletionConfigurationDigest(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                                                       endpoint: URL(string: "https://deletion.example.invalid/reader")!)
        addTeardownBlock { disk.release(); try? FileManager.default.removeItem(at: root) }
        try await recovery.bootstrap()
        _ = try await recovery.seal(binding: .init(ownerUID: request.expectedUID, epoch: request.membershipEpoch))
        return Fixture(root: root, disk: disk, store: store, recovery: recovery, request: request, digest: digest)
    }
    private func read(_ store: Store) async throws -> Store.Resumption {
        try await withCheckedThrowingContinuation { continuation in store.readResumption { continuation.resume(with: $0) } }
    }
    private func save(_ checkpoint: Checkpoint, expected: Checkpoint?, store: Store) async throws -> Checkpoint {
        try await withCheckedThrowingContinuation { continuation in
            store.saveDeletionCheckpoint(checkpoint, expected: expected) { continuation.resume(with: $0) }
        }
    }
    private func failure<T>(_ operation: () async throws -> T) async -> Error? {
        do { _ = try await operation(); XCTFail("Expected a closed recovery boundary"); return nil }
        catch { return error }
    }
    private func mutate(_ file: URL, _ change: (inout [String: Any]) -> Void) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        change(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file, options: .atomic)
    }
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<2_000 { if condition() { return }; try? await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Expected physical checkpoint stage was not reached")
    }

    func testGenericMarkerIsNeverUpconvertedAndItsOriginalBytesRemainImmutable() async throws {
        let f = try await fixture()
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: f.markerURL))
        let pretty = try JSONSerialization.data(withJSONObject: original, options: [.prettyPrinted, .sortedKeys])
        try pretty.write(to: f.markerURL, options: .atomic)
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root))
        try await restarted.bootstrap()
        XCTAssertNil(restarted.deletionCheckpoint); XCTAssertFalse(restarted.legacyWritesPermitted)
        let initial = try await read(f.store)
        XCTAssertNil(initial.checkpoint)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.checkpointURL.path))
        _ = try await f.parent()
        XCTAssertEqual(try Data(contentsOf: f.markerURL), pretty)
    }

    func testParentRoundTripRetainsExactOriginalRequestAndConfigurationAfterRestart() async throws {
        let f = try await fixture(), parent = try await f.parent()
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root))
        try await restarted.bootstrap()
        XCTAssertEqual(restarted.deletionCheckpoint, parent); XCTAssertFalse(restarted.admission.isAllowed)
        XCTAssertEqual(parent.request, f.request); XCTAssertEqual(parent.phase, .parent); XCTAssertEqual(parent.configurationDigest, f.digest)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.checkpointURL)) as? [String: Any])
        XCTAssertEqual(Set(wire.keys), ["schemaVersion", "scope", "marker", "request", "requestID", "phase", "configurationDigest"])
        XCTAssertEqual(wire["requestID"] as? String, f.request.requestID)
        let request = try XCTUnwrap(wire["request"] as? [String: Any])
        XCTAssertEqual(Set(request.keys), ["expectedUID", "membershipEpoch"])
        XCTAssertEqual(request["expectedUID"] as? String, "reader-A"); XCTAssertEqual(request["membershipEpoch"] as? Int, 7)
        XCTAssertNil(wire["receipt"]); XCTAssertNil(wire["idToken"])
    }

    func testPhaseAdvanceUsesExactCASAndParentReconciliationNeverDowngradesLedger() async throws {
        let f = try await fixture(), parent = try await f.parent()
        let repeated = try await f.parent(); XCTAssertEqual(repeated, parent); XCTAssertEqual(f.disk.count, 1)
        let ledger = try Checkpoint(marker: parent.marker, request: parent.request, phase: .ledger, configurationDigest: f.digest)
        let failure1 = await failure { try await save(ledger, expected: nil, store: f.store) }
        XCTAssertEqual(failure1 as? Store.Failure, .conflictingCheckpoint)
        let accepted = try await f.ledger(); XCTAssertEqual(accepted, ledger); XCTAssertEqual(f.disk.count, 2)
        let bytes = try Data(contentsOf: f.checkpointURL)
        let reconciled = try await f.parent()
        XCTAssertEqual(reconciled, ledger); XCTAssertEqual(f.disk.count, 2)
        XCTAssertEqual(try Data(contentsOf: f.checkpointURL), bytes)
        let failure2 = await failure { try await save(parent, expected: ledger, store: f.store) }
        XCTAssertEqual(failure2 as? Store.Failure, .conflictingCheckpoint)
    }

    func testLedgerCannotBeFirstAndOtherFamiliesOrConfigurationCannotReplaceParent() async throws {
        let f = try await fixture()
        let failure3 = await failure { try await f.ledger() }
        XCTAssertEqual(failure3 as? Store.Failure, .conflictingCheckpoint)
        let parent = try await f.parent(), bytes = try Data(contentsOf: f.checkpointURL)
        let otherDigest = Store.deletionConfigurationDigest(projectID: "other-project", appID: "1:123456789:ios:abcdef123456",
                                                           endpoint: URL(string: "https://deletion.example.invalid/reader")!)
        let failure4 = await failure { try await f.recovery.recordDeletion(request: f.request, phase: .parent,
            configurationDigest: otherDigest) }
        XCTAssertEqual(failure4 as? Store.Failure, .conflictingCheckpoint)
        XCTAssertThrowsError(try Checkpoint(marker: parent.marker, request: .init(expectedUID: "reader-B", membershipEpoch: 7),
                                           phase: .parent, configurationDigest: f.digest))
        XCTAssertThrowsError(try Checkpoint(marker: parent.marker, request: .init(expectedUID: "reader-A", membershipEpoch: 8),
                                           phase: .parent, configurationDigest: f.digest))
        XCTAssertEqual(try Data(contentsOf: f.checkpointURL), bytes)
    }

    func testFailedOrFalseAcknowledgedWriteNeverBecomesSavedIntentAndCanRetryOriginal() async throws {
        for mode in [Disk.Mode.fail, .falseACK] {
            let f = try await fixture(); f.disk.configure(mode)
            _ = await failure { try await f.parent() }
            XCTAssertNil(f.recovery.deletionCheckpoint); XCTAssertFalse(f.recovery.admission.isAllowed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.checkpointURL.path))
            f.disk.configure(.commit)
            let accepted = try await f.parent()
            XCTAssertEqual(accepted.request, f.request); XCTAssertEqual(accepted.phase, .parent); XCTAssertEqual(f.disk.count, 2)
        }
    }

    func testCommitThenThrowRequiresActualReadbackAndDoesNotRewriteExactRetry() async throws {
        let f = try await fixture(); f.disk.configure(.commitThenThrow)
        let parent = try await f.parent(), bytes = try Data(contentsOf: f.checkpointURL)
        XCTAssertEqual(f.recovery.deletionCheckpoint, parent); XCTAssertEqual(f.disk.count, 1)
        let retried = try await f.parent()
        XCTAssertEqual(retried, parent); XCTAssertEqual(f.disk.count, 1)
        XCTAssertEqual(try Data(contentsOf: f.checkpointURL), bytes)
    }

    func testCancelledPhysicalCheckpointRetainsBusySlotAndPreservesLateDiskSuccess() async throws {
        let f = try await fixture(); f.disk.configure(.commit, hold: true)
        let task = Task { try await f.parent() }
        await eventually { f.disk.isHeld }
        task.cancel()
        XCTAssertTrue(f.recovery.isBusy); XCTAssertFalse(f.recovery.admission.isAllowed)
        let busy = await failure { try await f.parent() }
        guard case .busy? = busy as? ReaderTransitionRecovery.Failure else {
            f.disk.release(); _ = await failure { try await task.value }
            XCTFail("Physical checkpoint lost busy ownership"); return
        }
        f.disk.release()
        _ = await failure { try await task.value }
        XCTAssertFalse(f.recovery.isBusy); XCTAssertNotNil(f.recovery.deletionCheckpoint)
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root))
        try await restarted.bootstrap()
        XCTAssertEqual(restarted.deletionCheckpoint, f.recovery.deletionCheckpoint); XCTAssertFalse(restarted.admission.isAllowed)
    }

    func testOrphanCheckpointRefusesBothStartupAndResumptionInsteadOfOpeningLegacy() async throws {
        let f = try await fixture(); _ = try await f.parent()
        try FileManager.default.removeItem(at: f.markerURL)
        let failure5 = await failure { try await read(Store(rootDirectory: f.root)) }
        XCTAssertEqual(failure5 as? Store.Failure, .conflictingMarker)
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root))
        _ = await failure { try await restarted.bootstrap() }
        XCTAssertFalse(restarted.admission.isAllowed); XCTAssertEqual(restarted.status, .unavailable)
    }

    func testChangedMarkerIdentityCannotAdoptAnOtherwiseValidCheckpoint() async throws {
        let f = try await fixture(); _ = try await f.parent()
        try mutate(f.markerURL) { $0["transitionID"] = UUID().uuidString.lowercased() }
        let failure6 = await failure { try await read(Store(rootDirectory: f.root)) }
        XCTAssertEqual(failure6 as? Store.Failure, .conflictingMarker)
        XCTAssertFalse(f.recovery.admission.isAllowed)
    }

    func testStrictCheckpointRejectsUnknownNestedRequestWrongIDsAndMalformedPhase() async throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["extra"] = true }, { $0["phase"] = "complete" }, { $0["requestID"] = String(repeating: "0", count: 64) },
            { $0["configurationDigest"] = "unbound" },
            { var request = $0["request"] as! [String: Any]; request["scope"] = "another"; $0["request"] = request },
            { var request = $0["request"] as! [String: Any]; request["membershipEpoch"] = 8; $0["request"] = request }
        ]
        for mutation in mutations {
            let f = try await fixture(); _ = try await f.parent(); try mutate(f.checkpointURL, mutation)
            let failure7 = await failure { try await read(Store(rootDirectory: f.root)) }
            XCTAssertEqual(failure7 as? Store.Failure, .invalidCheckpoint)
            let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root))
            _ = await failure { try await restarted.bootstrap() }; XCTAssertFalse(restarted.admission.isAllowed)
        }
    }

    func testOversizeSymlinkAndDirectoryCheckpointAreBoundedReadFailures() async throws {
        for kind in 0..<3 {
            let f = try await fixture(); _ = try await f.parent()
            try FileManager.default.removeItem(at: f.checkpointURL)
            if kind == 0 { try Data(repeating: 65, count: Store.maximumCheckpointBytes + 1).write(to: f.checkpointURL) }
            else if kind == 1 { try FileManager.default.createSymbolicLink(at: f.checkpointURL, withDestinationURL: f.markerURL) }
            else { try FileManager.default.createDirectory(at: f.checkpointURL, withIntermediateDirectories: false) }
            let failure8 = await failure { try await read(Store(rootDirectory: f.root)) }
            XCTAssertEqual(failure8 as? Store.Failure,
                           kind == 0 ? .limitExceeded : .readFailed)
        }
    }

    func testObservedLedgerCheckpointCannotDisappearOrRegressWithinSameRecovery() async throws {
        for remove in [false, true] {
            let f = try await fixture(); _ = try await f.parent(); let parentBytes = try Data(contentsOf: f.checkpointURL)
            let ledger = try await f.ledger()
            if remove { try FileManager.default.removeItem(at: f.checkpointURL) }
            else { try parentBytes.write(to: f.checkpointURL, options: .atomic) }
            let failure9 = await failure { try await f.recovery.readResumption() }
            XCTAssertEqual(failure9 as? Store.Failure,
                           remove ? .missingCheckpoint : .conflictingCheckpoint)
            XCTAssertEqual(f.recovery.deletionCheckpoint, ledger); XCTAssertFalse(f.recovery.admission.isAllowed)
        }
    }

    func testConfigurationDigestDistinguishesProjectAppAndExactEndpoint() {
        let base = URL(string: "https://deletion.example.invalid/reader")!
        let values = [
            Store.deletionConfigurationDigest(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456", endpoint: base),
            Store.deletionConfigurationDigest(projectID: "other-project", appID: "1:123456789:ios:abcdef123456", endpoint: base),
            Store.deletionConfigurationDigest(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123457", endpoint: base),
            Store.deletionConfigurationDigest(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                                             endpoint: URL(string: "https://deletion.example.invalid/reader-v2")!)
        ]
        XCTAssertEqual(Set(values).count, 4); XCTAssertTrue(values.allSatisfy { $0.count == 64 })
    }
}
