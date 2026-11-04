import XCTest
@testable import Apropos

@MainActor
final class ReadingHistoryLocalCleanupTests: XCTestCase {
    @MainActor private final class Memory {
        var values: [String: Data] = [:]
        var metadata: Data?
        var normalReads = 0, normalWrites = 0, sourceReads = 0, sourceWrites = 0, metadataReads = 0, metadataWrites = 0
        var onRead: (() -> Void)?, onWrite: (() -> Void)?, onMetadataRead: (() -> Void)?, onMetadataWrite: (() -> Void)?
        var failSourceReadback = false, nextSourceReadFails = false, nextMetadataReadFails = false
        var failMetadataReadbackAt: Int?, dropMetadataWriteAt: Int?
        var cleanup: ReadingHistoryModel.Storage.Cleanup {
            .init(readSource: { [self] namespace in
                sourceReads += 1; onRead?()
                if nextSourceReadFails { nextSourceReadFails = false; throw CocoaError(.fileReadUnknown) }
                return values[namespace.storageKey]
            }, writeSource: { [self] namespace, bytes in
                sourceWrites += 1; onWrite?(); values[namespace.storageKey] = bytes
                if failSourceReadback { failSourceReadback = false; nextSourceReadFails = true }
            }, readMetadata: { [self] in
                metadataReads += 1; onMetadataRead?()
                if nextMetadataReadFails { nextMetadataReadFails = false; throw CocoaError(.fileReadUnknown) }
                return metadata
            }, writeMetadata: { [self] bytes in
                metadataWrites += 1; onMetadataWrite?()
                if dropMetadataWriteAt != metadataWrites { metadata = bytes }
                if failMetadataReadbackAt == metadataWrites { nextMetadataReadFails = true }
            })
        }
        var storage: ReadingHistoryModel.Storage {
            .init(read: { [self] namespace in normalReads += 1; return values[namespace.storageKey] },
                  write: { [self] namespace, bytes in normalWrites += 1; values[namespace.storageKey] = bytes },
                  cleanup: cleanup)
        }
        func seed() throws {
            for uid in [Optional("reader-a"), Optional("reader-b"), nil] {
                let namespace = ReadingHistoryContext.confirmed(userID: uid).namespace!
                values[namespace.storageKey] = try ReadingHistoryRecordCodec.encode(.init(entries: [
                    .init(articleID: "private-read-article", read: true, progress: 0.37),
                    .init(articleID: "private-progress-article", read: false, progress: 0.58)
                ]), namespace: namespace)
            }
            values["readArticleIds"] = Data("unowned legacy read IDs".utf8)
            values["readingProgress"] = Data("unowned legacy progress".utf8)
        }
    }
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-cleanup-" + UUID().uuidString)
        let memory = Memory()
        let namespace = ReadingHistoryContext.confirmed(userID: "reader-a").namespace!
        lazy var recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        lazy var model = ReadingHistoryModel(storage: memory.storage, schedule: { _, _ in {} }, recovery: recovery)
        var checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint!
        func close(bootstrap: Bool = true) async throws {
            if bootstrap { try await recovery.bootstrap() }
            _ = try await recovery.seal(binding: .init(ownerUID: "reader-a", epoch: 7))
            let request = try ReaderAccountDeletionContract.Request(expectedUID: "reader-a", membershipEpoch: 7)
            _ = try await recovery.recordDeletion(request: request, phase: .parent, configurationDigest: String(repeating: "a", count: 64))
            checkpoint = try await recovery.recordDeletion(request: request, phase: .ledger, configurationDigest: String(repeating: "a", count: 64))
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    private func permit() -> ReaderLegacyWriteAdmission { .init(isAllowed: true) }
    private func prepare(_ f: Fixture) async throws -> ReadingHistoryModel.CleanupLease {
        try await f.model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
    }
    private func commit(_ f: Fixture, _ lease: ReadingHistoryModel.CleanupLease) async throws -> ReadingHistoryModel.CleanupReceipt {
        try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
    }
    private func failure<Value>(_ work: () async throws -> Value, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await work(); XCTFail("Unexpected success", file: file, line: line) } catch { }
    }
    private func changedSource(_ f: Fixture) throws -> Data {
        try ReadingHistoryRecordCodec.encode(.init(entries: [.init(articleID: "new-private-article", read: true, progress: 0.9)]), namespace: f.namespace)
    }

