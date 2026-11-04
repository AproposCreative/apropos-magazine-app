import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderIntroductionLocalCleanupTests: XCTestCase {
    @MainActor private final class Memory {
        var source: Data?, metadata: Data?, guest = Data("independent guest interests".utf8)
        var sourceReads = 0, sourceWrites = 0, metadataReads = 0, metadataWrites = 0
        var onSourceRead: (() -> Void)?, onSourceWrite: (() -> Void)?
        var onMetadataRead: (() -> Void)?, onMetadataWrite: (() -> Void)?
        var failSourceReadback = false, failMetadataReadbackAt: Int?, dropMetadataWriteAt: Int?
        var nextSourceReadFails = false, nextMetadataReadFails = false
        var storage: ReaderIntroductionStorage {
            .init(read: { [self] in
                sourceReads += 1; onSourceRead?()
                if nextSourceReadFails { nextSourceReadFails = false; throw CocoaError(.fileReadUnknown) }
                return source
            }, write: { [self] bytes in
                sourceWrites += 1; onSourceWrite?(); source = bytes
                if failSourceReadback { nextSourceReadFails = true; failSourceReadback = false }
            }, cleanup: .init(read: { [self] in
                metadataReads += 1; onMetadataRead?()
                if nextMetadataReadFails { nextMetadataReadFails = false; throw CocoaError(.fileReadUnknown) }
                return metadata
            }, write: { [self] bytes in
                metadataWrites += 1; onMetadataWrite?()
                if dropMetadataWriteAt != metadataWrites { metadata = bytes }
                if failMetadataReadbackAt == metadataWrites { nextMetadataReadFails = true }
            }))
        }
        func seed(_ uid: String? = "reader-a", completed: Bool = true) {
            let canonical = CanonicalSessionState()
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: "test@example.invalid", isEmailVerified: true) })
            let model = ReaderIntroductionModel(storage: storage)
            XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
            XCTAssertTrue(model.start()); XCTAssertTrue(model.setSelectedTopicIDs(["culture", "music"]))
            if completed { XCTAssertTrue(model.complete()); XCTAssertTrue(model.replay()) }
            sourceReads = 0; sourceWrites = 0
        }
    }
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("intro-cleanup-" + UUID().uuidString)
        let memory = Memory()
        lazy var recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        lazy var model = ReaderIntroductionModel(storage: memory.storage, recovery: recovery)
        var checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint!
        func close() async throws {
            try await recovery.bootstrap()
            _ = try await recovery.seal(binding: .init(ownerUID: "reader-a", epoch: 7))
            let request = try ReaderAccountDeletionContract.Request(expectedUID: "reader-a", membershipEpoch: 7)
            _ = try await recovery.recordDeletion(request: request, phase: .parent, configurationDigest: String(repeating: "a", count: 64))
            checkpoint = try await recovery.recordDeletion(request: request, phase: .ledger, configurationDigest: String(repeating: "a", count: 64))
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    private func permit() -> ReaderLegacyWriteAdmission { .init(isAllowed: true) }
    private func prepare(_ f: Fixture) async throws -> ReaderIntroductionModel.CleanupLease {
        try await f.model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
    }
    private func commit(_ f: Fixture, _ lease: ReaderIntroductionModel.CleanupLease) async throws -> ReaderIntroductionModel.CleanupReceipt {
        try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
    }
    private func failure<Value>(_ work: () async throws -> Value, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await work(); XCTFail("Unexpected success", file: file, line: line) } catch { }
    }
    private func fields(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testBeforeSeparateCleanupRetainsCompletedDraftAndGuestKey() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); let source = f.memory.source, guest = f.memory.guest
        try await f.close()
        XCTAssertFalse(f.model.toggleTopic("film")); XCTAssertFalse(f.model.replay()); XCTAssertFalse(f.model.retry())
        XCTAssertEqual(f.memory.source, source); XCTAssertEqual(f.memory.guest, guest)
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertNil(f.memory.metadata)
    }

    func testReadOnlyPrepareUsesActualCodecOwnerAndNoGuestOrSidecarWrite() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let source = f.memory.source, guest = f.memory.guest, lease = try await prepare(f)
        XCTAssertEqual(lease.owner, try fields(source)["draftOwner"] as? String)
        XCTAssertTrue(lease.owner.hasPrefix("account:")); XCTAssertEqual(lease.originalEntryCount, 2)
        XCTAssertNotEqual(lease.owner, PodcastProgressContext.confirmed(userID: "reader-a").namespace?.recordBinding)
        XCTAssertEqual(f.memory.source, source); XCTAssertEqual(f.memory.guest, guest)
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 0)
    }

    func testConfirmedDraftCleanupPreservesCompletionAndNeverReplaysOnboarding() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let guest = f.memory.guest, lease = try await prepare(f), receipt = try await commit(f, lease)
        XCTAssertTrue(receipt.isComplete); XCTAssertTrue(receipt.belongs(to: f.checkpoint))
        let record = try fields(f.memory.source)
        XCTAssertEqual(record["completed"] as? Bool, true); XCTAssertEqual(record["schemaVersion"] as? Int, 3)
        XCTAssertEqual(record["replaying"] as? Bool, false); XCTAssertEqual(record["step"] as? String, "welcome")
        XCTAssertEqual(record["selectedTopicIDs"] as? [String], []); XCTAssertNil(record["draftOwner"])
        XCTAssertEqual(f.memory.guest, guest); XCTAssertEqual(f.memory.sourceWrites, 1)
        let canonical = CanonicalSessionState(); canonical.adopt(nil)
        let normal = ReaderIntroductionModel(storage: f.memory.storage)
        XCTAssertTrue(normal.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)); XCTAssertTrue(normal.start())
        XCTAssertTrue(normal.isCompleted); XCTAssertFalse(normal.isPresented)
        XCTAssertEqual(f.memory.metadataWrites, 2)
    }

    func testForeignGuestOwnerlessAndMissingSourcesRemainByteIdentical() async throws {
        for variant in 0..<4 {
            let f = Fixture(); defer { f.cleanup() }
            if variant < 2 { f.memory.seed(variant == 0 ? "reader-b" : nil) }
            if variant == 2 {
                f.memory.seed()
                var record = try fields(f.memory.source); record.removeValue(forKey: "draftOwner")
                f.memory.source = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            }
            try await f.close()
            let source = f.memory.source, guest = f.memory.guest, lease = try await prepare(f)
            XCTAssertEqual(lease.originalEntryCount, 0)
            let receipt = try await commit(f, lease)
            XCTAssertTrue(receipt.isComplete); XCTAssertEqual(f.memory.source, source); XCTAssertEqual(f.memory.guest, guest)
            XCTAssertEqual(f.memory.sourceWrites, 0)
        }
    }

    func testReplacementAfterPrepareNeverGetsOverwritten() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f)
        let replacement = Memory(); replacement.seed("reader-b"); f.memory.source = replacement.source
        await failure { try await commit(f, lease) }
        XCTAssertEqual(f.memory.source, replacement.source); XCTAssertEqual(f.memory.sourceWrites, 0)
        XCTAssertEqual(f.memory.metadataWrites, 0)
    }

    func testUnknownRepeatedAndMalformedSourceOrSidecarFailClosed() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let original = try XCTUnwrap(f.memory.source), text = String(decoding: original, as: UTF8.self)
        for source in [Data("bad".utf8),
                       Data(text.replacingOccurrences(of: "\"schemaVersion\":3", with: "\"schemaVersion\":3,\"unknown\":true").utf8),
                       Data(text.replacingOccurrences(of: "\"schemaVersion\":3", with: "\"schemaVersion\":3,\"schemaVersion\":3").utf8)] {
            f.memory.source = source
            await failure { try await prepare(f) }
            XCTAssertEqual(f.memory.source, source)
        }
        f.memory.source = original; f.memory.metadata = Data("unknown metadata".utf8)
        await failure { try await prepare(f) }
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 0)
    }

    func testPendingSourceAndCompleteReadbackFailuresResumeOnlyOriginalBytes() async throws {
        for failurePoint in 0..<3 {
            let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
            if failurePoint == 0 { f.memory.failMetadataReadbackAt = 1 }
            if failurePoint == 1 { f.memory.failSourceReadback = true }
            if failurePoint == 2 { f.memory.failMetadataReadbackAt = 2 }
            let lease = try await prepare(f)
            await failure { try await commit(f, lease) }
            await failure { try await commit(f, lease) }
            // Logical reconstruction over persisted injected bytes; no process
            // kill, Defaults/fsync or atomic two-key guarantee is asserted.
            let reconstructed = ReaderIntroductionModel(storage: f.memory.storage, recovery: f.recovery)
            XCTAssertFalse(reconstructed.start()); XCTAssertFalse(reconstructed.replay())
            let fresh = try await reconstructed.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
            let receipt = try await reconstructed.commitLocalCleanup(fresh, finalAdmission: permit(), stillCurrent: { true })
            XCTAssertTrue(receipt.isComplete); XCTAssertEqual(f.memory.sourceWrites, 1)
            XCTAssertEqual(try fields(f.memory.source)["completed"] as? Bool, true)
        }
    }

    func testDroppedFirstPendingWriteRetainsOriginalFingerprintInThisModel() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        f.memory.dropMetadataWriteAt = 1
        let lease = try await prepare(f)
        await failure { try await commit(f, lease) }
        let changed = Memory(); changed.seed(); let canonical = CanonicalSessionState()
        canonical.adopt(ReaderAccountSession(uid: "reader-a", email: "test@example.invalid", isEmailVerified: true))
        let model = ReaderIntroductionModel(storage: changed.storage)
        XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)); XCTAssertTrue(model.start())
        XCTAssertTrue(model.setSelectedTopicIDs(["new-topic"]))
        f.memory.source = changed.source
        await failure { try await prepare(f) }
        XCTAssertEqual(f.memory.source, changed.source); XCTAssertEqual(f.memory.sourceWrites, 0)
    }

    func testSidecarSurvivesNormalForeignAndGuestSavesWithoutRetainingRemovedTopics() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f)
        _ = try await commit(f, lease)
        let metadata = try XCTUnwrap(f.memory.metadata)
        let text = String(decoding: metadata, as: UTF8.self)
        XCTAssertFalse(text.contains("culture")); XCTAssertFalse(text.contains("music")); XCTAssertFalse(text.contains("selectedTopicIDs"))
        for uid in [Optional("reader-b"), nil] {
            let canonical = CanonicalSessionState()
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: "test@example.invalid", isEmailVerified: true) })
            let normal = ReaderIntroductionModel(storage: f.memory.storage)
            XCTAssertTrue(normal.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)); XCTAssertTrue(normal.start())
            XCTAssertTrue(normal.setSelectedTopicIDs(["foreign-topic"]))
            XCTAssertEqual(f.memory.metadata, metadata); XCTAssertTrue(normal.isCompleted)
        }
    }

    func testOldLeaseWrongModelAndOriginalRequestFamilyCannotBeReused() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f), other = ReaderIntroductionModel(storage: f.memory.storage, recovery: f.recovery)
        await failure { try await other.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        await failure { try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { false }) }
        await failure { try await commit(f, lease) }
        let changed = try ReaderTransitionRecoveryStore.DeletionCheckpoint(marker: f.checkpoint.marker,
            request: f.checkpoint.request, phase: .ledger, configurationDigest: String(repeating: "b", count: 64))
        await failure { try await f.model.prepareLocalCleanup(checkpoint: changed, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 0)
    }

    func testPureAdmissionRevocationInLastReadPreventsSourceMutation() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f), final = permit()
        var readsAfterPending = 0
        f.memory.onSourceRead = {
            XCTAssertFalse(f.model.isPhysicallyIdle)
            if f.memory.metadataWrites == 1 {
                readsAfterPending += 1
                // Pending write readback, then both source reads in the last
                // prewrite pair check. No Task cancellation is needed.
                if readsAfterPending == 3 { final.setAllowed(false) }
            }
        }
        await failure { try await f.model.commitLocalCleanup(lease, finalAdmission: final, stillCurrent: { true }) }
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 1)
        XCTAssertTrue(f.model.isPhysicallyIdle)
    }

    func testCancellationInsideSourceWriteFinishesReadbackAndLeavesPendingRetry() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f)
        var task: Task<ReaderIntroductionModel.CleanupReceipt, Error>?, readsAtWrite = 0
        f.memory.onSourceWrite = {
            XCTAssertFalse(f.model.isPhysicallyIdle); readsAtWrite = f.memory.sourceReads; task?.cancel()
        }
        task = Task { try await commit(f, lease) }
        await failure { try await task!.value }
        XCTAssertGreaterThan(f.memory.sourceReads, readsAtWrite)
        XCTAssertEqual(try ReaderIntroductionLocalCleanupRecord.decode(f.memory.metadata).records.first?.phase, .pending)
        XCTAssertEqual(try fields(f.memory.source)["completed"] as? Bool, true)
    }

    func testMetadataCallbackChangingSharedSourceIsDetectedBeforeSourceWrite() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f), replacement = Memory(); replacement.seed("reader-b")
        f.memory.onMetadataWrite = { f.memory.source = replacement.source }
        await failure { try await commit(f, lease) }
        XCTAssertEqual(f.memory.source, replacement.source); XCTAssertEqual(f.memory.sourceWrites, 0)
        await failure { try await prepare(f) }
    }

    func testLastPrewritePermissionHookCannotOverwriteForeignReplacement() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f), replacement = Memory(); replacement.seed("reader-b")
        await failure {
            try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: {
                if f.memory.metadataWrites == 1 { f.memory.source = replacement.source }
                return true
            })
        }
        XCTAssertEqual(f.memory.source, replacement.source); XCTAssertEqual(f.memory.sourceWrites, 0)
        XCTAssertEqual(f.memory.metadataWrites, 1)
    }

    func testLastPermissionHookCannotHideSourceOrMetadataReplacement() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(); try await f.close()
        let lease = try await prepare(f)
        await failure {
            try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: {
                if f.memory.metadataWrites == 2 { f.memory.metadata = Data("changed after complete".utf8) }
                return true
            })
        }
        XCTAssertEqual(f.memory.metadata, Data("changed after complete".utf8))
    }

    func testCompletedFlagFalseAndBoundedRetainedMetadataAreNotChangedImplicitly() async throws {
        let f = Fixture(); defer { f.cleanup() }; f.memory.seed(completed: false); try await f.close()
        let lease = try await prepare(f)
        _ = try await commit(f, lease)
        XCTAssertEqual(try fields(f.memory.source)["completed"] as? Bool, false)
        var envelope = ReaderIntroductionLocalCleanupRecord.Envelope()
        for index in 0..<ReaderIntroductionLocalCleanupRecord.maximumRecords {
            let uid = "other-\(index)"
            let checkpoint = try ReaderTransitionRecoveryStore.DeletionCheckpoint(
                marker: .init(binding: .init(ownerUID: uid, epoch: 7), transitionID: UUID()),
                request: .init(expectedUID: uid, membershipEpoch: 7), phase: .ledger,
                configurationDigest: String(repeating: "a", count: 64))
            var record = try ReaderIntroductionLocalCleanupRecord(checkpoint: checkpoint, source: nil, target: nil,
                ownedDraft: false, originalEntryCount: 0, completed: nil)
            record.phase = .complete; envelope.records.append(record)
        }
        let metadata = try ReaderIntroductionLocalCleanupRecord.encode(envelope)
        let other = Fixture(); defer { other.cleanup() }; other.memory.seed(); try await other.close()
        other.memory.metadata = metadata
        await failure { try await prepare(other) }
        XCTAssertEqual(other.memory.metadata, metadata); XCTAssertEqual(other.memory.metadataWrites, 0)
    }

    func testNormalStartReadUsesSamePhysicalGuardAndMissingAdapterIsUnavailable() async throws {
        let memory = Memory(), model = ReaderIntroductionModel(storage: memory.storage), canonical = CanonicalSessionState()
        canonical.adopt(nil)
        XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
        memory.onSourceRead = { XCTAssertFalse(model.isPhysicallyIdle); XCTAssertFalse(model.start()) }
        XCTAssertTrue(model.start()); XCTAssertTrue(model.isPhysicallyIdle)
        let f = Fixture(); defer { f.cleanup() }; try await f.close()
        let unsupported = ReaderIntroductionModel(storage: .init(read: { XCTFail("Unsupported cleanup read"); return nil },
                                                                 write: { _ in XCTFail("Unsupported cleanup write") }), recovery: f.recovery)
        await failure { try await unsupported.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true }) }
    }
}
