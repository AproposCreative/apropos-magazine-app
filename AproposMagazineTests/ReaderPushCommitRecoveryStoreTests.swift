import CryptoKit
import Foundation
import XCTest
@testable import Apropos

/// Actual bounded serial file operations. Reconstruction is a new local object
/// over isolated files, not process termination, fsync or a live Keychain test.
@MainActor
final class ReaderPushCommitRecoveryStoreTests: XCTestCase {
    private typealias Store = ReaderTransitionRecoveryStore
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Pending = Store.PushCommitCheckpoint
    private enum Fault: Error { case injected, heldTooLong }
    private final class Disk: @unchecked Sendable {
        enum Mode { case commit, fail, falseACK, commitThenThrow, failReadback, changeParent }
        private let lock = NSLock(), gate = DispatchSemaphore(value: 0)
        private var mode: Mode = .commit, held = false, entered = false, failRead = false
        private var writes = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return writes }
        var isHeld: Bool { lock.lock(); defer { lock.unlock() }; return entered }
        func configure(_ mode: Mode, hold: Bool = false) { lock.lock(); self.mode = mode; held = hold; lock.unlock() }
        func release() { gate.signal() }
        func beforeRead() throws {
            lock.lock(); let reject = failRead; failRead = false; lock.unlock()
            if reject { throw Fault.injected }
        }
        func replace(_ bytes: Data, _ url: URL) throws {
            guard url.lastPathComponent == "reader-push-commit-v1.json" else { try bytes.write(to: url, options: .atomic); return }
            lock.lock(); let mode = mode, hold = held; writes += 1; entered = hold; lock.unlock()
            defer { lock.lock(); entered = false; lock.unlock() }
            if hold, gate.wait(timeout: .now() + 5) != .success { throw Fault.heldTooLong }
            switch mode {
            case .fail: throw Fault.injected
            case .falseACK: return
            case .commit: try bytes.write(to: url, options: .atomic)
            case .commitThenThrow: try bytes.write(to: url, options: .atomic); throw Fault.injected
            case .failReadback:
                try bytes.write(to: url, options: .atomic)
                lock.lock(); failRead = true; lock.unlock()
            case .changeParent:
                try bytes.write(to: url, options: .atomic)
                try Data("{}".utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("reader-deletion-v1.json"), options: .atomic)
                lock.lock(); failRead = true; lock.unlock()
            }
        }
    }
    @MainActor private struct Fixture {
        let root: URL
        let disk: Disk
        let store: Store
        let recovery: ReaderTransitionRecovery
        let parent: Store.DeletionCheckpoint
        let ledger: Store.DeletionCheckpoint
        let record: PushInstallationRecord
        let candidate: Pending
        var childURL: URL { root.appendingPathComponent("reader-push-commit-v1.json") }
        var markerURL: URL { root.appendingPathComponent("reader-transition-v1.json") }
        var ledgerURL: URL { root.appendingPathComponent("reader-deletion-v1.json") }
    }
    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("push-commit-checkpoint-" + UUID().uuidString)
        let disk = Disk(), store = Store(rootDirectory: root, replace: { try disk.replace($0, $1) }, beforeRead: { try disk.beforeRead() })
        let recovery = ReaderTransitionRecovery(store: store)
        addTeardownBlock { disk.release(); try? FileManager.default.removeItem(at: root) }
        try await recovery.bootstrap()
        let request = try Contract.Request(expectedUID: "reader-A", membershipEpoch: 7)
        _ = try await recovery.seal(binding: .init(ownerUID: request.expectedUID, epoch: request.membershipEpoch))
        let digest = Store.deletionConfigurationDigest(projectID: "local-fixture", appID: "1:123456789:ios:abcdef123456",
            endpoint: URL(string: "https://reader.example.invalid/delete")!)
        let parent = try await recovery.recordDeletion(request: request, phase: .parent, configurationDigest: digest)
        let ledger = try await recovery.recordDeletion(request: request, phase: .ledger, configurationDigest: digest)
        let id = "123e4567-e89b-42d3-a456-426614174000"
        let ack = PushAcknowledgedInstallationBinding(schemaVersion: 1, installationId: id, appId: "1:123456789:ios:abcdef123456",
            ownerUID: "reader-A", ownerEpoch: 3, revision: 9, clientRevision: 11, status: .active)
        let record = PushInstallationRecord(installationId: id, key: String(repeating: "k", count: 43), revision: 11,
            intentHash: String(repeating: "a", count: 64), revisionStartedAt: Date(timeIntervalSince1970: 100), acknowledgedBinding: ack)
        let snapshot = try Contract.PushSnapshot(requestId: "original_request_001", installationId: id, appId: ack.appId,
            ownerUID: "reader-A", ownerEpoch: 3, revision: 9, clientRevision: 11, stateDigest: String(repeating: "d", count: 64))
        let candidate = try Pending(checkpoint: ledger, snapshot: snapshot, recordDigest: Pending.recordDigest(for: record))
        return Fixture(root: root, disk: disk, store: store, recovery: recovery, parent: parent, ledger: ledger, record: record, candidate: candidate)
    }
    private func read(_ store: Store) async throws -> Store.Resumption {
        try await withCheckedThrowingContinuation { continuation in store.readResumption { continuation.resume(with: $0) } }
    }
    private func save(_ value: Pending, expected: Pending? = nil, store: Store) async throws -> Pending {
        try await withCheckedThrowingContinuation { continuation in
            store.savePushCommitCheckpoint(value, expected: expected) { continuation.resume(with: $0) }
        }
    }
    private func failure<T>(_ operation: () async throws -> T) async -> Error? {
        do { _ = try await operation(); XCTFail("Expected closed original boundary"); return nil } catch { return error }
    }
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<2_000 { if condition() { return }; try? await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Expected physical operation did not enter")
    }
    private func changed(_ value: Pending) throws -> Pending {
        try .init(checkpoint: value.checkpoint, snapshot: value.snapshot, recordDigest: String(repeating: "f", count: 64))
    }
    private func mutate(_ url: URL, _ update: (inout [String: Any]) -> Void) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]); update(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
    }

    func testOriginalCheckpointRoundTripReconstructsExactCommitWithoutPersistingSecrets() async throws {
        let f = try await fixture(), candidate = f.candidate
        let expectedRequest = try candidate.commitRequest(key: f.record.key)
        XCTAssertEqual(expectedRequest.membershipEpoch, 7); XCTAssertEqual(expectedRequest.installation.expected.ownerEpoch, 3)
        let accepted = try await f.recovery.recordPushCommit(candidate)
        XCTAssertEqual(accepted, candidate); XCTAssertEqual(f.recovery.pushCommitCheckpoint, candidate)
        let bytes = try Data(contentsOf: f.childURL), raw = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(raw.contains(f.record.key)); XCTAssertFalse(raw.contains("idToken")); XCTAssertFalse(raw.contains("nonce"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "scope", "checkpoint", "snapshot", "recordDigest"])
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root))
        try await restarted.bootstrap()
        XCTAssertEqual(restarted.pushCommitCheckpoint, candidate); XCTAssertEqual(restarted.deletionCheckpoint, f.ledger)
        XCTAssertFalse(restarted.admission.isAllowed)
        XCTAssertEqual(try XCTUnwrap(restarted.pushCommitCheckpoint).commitRequest(key: f.record.key), expectedRequest)
    }
    func testDigestUsesVersionedCanonicalWholeRecordIncludingKeyAndAcknowledgedBinding() async throws {
        let f = try await fixture(), original = try Pending.recordDigest(for: f.record)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .millisecondsSince1970
        let expected = SHA256.hash(data: Data("apropos-push-installation-record-v1\n".utf8) + (try encoder.encode(f.record)))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(original, expected)
        var values: [PushInstallationRecord] = []
        var modified = f.record; modified.key = String(repeating: "x", count: 43); values.append(modified)
        modified = f.record; modified.intentHash = String(repeating: "b", count: 64); values.append(modified)
        modified = f.record; modified.revisionStartedAt = Date(timeIntervalSince1970: 101); values.append(modified)
        modified = f.record; modified.acknowledgedBinding = nil; values.append(modified)
        modified = f.record
        let ack = try XCTUnwrap(modified.acknowledgedBinding)
        modified.acknowledgedBinding = .init(schemaVersion: 1, installationId: ack.installationId, appId: ack.appId,
            ownerUID: "reader-B", ownerEpoch: ack.ownerEpoch + 2, revision: ack.revision + 2, clientRevision: ack.clientRevision, status: .active)
        values.append(modified)
        for value in values { XCTAssertNotEqual(try Pending.recordDigest(for: value), original) }
        modified = f.record; modified.revision = -1; XCTAssertThrowsError(try Pending.recordDigest(for: modified))
    }
    func testConstructorRequiresActualLedgerOriginalOwnerAndValidFingerprint() async throws {
        let f = try await fixture()
        XCTAssertThrowsError(try Pending(checkpoint: f.parent, snapshot: f.candidate.snapshot, recordDigest: f.candidate.recordDigest))
        XCTAssertThrowsError(try Pending(checkpoint: f.ledger, snapshot: f.candidate.snapshot, recordDigest: "not-a-digest"))
        let s = f.candidate.snapshot
        let other = try Contract.PushSnapshot(requestId: s.requestId, installationId: s.installationId, appId: s.appId,
            ownerUID: "reader-B", ownerEpoch: s.ownerEpoch, revision: s.revision, clientRevision: s.clientRevision, stateDigest: s.stateDigest)
        XCTAssertThrowsError(try Pending(checkpoint: f.ledger, snapshot: other, recordDigest: f.candidate.recordDigest))
        XCTAssertThrowsError(try f.candidate.commitRequest(key: "missing"))
    }
    func testExactRetryNeverRewritesAndDifferentCandidateCannotReplaceOriginal() async throws {
        let f = try await fixture(); _ = try await f.recovery.recordPushCommit(f.candidate)
        let bytes = try Data(contentsOf: f.childURL)
        _ = try await f.recovery.recordPushCommit(f.candidate)
        _ = try await save(f.candidate, store: Store(rootDirectory: f.root))
        XCTAssertEqual(f.disk.count, 1); XCTAssertEqual(try Data(contentsOf: f.childURL), bytes)
        _ = await failure { try await save(changed(f.candidate), expected: f.candidate, store: f.store) }
        _ = await failure { try await f.recovery.recordPushCommit(changed(f.candidate)) }
        XCTAssertEqual(try Data(contentsOf: f.childURL), bytes)
    }
    func testParentReconciliationKeepsLedgerAndPendingCommitExactly() async throws {
        let f = try await fixture(); _ = try await f.recovery.recordPushCommit(f.candidate)
        let bytes = try Data(contentsOf: f.childURL), parentBytes = try Data(contentsOf: f.ledgerURL)
        let reconciled = try await f.recovery.recordDeletion(request: f.parent.request, phase: .parent, configurationDigest: f.parent.configurationDigest)
        XCTAssertEqual(reconciled, f.ledger); XCTAssertEqual(f.recovery.pushCommitCheckpoint, f.candidate)
        XCTAssertEqual(try Data(contentsOf: f.childURL), bytes); XCTAssertEqual(try Data(contentsOf: f.ledgerURL), parentBytes)
    }
    func testDroppedOrFalseAcknowledgedFirstWritePinsSameCandidateForExplicitRepair() async throws {
        for mode in [Disk.Mode.fail, .falseACK] {
            let f = try await fixture(); f.disk.configure(mode)
            let error = await failure { try await f.recovery.recordPushCommit(f.candidate) }
            XCTAssertEqual(error as? Store.Failure, .unconfirmedPushCommit)
            XCTAssertNil(f.recovery.pushCommitCheckpoint); XCTAssertFalse(f.recovery.admission.isAllowed)
            XCTAssertEqual(f.recovery.status, .sealed(f.ledger.marker))
            _ = await failure { try await f.recovery.recordPushCommit(changed(f.candidate)) }
            XCTAssertEqual(f.disk.count, 1)
            f.disk.configure(.commit)
            let accepted = try await f.recovery.recordPushCommit(f.candidate)
            XCTAssertEqual(accepted, f.candidate); XCTAssertEqual(f.disk.count, 2)
        }
    }
    func testWriteThenThrownCallbackRequiresActualReadbackAndExactRetryDoesNotWrite() async throws {
        let f = try await fixture(); f.disk.configure(.commitThenThrow)
        let result = try await f.recovery.recordPushCommit(f.candidate)
        XCTAssertEqual(result, f.candidate); XCTAssertEqual(f.disk.count, 1)
        _ = try await f.recovery.recordPushCommit(f.candidate); XCTAssertEqual(f.disk.count, 1)
    }
    func testSuccessfulPhysicalWriteWithFailedReadbackCanBeRecoveredButNotReplaced() async throws {
        let f = try await fixture(); f.disk.configure(.failReadback)
        let error = await failure { try await f.recovery.recordPushCommit(f.candidate) }
        XCTAssertEqual(error as? Store.Failure, .unconfirmedPushCommit); XCTAssertNil(f.recovery.pushCommitCheckpoint)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.childURL.path))
        _ = await failure { try await f.recovery.recordPushCommit(changed(f.candidate)) }
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root)); try await restarted.bootstrap()
        XCTAssertEqual(restarted.pushCommitCheckpoint, f.candidate)
        f.disk.configure(.commit)
        _ = try await f.recovery.recordPushCommit(f.candidate); XCTAssertEqual(f.disk.count, 1)
    }
    func testParentCorruptionDuringFailedReadbackInvalidatesSealInsteadOfPermittingRepair() async throws {
        let f = try await fixture(); f.disk.configure(.changeParent)
        let error = await failure { try await f.recovery.recordPushCommit(f.candidate) }
        XCTAssertEqual(error as? Store.Failure, .invalidCheckpoint)
        XCTAssertEqual(f.recovery.status, .unavailable); XCTAssertFalse(f.recovery.hasVerifiedSeal(binding: f.ledger.marker.binding))
        XCTAssertFalse(f.recovery.admission.isAllowed); XCTAssertNil(f.recovery.pushCommitCheckpoint)
    }
    func testCancellationBeforeEntryHasNoWriteAndEnteredCancellationWaitsForPhysicalCompletion() async throws {
        let f = try await fixture()
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await f.recovery.recordPushCommit(f.candidate) }
        _ = await failure { try await cancelled.value }; XCTAssertEqual(f.disk.count, 0)
        f.disk.configure(.commit, hold: true)
        let task = Task { try await f.recovery.recordPushCommit(f.candidate) }
        await eventually { f.disk.isHeld }; task.cancel()
        XCTAssertTrue(f.recovery.isBusy); XCTAssertFalse(f.recovery.admission.isAllowed)
        let busy = await failure { try await f.recovery.recordPushCommit(f.candidate) }
        guard case .busy? = busy as? ReaderTransitionRecovery.Failure else { f.disk.release(); XCTFail("Physical ownership lost"); return }
        f.disk.release(); _ = await failure { try await task.value }
        XCTAssertFalse(f.recovery.isBusy); XCTAssertEqual(f.recovery.pushCommitCheckpoint, f.candidate)
        XCTAssertEqual(f.recovery.status, .sealed(f.ledger.marker))
        let resumed = try await read(Store(rootDirectory: f.root)); XCTAssertEqual(resumed.pushCommit, f.candidate)
    }
    func testObservedCheckpointCannotDisappearOrChangeOnResumption() async throws {
        for remove in [false, true] {
            let f = try await fixture(); _ = try await f.recovery.recordPushCommit(f.candidate)
            if remove { try FileManager.default.removeItem(at: f.childURL) }
            else { try mutate(f.childURL) { $0["recordDigest"] = String(repeating: "f", count: 64) } }
            let error = await failure { try await f.recovery.readResumption() }
            XCTAssertEqual(error as? Store.Failure, remove ? .missingPushCheckpoint : .conflictingPushCheckpoint)
            XCTAssertEqual(f.recovery.pushCommitCheckpoint, f.candidate); XCTAssertEqual(f.recovery.status, .unavailable)
            XCTAssertFalse(f.recovery.admission.isAllowed)
        }
    }
    func testMissingPreviouslyConfirmedChildCannotBeRecreatedByExpectedSave() async throws {
        let f = try await fixture(); _ = try await f.recovery.recordPushCommit(f.candidate)
        try FileManager.default.removeItem(at: f.childURL)
        let error = await failure { try await f.recovery.recordPushCommit(f.candidate) }
        XCTAssertEqual(error as? Store.Failure, .missingPushCheckpoint); XCTAssertEqual(f.disk.count, 1)
        XCTAssertEqual(f.recovery.status, .unavailable)
    }
    func testOrphanAndRegressedOriginalRecordsFailEveryReadSealAndCheckpointPath() async throws {
        for kind in 0..<3 {
            let f = try await fixture(); _ = try await f.recovery.recordPushCommit(f.candidate)
            if kind == 0 { try FileManager.default.removeItem(at: f.markerURL) }
            else if kind == 1 { try FileManager.default.removeItem(at: f.ledgerURL) }
            else { try mutate(f.ledgerURL) { $0["phase"] = "parent" } }
            let store = Store(rootDirectory: f.root)
            _ = await failure { try await read(store) }
            _ = await failure { try await withCheckedThrowingContinuation { (c: CheckedContinuation<Store.Marker, Error>) in store.seal(f.ledger.marker) { c.resume(with: $0) } } }
            _ = await failure { try await withCheckedThrowingContinuation { (c: CheckedContinuation<Store.DeletionCheckpoint, Error>) in
                store.saveDeletionCheckpoint(f.ledger, expected: f.ledger) { c.resume(with: $0) }
            } }
            let restarted = ReaderTransitionRecovery(store: store); _ = await failure { try await restarted.bootstrap() }
            XCTAssertEqual(restarted.status, .unavailable); XCTAssertFalse(restarted.admission.isAllowed)
        }
    }
    func testUnknownDuplicateNoncanonicalAndChangedSnapshotFieldsFailClosed() async throws {
        for kind in 0..<5 {
            let f = try await fixture(); _ = try await f.recovery.recordPushCommit(f.candidate)
            switch kind {
            case 0: try mutate(f.childURL) { $0["key"] = "private" }
            case 1: try mutate(f.childURL) { var s = $0["snapshot"] as! [String: Any]; s["ownerUID"] = "reader-B"; $0["snapshot"] = s }
            case 2: try mutate(f.childURL) { var s = $0["snapshot"] as! [String: Any]; s["revision"] = Contract.maximumSafeInteger; $0["snapshot"] = s }
            case 3:
                let raw = try String(contentsOf: f.childURL, encoding: .utf8)
                try raw.replacingOccurrences(of: "\"recordDigest\":", with: "\"recordDigest\":\"wrong\",\"recordDigest\":").write(to: f.childURL, atomically: true, encoding: .utf8)
            default:
                var raw = try Data(contentsOf: f.childURL); raw.append(32); try raw.write(to: f.childURL)
            }
            let error = await failure { try await read(Store(rootDirectory: f.root)) }
            XCTAssertEqual(error as? Store.Failure, .invalidPushCheckpoint)
        }
    }
    func testSidecarSizeAndFileTypeAreBoundedWithoutFollowingSymlinks() async throws {
        for kind in 0..<3 {
            let f = try await fixture()
            if kind == 0 { try Data(repeating: 65, count: Store.maximumPushCommitBytes + 1).write(to: f.childURL) }
            else if kind == 1 { try FileManager.default.createSymbolicLink(at: f.childURL, withDestinationURL: f.markerURL) }
            else { try FileManager.default.createDirectory(at: f.childURL, withIntermediateDirectories: false) }
            let error = await failure { try await read(Store(rootDirectory: f.root)) }
            XCTAssertEqual(error as? Store.Failure, kind == 0 ? .limitExceeded : .readFailed)
        }
    }
    func testTwoStoreInstancesSerializeFirstSaveAndCannotReplaceWinningCandidate() async throws {
        let f = try await fixture(), disk = f.disk
        let other = Store(rootDirectory: f.root, replace: { try disk.replace($0, $1) })
        let next = try changed(f.candidate)
        let first = Task { () -> Result<Pending, Error> in
            do { return .success(try await save(f.candidate, store: f.store)) } catch { return .failure(error) }
        }
        let second = Task { () -> Result<Pending, Error> in
            do { return .success(try await save(next, store: other)) } catch { return .failure(error) }
        }
        let results = [await first.value, await second.value]
        XCTAssertEqual(results.filter { if case .success = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(f.disk.count, 1)
        let resumed = try await read(Store(rootDirectory: f.root))
        XCTAssertTrue(resumed.pushCommit == f.candidate || resumed.pushCommit == next)
    }
    func testPendingReadOnOtherStoreCannotOvertakeHeldPhysicalPushWrite() async throws {
        let f = try await fixture(); f.disk.configure(.commit, hold: true)
        let writing = Task { try await f.recovery.recordPushCommit(f.candidate) }
        await eventually { f.disk.isHeld }
        var readFinished = false
        let reading = Task { let result = try await read(Store(rootDirectory: f.root)); readFinished = true; return result }
        await Task.yield(); XCTAssertFalse(readFinished)
        XCTAssertTrue(f.recovery.isBusy)
        f.disk.release(); _ = try await writing.value
        let result = try await reading.value; XCTAssertEqual(result.pushCommit, f.candidate)
    }
    func testPushJobsShareExistingBoundedPendingQueueWithoutEvictingAcceptedWork() async throws {
        let f = try await fixture(); f.disk.configure(.commit, hold: true)
        let writing = Task { try await f.recovery.recordPushCommit(f.candidate) }
        await eventually { f.disk.isHeld }
        let completed = expectation(description: "All accepted original push jobs finish")
        completed.expectedFulfillmentCount = Store.maximumPendingJobs
        for _ in 0..<Store.maximumPendingJobs {
            f.store.savePushCommitCheckpoint(f.candidate, expected: nil) { result in
                switch result {
                case .success(let value): XCTAssertEqual(value, f.candidate)
                case .failure(let error): XCTFail("Accepted queue operation failed: \(error)")
                }
                completed.fulfill()
            }
        }
        var overflow: Error?
        f.store.savePushCommitCheckpoint(f.candidate, expected: nil) { if case .failure(let error) = $0 { overflow = error } }
        XCTAssertEqual(overflow as? Store.Failure, .limitExceeded)
        f.disk.release(); _ = try await writing.value
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(result, .completed); XCTAssertEqual(f.disk.count, 1)
    }
    func testLogicalReconstructionAfterNeverPersistedWriteCannotInventLostProcessFingerprint() async throws {
        let f = try await fixture(); f.disk.configure(.falseACK)
        _ = await failure { try await f.recovery.recordPushCommit(f.candidate) }
        _ = await failure { try await f.recovery.readResumption() }
        XCTAssertEqual(f.recovery.status, .unavailable)
        let restarted = ReaderTransitionRecovery(store: Store(rootDirectory: f.root)); try await restarted.bootstrap()
        XCTAssertNil(restarted.pushCommitCheckpoint); XCTAssertEqual(restarted.deletionCheckpoint, f.ledger)
        XCTAssertFalse(restarted.admission.isAllowed) // Absence still cannot authorize dispatch or a replacement preparation.
    }
}