    func testReadOnlyPrepareUsesExactHistoryNamespaceAndNeverNormalKVSWriter() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        let original = f.memory.values, lease = try await prepare(f)
        XCTAssertEqual(lease.owner, f.namespace.recordBinding); XCTAssertEqual(lease.originalEntryCount, 2)
        XCTAssertNotEqual(lease.owner, PodcastProgressContext.confirmed(userID: "reader-a").namespace?.recordBinding)
        XCTAssertNotEqual(lease.owner, ReaderIntroductionLocalCleanupRecord.owner("reader-a"))
        XCTAssertEqual(f.memory.values, original); XCTAssertNil(f.memory.metadata)
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.normalReads, 0); XCTAssertEqual(f.memory.normalWrites, 0)
    }

    func testExplicitConfirmationClearsOnlyOriginalHistoryAndNeverClaimsCloudCompletion() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        var expected = f.memory.values
        expected[f.namespace.storageKey] = try ReadingHistoryRecordCodec.encode(.empty, namespace: f.namespace)
        let lease = try await prepare(f), receipt = try await commit(f, lease)
        XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
        XCTAssertTrue(receipt.belongs(to: f.checkpoint)); XCTAssertEqual(receipt.originalEntryCount, 2)
        XCTAssertEqual(f.memory.values, expected); XCTAssertEqual(f.memory.sourceWrites, 1)
        XCTAssertEqual(f.memory.metadataWrites, 2); XCTAssertEqual(f.memory.normalWrites, 0)
        let evidence = String(decoding: try XCTUnwrap(f.memory.metadata), as: UTF8.self)
        XCTAssertFalse(evidence.contains("private-read-article")); XCTAssertFalse(evidence.contains("private-progress-article"))
        XCTAssertFalse(evidence.contains("0.37")); XCTAssertFalse(evidence.contains("entries"))
        XCTAssertFalse(f.recovery.admission.isAllowed); XCTAssertNil(f.model.beginArticle(articleID: "new"))
    }

    func testMissingSourceRemainsAbsentWithOtherAndLegacyBytesUntouched() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); f.memory.values.removeValue(forKey: f.namespace.storageKey)
        try await f.close(); let original = f.memory.values, lease = try await prepare(f)
        let receipt = try await commit(f, lease)
        XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
        XCTAssertEqual(receipt.originalEntryCount, 0); XCTAssertEqual(f.memory.values, original)
        XCTAssertEqual(f.memory.sourceWrites, 0)
    }

    func testSourceOrEvidenceReplacementRejectsPreparedLeaseWithoutMutation() async throws {
        for changeEvidence in [false, true] {
            let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); let lease = try await prepare(f)
            if changeEvidence { f.memory.metadata = Data("external evidence replacement".utf8) }
            else { f.memory.values[f.namespace.storageKey] = try changedSource(f) }
            let values = f.memory.values, metadata = f.memory.metadata
            await failure { try await commit(f, lease) }
            XCTAssertEqual(f.memory.values, values); XCTAssertEqual(f.memory.metadata, metadata)
            XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 0)
        }
    }

    func testUnknownRepeatedMalformedAndWrongOwnerSourceFailClosed() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        let original = try XCTUnwrap(f.memory.values[f.namespace.storageKey]), text = String(decoding: original, as: UTF8.self)
        let b = ReadingHistoryContext.confirmed(userID: "reader-b").namespace!
        for bytes in [Data("bad".utf8), Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"unknown\":true").utf8),
                      Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1").utf8),
                      try XCTUnwrap(f.memory.values[b.storageKey])] {
            f.memory.values[f.namespace.storageKey] = bytes
            await failure { try await prepare(f) }
            XCTAssertEqual(f.memory.values[f.namespace.storageKey], bytes)
        }
        f.memory.values[f.namespace.storageKey] = original; f.memory.metadata = Data("bad".utf8)
        await failure { try await prepare(f) }
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 0)
    }

    func testPendingSourceAndCompleteReadbackFailuresRequireFreshOriginalConfirmation() async throws {
        for failurePoint in 0..<3 {
            let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
            if failurePoint == 0 { f.memory.failMetadataReadbackAt = 1 }
            if failurePoint == 1 { f.memory.failSourceReadback = true }
            if failurePoint == 2 { f.memory.failMetadataReadbackAt = 2 }
            let lease = try await prepare(f)
            await failure { try await commit(f, lease) }; await failure { try await commit(f, lease) }
            // Logical reconstruction over injected bytes and an existing closed
            // recovery seal, not a process kill, KVS or cloud-purge assertion.
            let reconstructed = ReadingHistoryModel(storage: f.memory.storage, schedule: { _, _ in {} }, recovery: f.recovery)
            reconstructed.changeContext(to: .confirmed(userID: "reader-a"))
            XCTAssertNil(reconstructed.beginArticle(articleID: "old")); XCTAssertEqual(f.memory.normalReads, 0)
            let fresh = try await reconstructed.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
            let receipt = try await reconstructed.commitLocalCleanup(fresh, finalAdmission: permit(), stillCurrent: { true })
            XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
            XCTAssertEqual(f.memory.sourceWrites, 1)
        }
    }

    func testDroppedFirstEvidenceWriteCannotAdoptChangedOriginalInSameModel() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        f.memory.dropMetadataWriteAt = 1; let lease = try await prepare(f)
        await failure { try await commit(f, lease) }
        f.memory.values[f.namespace.storageKey] = try changedSource(f); let changed = f.memory.values
        await failure { try await prepare(f) }
        XCTAssertEqual(f.memory.values, changed); XCTAssertEqual(f.memory.sourceWrites, 0)
        XCTAssertNil(f.memory.metadata)
    }

    func testCompleteEvidenceRejectsChangedOriginalAfterLogicalReconstruction() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        let lease = try await prepare(f)
        _ = try await commit(f, lease)
        f.memory.values[f.namespace.storageKey] = try changedSource(f)
        let fresh = ReadingHistoryModel(storage: f.memory.storage, schedule: { _, _ in {} }, recovery: f.recovery)
        await failure { try await fresh.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(f.memory.sourceWrites, 1)
    }

    func testOldLeaseWrongModelAndOriginalCheckpointCannotBeReused() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); let lease = try await prepare(f)
        let other = ReadingHistoryModel(storage: f.memory.storage, schedule: { _, _ in {} }, recovery: f.recovery)
        await failure { try await other.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        await failure { try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { false }) }
        await failure { try await commit(f, lease) }
        let changed = try ReaderTransitionRecoveryStore.DeletionCheckpoint(marker: f.checkpoint.marker, request: f.checkpoint.request,
            phase: .ledger, configurationDigest: String(repeating: "b", count: 64))
        await failure { try await f.model.prepareLocalCleanup(checkpoint: changed, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 0)
    }

    func testPureRevocationInLastSourceReadPreventsWriteWithoutTaskCancellation() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        let lease = try await prepare(f), admission = permit(); var readsAfterPending = 0
        f.memory.onRead = {
            XCTAssertFalse(f.model.isPhysicallyIdle)
            if f.memory.metadataWrites == 1 {
                readsAfterPending += 1
                if readsAfterPending == 3 { admission.setAllowed(false) }
            }
        }
        await failure { try await f.model.commitLocalCleanup(lease, finalAdmission: admission, stillCurrent: { true }) }
        XCTAssertEqual(f.memory.sourceWrites, 0); XCTAssertEqual(f.memory.metadataWrites, 1)
        XCTAssertTrue(f.model.isPhysicallyIdle)
    }

    func testCancellationInsideSourceWriteFinishesReadbackAndKeepsPendingEvidence() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); let lease = try await prepare(f)
        var task: Task<ReadingHistoryModel.CleanupReceipt, Error>?, readsAtWrite = 0
        f.memory.onWrite = { XCTAssertFalse(f.model.isPhysicallyIdle); readsAtWrite = f.memory.sourceReads; task?.cancel() }
        task = Task { try await commit(f, lease) }
        await failure { try await task!.value }
        XCTAssertGreaterThan(f.memory.sourceReads, readsAtWrite)
        XCTAssertEqual(try ReadingHistoryLocalCleanupRecord.decode(f.memory.metadata).records.first?.phase, .pending)
        XCTAssertEqual(f.memory.sourceWrites, 1); XCTAssertEqual(f.memory.metadataWrites, 1)
    }

    func testMetadataCallbackReplacingSourceCannotBeOverwritten() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); let lease = try await prepare(f)
        let replacement = try changedSource(f)
        f.memory.onMetadataWrite = { f.memory.values[f.namespace.storageKey] = replacement }
        await failure { try await commit(f, lease) }
        XCTAssertEqual(f.memory.values[f.namespace.storageKey], replacement); XCTAssertEqual(f.memory.sourceWrites, 0)
        await failure { try await prepare(f) }
    }

    func testLastPermissionHooksCannotHideSourceOrFinalMetadataChanges() async throws {
        for changeAtComplete in [false, true] {
            let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); let lease = try await prepare(f)
            let replacement = try changedSource(f)
            await failure {
                try await f.model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: {
                    if changeAtComplete, f.memory.metadataWrites == 2 { f.memory.metadata = Data("changed complete".utf8) }
                    else if !changeAtComplete, f.memory.metadataWrites == 1 { f.memory.values[f.namespace.storageKey] = replacement }
                    return true
                })
            }
            XCTAssertEqual(f.memory.sourceWrites, changeAtComplete ? 1 : 0)
        }
    }

    func testBoundedEvidenceNeverEvictsOtherOwnersOrRetainsArticlePayload() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        var envelope = ReadingHistoryLocalCleanupRecord.Envelope()
        for index in 0..<ReadingHistoryLocalCleanupRecord.maximumRecords {
            let uid = "other-\(index)"
            let checkpoint = try ReaderTransitionRecoveryStore.DeletionCheckpoint(
                marker: .init(binding: .init(ownerUID: uid, epoch: 7), transitionID: UUID()),
                request: .init(expectedUID: uid, membershipEpoch: 7), phase: .ledger, configurationDigest: String(repeating: "a", count: 64))
            var record = try ReadingHistoryLocalCleanupRecord(checkpoint: checkpoint, source: nil, target: nil, originalEntryCount: 0)
            record.phase = .complete; envelope.records.append(record)
        }
        f.memory.metadata = try ReadingHistoryLocalCleanupRecord.encode(envelope); let metadata = f.memory.metadata
        await failure { try await prepare(f) }
        XCTAssertEqual(f.memory.metadata, metadata); XCTAssertEqual(f.memory.metadataWrites, 0); XCTAssertEqual(f.memory.sourceWrites, 0)
    }

    func testMissingCapabilityNeverUsesOrdinarySourceReadWriteOrSynchronize() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); var factory = 0, sync = 0
        let runtime = ReadingHistoryRuntime(disabled: false, transportFactory: {
            factory += 1
            return .init(storage: f.memory.storage, observe: { _ in {} }, synchronize: { sync += 1 })
        }, schedule: { _, _ in {} }, markProfileRead: { _, _ in XCTFail("Profile write") }, recovery: f.recovery)
        let model = try XCTUnwrap(runtime.localCleanupModel())
        XCTAssertTrue(model === runtime.model); XCTAssertFalse(model.isLocalCleanupAvailable)
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "reader-a"); runtime.flushAcceptedEdits()
        await failure { try await model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(factory, 0); XCTAssertEqual(sync, 0); XCTAssertEqual(f.memory.normalReads, 0); XCTAssertEqual(f.memory.normalWrites, 0)
        XCTAssertEqual(f.memory.sourceReads, 0); XCTAssertEqual(f.memory.metadataReads, 0)
    }

    func testColdExplicitCapabilityReturnsSameModelWithoutTransportFactory() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close(); var factory = 0
        let runtime = ReadingHistoryRuntime(disabled: false, transportFactory: {
            factory += 1; return .init(storage: f.memory.storage, observe: { _ in {} }, synchronize: { XCTFail("Synchronize") })
        }, schedule: { _, _ in {} }, markProfileRead: { _, _ in XCTFail("Profile write") }, recovery: f.recovery, cleanupStorage: f.memory.cleanup)
        let model = try XCTUnwrap(runtime.localCleanupModel())
        XCTAssertTrue(model === runtime.model); XCTAssertTrue(model.isLocalCleanupAvailable); XCTAssertEqual(factory, 0)
        let lease = try await model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
        let receipt = try await model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
        XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
        XCTAssertEqual(factory, 0); XCTAssertEqual(f.memory.normalReads, 0); XCTAssertEqual(f.memory.normalWrites, 0)
    }

    func testHotRuntimeOldTimerArticleAndExternalEventsStayRevokedDuringAndAfterCleanup() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.recovery.bootstrap()
        var timers: [@MainActor () -> Void] = [], events: [@MainActor (ReadingHistoryRuntime.ExternalEvent) -> Void] = []
        var factory = 0, sync = 0, profile = 0
        let runtime = ReadingHistoryRuntime(disabled: false, transportFactory: {
            factory += 1; return .init(storage: f.memory.storage, observe: { events.append($0); return {} }, synchronize: { sync += 1 })
        }, schedule: { _, action in timers.append(action); return {} }, markProfileRead: { _, _ in profile += 1 },
            recovery: f.recovery, cleanupStorage: f.memory.cleanup)
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "reader-a")
        let model = try XCTUnwrap(runtime.localCleanupModel()), ticket = try XCTUnwrap(model.beginArticle(articleID: "scheduled"))
        XCTAssertEqual(model.saveProgress(0.6, ticket: ticket), .scheduled)
        try await f.close(bootstrap: false)
        let normalReads = f.memory.normalReads
        let fireOld = {
            for timer in timers { timer() }
            for receive in events { receive(.changed(keys: [f.namespace.storageKey])); receive(.accountChanged) }
            runtime.markRead(ticket); runtime.flushAcceptedEdits(); runtime.changeAccountContext(userID: "reader-b")
            runtime.changeAccountContext(userID: "reader-a")
            XCTAssertEqual(model.saveProgress(0.7, ticket: ticket), .stale)
        }
        f.memory.onRead = { XCTAssertFalse(model.isPhysicallyIdle); fireOld() }
        let lease = try await model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
        let receipt = try await model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
        fireOld()
        XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
        XCTAssertEqual(f.memory.normalReads, normalReads); XCTAssertEqual(f.memory.normalWrites, 0)
        XCTAssertEqual(factory, 1); XCTAssertEqual(sync, 1); XCTAssertEqual(profile, 0)
        XCTAssertFalse(f.recovery.admission.isAllowed)
    }

    func testPreparedNormalTransportNeverGrantsItsCleanupCapabilityImplicitly() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.recovery.bootstrap()
        let runtime = ReadingHistoryRuntime(disabled: false, transportFactory: {
            .init(storage: f.memory.storage, observe: { _ in {} }, synchronize: {})
        }, schedule: { _, _ in {} }, markProfileRead: { _, _ in }, recovery: f.recovery)
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "reader-a")
        try await f.close(bootstrap: false)
        let normalReads = f.memory.normalReads, model = try XCTUnwrap(runtime.localCleanupModel())
        XCTAssertFalse(model.isLocalCleanupAvailable)
        await failure { try await model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(f.memory.normalReads, normalReads); XCTAssertEqual(f.memory.sourceReads, 0)
        XCTAssertEqual(f.memory.normalWrites, 0); XCTAssertEqual(f.memory.sourceWrites, 0)
    }

    func testExplicitOpenLegacyTokenCannotBypassClosedRecoveryDuringLocalCleanup() async throws {
        let f = Fixture(); defer { f.cleanup() }; try f.memory.seed(); try await f.close()
        let legacy = ReaderLegacyWriteAdmission(isAllowed: true)
        let model = ReadingHistoryModel(storage: f.memory.storage, schedule: { _, _ in
            XCTFail("Closed recovery must not schedule a normal write"); return {}
        }, legacyAdmission: legacy, recovery: f.recovery)
        let tryNormalAccess = {
            model.changeContext(to: .confirmed(userID: "reader-a"))
            XCTAssertEqual(model.context, .unresolved)
            XCTAssertNil(model.beginArticle(articleID: "ordinary-read")); XCTAssertNil(model.externalTicket())
            model.retryStorage(); model.flushPending()
        }
        tryNormalAccess()
        f.memory.onRead = { XCTAssertFalse(model.isPhysicallyIdle); tryNormalAccess() }
        let lease = try await model.prepareLocalCleanup(checkpoint: f.checkpoint, finalAdmission: permit(), stillCurrent: { true })
        let receipt = try await model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
        tryNormalAccess()
        XCTAssertTrue(legacy.isAllowed); XCTAssertFalse(f.recovery.admission.isAllowed)
        XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
        XCTAssertEqual(f.memory.normalReads, 0); XCTAssertEqual(f.memory.normalWrites, 0)
        XCTAssertEqual(f.memory.sourceWrites, 1)
    }

    func testNormalStorageReadAndWriteShareCleanupPhysicalBusyFlag() throws {
        let memory = Memory(); try memory.seed()
        var model: ReadingHistoryModel!
        let storage = ReadingHistoryModel.Storage(read: { namespace in
            XCTAssertFalse(model.isPhysicallyIdle); return memory.values[namespace.storageKey]
        }, write: { namespace, bytes in
            XCTAssertFalse(model.isPhysicallyIdle); memory.values[namespace.storageKey] = bytes
        })
        model = .init(storage: storage, schedule: { _, _ in {} })
        model.changeContext(to: .confirmed(userID: "reader-a"))
        let ticket = try XCTUnwrap(model.beginArticle(articleID: "different"))
        XCTAssertEqual(model.markRead(ticket), .written); XCTAssertTrue(model.isPhysicallyIdle)
        XCTAssertFalse(model.isLocalCleanupAvailable)
    }
}
