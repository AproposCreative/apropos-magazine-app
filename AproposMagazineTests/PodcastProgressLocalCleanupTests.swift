import Foundation
import XCTest
@testable import Apropos

@MainActor
final class PodcastProgressLocalCleanupTests: XCTestCase {
    private func namespace(_ uid: String? = "reader-a") -> PodcastProgressNamespace {
        PodcastProgressContext.confirmed(userID: uid).namespace!
    }
    private func bytes(_ owner: PodcastProgressNamespace, seconds: Double = 42) throws -> Data {
        try PodcastProgressRecordCodec.encode(.init(entries: [
            .init(episodeID: "episode", articleID: "article", positionSeconds: seconds, durationSeconds: 600)
        ], lastEpisodeID: "episode"), namespace: owner)
    }
    private func checkpoint(epoch: Int64 = 7, transition: UUID = UUID(),
                            digest: String = String(repeating: "a", count: 64)) throws -> ReaderTransitionRecoveryStore.DeletionCheckpoint {
        try .init(marker: .init(binding: .init(ownerUID: "reader-a", epoch: epoch), transitionID: transition),
                  request: .init(expectedUID: "reader-a", membershipEpoch: epoch), phase: .ledger, configurationDigest: digest)
    }
    private func memory() throws -> Memory {
        let value = Memory()
        for uid in [Optional("reader-a"), Optional("reader-b"), nil] { value.records[namespace(uid).storageKey] = try bytes(namespace(uid)) }
        value.records["podcast_progress_v0"] = Data("unowned legacy progress".utf8)
        value.records["lastPlayedEpisode"] = Data("unowned last episode".utf8)
        return value
    }
    private func closedStore(_ memory: Memory) -> PodcastPlaybackProgressStore {
        let store = PodcastPlaybackProgressStore(storage: memory.storage)
        store.revokeForRecovery()
        return store
    }
    private func permit() -> ReaderLegacyWriteAdmission { .init(isAllowed: true) }
    private func failure<Value>(_ work: () async throws -> Value,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await work(); XCTFail("Unexpected success", file: file, line: line) } catch { }
    }
    @MainActor private final class Memory {
        var records: [String: Data] = [:]
        var reads: [PodcastProgressNamespace] = []
        var writes: [PodcastProgressNamespace] = []
        var onRead: (@MainActor (PodcastProgressNamespace) -> Void)?
        var onWrite: (@MainActor (PodcastProgressNamespace, Data) -> Void)?
        var failReadAfterWrite: Int?
        var failNextRead = false
        var failWrite: Int?
        var dropWrite: Int?
        var storage: PodcastPlaybackProgressStore.Storage {
            .init(read: { [self] owner in
                reads.append(owner); onRead?(owner)
                if failNextRead { failNextRead = false; throw PodcastProgressRecordCodec.Failure.invalidRecord }
                return records[owner.storageKey]
            }, write: { [self] owner, data in
                writes.append(owner); onWrite?(owner, data)
                if failWrite == writes.count { throw PodcastProgressRecordCodec.Failure.invalidRecord }
                if dropWrite != writes.count { records[owner.storageKey] = data }
                if failReadAfterWrite == writes.count { failNextRead = true }
            })
        }
    }

    func testBeforeSeparateCleanupRecoveryPreservesAllProgressAndUnownedKeys() throws {
        let memory = try memory(), original = memory.records
        let store = PodcastPlaybackProgressStore(storage: memory.storage)
        store.changeContext(to: .confirmed(userID: "reader-a"))
        let session = try XCTUnwrap(store.beginSession(episodeID: "episode", articleID: "article"))
        store.revokeForRecovery()
        XCTAssertEqual(store.save(session.ticket, seconds: 70, duration: 600), .stale)
        XCTAssertEqual(store.complete(session.ticket), .stale)
        XCTAssertEqual(memory.records, original); XCTAssertTrue(memory.writes.isEmpty)
    }

    func testPrepareIsReadOnlyAndUsesPodcastDomain() async throws {
        let memory = try memory(), original = memory.records, store = closedStore(memory)
        let lease = try await store.prepareLocalCleanup(checkpoint: checkpoint(), finalAdmission: permit(), stillCurrent: { true })
        XCTAssertEqual(lease.owner, namespace().recordBinding); XCTAssertEqual(lease.originalEntryCount, 1)
        XCTAssertNotEqual(lease.owner, ReadingHistoryContext.confirmed(userID: "reader-a").namespace?.recordBinding)
        XCTAssertNotEqual(lease.owner, FavoritesContext.confirmed(userID: "reader-a").namespace?.recordBinding)
        XCTAssertEqual(memory.records, original); XCTAssertTrue(memory.writes.isEmpty)
        XCTAssertTrue(memory.reads.allSatisfy { $0 == namespace() })
    }

    func testConfirmedCleanupClearsPositionsAndLastAssociationPreservingEveryOtherKey() async throws {
        let memory = try memory(), original = memory.records, store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        let receipt = try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
        XCTAssertTrue(receipt.isComplete); XCTAssertTrue(receipt.belongs(to: cp)); XCTAssertEqual(receipt.originalEntryCount, 1)
        let final = try PodcastProgressRecordCodec.decode(XCTUnwrap(memory.records[namespace().storageKey]), namespace: namespace())
        XCTAssertTrue(final.entries.isEmpty); XCTAssertNil(final.lastEpisodeID); XCTAssertEqual(final.cleanup?.phase, .complete)
        for (key, value) in original where key != namespace().storageKey { XCTAssertEqual(memory.records[key], value) }
        XCTAssertEqual(memory.writes, [namespace(), namespace()]); XCTAssertFalse(store.hasPlaybackAccess)
    }

    func testNormalLegacyEncodingStaysCanonicalAndNilIsDistinctFromEmptyRecord() async throws {
        let raw = try bytes(namespace())
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("cleanup"))
        XCTAssertEqual(try PodcastProgressRecordCodec.encode(PodcastProgressRecordCodec.decode(raw, namespace: namespace()), namespace: namespace()), raw)
        let memory = Memory(), store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        XCTAssertTrue(memory.records.isEmpty)
        memory.records[namespace().storageKey] = try PodcastProgressRecordCodec.encode(.empty, namespace: namespace())
        await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertTrue(memory.writes.isEmpty)
    }

    func testUnclosedOrDeniedPreparationPerformsNoStorage() async throws {
        let memory = try memory(), normal = PodcastPlaybackProgressStore(storage: memory.storage), cp = try checkpoint()
        await failure { try await normal.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true }) }
        normal.revokeForRecovery()
        await failure { try await normal.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { false }) }
        XCTAssertTrue(memory.reads.isEmpty); XCTAssertTrue(memory.writes.isEmpty)
    }

    func testLeaseCannotCrossStoresOrBeReusedAfterDeniedConfirmation() async throws {
        let memory = try memory(), first = closedStore(memory), second = closedStore(memory), cp = try checkpoint()
        let lease = try await first.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        await failure { try await second.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        await failure { try await first.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { false }) }
        await failure { try await first.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertTrue(memory.writes.isEmpty)
    }

    func testChangedOwnerBytesAndUnknownOrRepeatedFieldsAreNotRemoved() async throws {
        let cp = try checkpoint(), raw = try bytes(namespace()), text = String(decoding: raw, as: UTF8.self)
        for changed in [Data("invalid".utf8),
                        Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"future\":true").utf8),
                        Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1").utf8),
                        Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"cleanup\":null").utf8)] {
            let memory = Memory(); memory.records[namespace().storageKey] = changed
            let store = closedStore(memory)
            await failure { try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true }) }
            XCTAssertEqual(memory.records[namespace().storageKey], changed); XCTAssertTrue(memory.writes.isEmpty)
        }
        let memory = try memory(), store = closedStore(memory)
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        let changed = try bytes(namespace(), seconds: 80); memory.records[namespace().storageKey] = changed
        await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(memory.records[namespace().storageKey], changed); XCTAssertTrue(memory.writes.isEmpty)
    }

    func testPendingAndCompleteReadbackFailureRequireFreshConfirmationAfterLogicalReconstruction() async throws {
        for failedWrite in [1, 2] {
            let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
            memory.failReadAfterWrite = failedWrite
            let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
            await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
            await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
            // Reconstructs Swift objects over retained injected bytes; no process kill or Defaults durability claim.
            let freshStore = closedStore(memory)
            let fresh = try await freshStore.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
            let receipt = try await freshStore.commitLocalCleanup(fresh, finalAdmission: permit(), stillCurrent: { true })
            XCTAssertTrue(receipt.isComplete)
        }
    }

    func testStoredPendingOrCompleteBlocksNormalOwnerPlaybackButPreservesBAndGuest() async throws {
        for failAfter in [1, 2] {
            let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
            memory.failReadAfterWrite = failAfter
            let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
            await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
            let normal = PodcastPlaybackProgressStore(storage: memory.storage)
            normal.changeContext(to: .confirmed(userID: "reader-a"))
            XCTAssertFalse(normal.hasPlaybackAccess); XCTAssertNil(normal.beginSession(episodeID: "episode", articleID: nil))
            XCTAssertNil(normal.snapshot.lastPlayedEpisodeID)
            normal.changeContext(to: .confirmed(userID: "reader-b"))
            XCTAssertEqual(normal.snapshot.position(for: "episode"), 42)
            normal.changeContext(to: .guest)
            XCTAssertEqual(normal.snapshot.position(for: "episode"), 42)
        }
    }

    func testDroppedFirstPendingWriteCannotAdoptChangedOwnerOnFreshPrepare() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        memory.dropWrite = 1
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        let changed = try bytes(namespace(), seconds: 80); memory.records[namespace().storageKey] = changed
        await failure { try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(memory.records[namespace().storageKey], changed); XCTAssertEqual(memory.writes.count, 1)
    }

    func testChangedPendingSourceAndOriginalFamilyAreRejected() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        memory.failWrite = 2
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        for other in [try checkpoint(epoch: 8, transition: cp.marker.transitionID), try checkpoint(),
                      try checkpoint(transition: cp.marker.transitionID, digest: String(repeating: "b", count: 64))] {
            await failure { try await store.prepareLocalCleanup(checkpoint: other, finalAdmission: permit(), stillCurrent: { true }) }
        }
        let raw = try XCTUnwrap(memory.records[namespace().storageKey])
        let changed = String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "\"positionSeconds\":42", with: "\"positionSeconds\":80")
        XCTAssertNotEqual(Data(changed.utf8), raw)
        memory.records[namespace().storageKey] = Data(changed.utf8)
        await failure { try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(memory.writes.count, 2)
    }

    func testReentrantPrewriteReadCancellationRejectsWriteAndKeepsActualGuardUntilReturn() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        var task: Task<PodcastPlaybackProgressStore.CleanupReceipt, Error>?
        memory.onRead = { _ in
            XCTAssertFalse(store.isPhysicallyIdle)
            task?.cancel()
        }
        task = Task { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        await failure { try await task!.value }
        XCTAssertTrue(store.isPhysicallyIdle); XCTAssertTrue(memory.writes.isEmpty)
    }

    func testFinalPrewriteReadRevokesPureAdmissionWithoutTaskCancellation() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        let finalAdmission = permit(); var reads = 0
        memory.onRead = { _ in
            reads += 1
            if reads == 2 { finalAdmission.setAllowed(false) }
        }
        await failure { try await store.commitLocalCleanup(lease, finalAdmission: finalAdmission, stillCurrent: { true }) }
        XCTAssertEqual(reads, 2); XCTAssertTrue(memory.writes.isEmpty)
        XCTAssertFalse(finalAdmission.isAllowed)
    }

    func testPrepareFinalReadRevocationDoesNotReturnLease() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint(), finalAdmission = permit()
        memory.onRead = { _ in if memory.reads.count == 2 { finalAdmission.setAllowed(false) } }
        await failure { try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: finalAdmission, stillCurrent: { true }) }
        XCTAssertEqual(memory.reads.count, 2); XCTAssertTrue(memory.writes.isEmpty)
    }

    func testLastPrewritePermissionHookCannotOverwriteChangedSource() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        let originalReadCount = memory.reads.count, changed = try bytes(namespace(), seconds: 90)
        await failure {
            try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: {
                if memory.reads.count == originalReadCount + 1 { memory.records[self.namespace().storageKey] = changed }
                return true
            })
        }
        XCTAssertTrue(memory.writes.isEmpty); XCTAssertEqual(memory.records[namespace().storageKey], changed)
    }

    func testCancellationInsideWriteFinishesItsReadbackButDoesNotRemoveOwner() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        var task: Task<PodcastPlaybackProgressStore.CleanupReceipt, Error>?, readsAtWrite = 0
        memory.onWrite = { _, _ in
            XCTAssertFalse(store.isPhysicallyIdle); readsAtWrite = memory.reads.count; task?.cancel()
        }
        task = Task { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true }) }
        await failure { try await task!.value }
        XCTAssertEqual(memory.writes.count, 1); XCTAssertGreaterThan(memory.reads.count, readsAtWrite)
        XCTAssertEqual(try PodcastProgressRecordCodec.decode(XCTUnwrap(memory.records[namespace().storageKey]), namespace: namespace()).cleanup?.phase, .pending)
        XCTAssertTrue(store.isPhysicallyIdle)
    }

    func testOriginalGenerationReentryRejectsAToBToAAfterPendingWrite() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        var generation = 0
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { generation == 0 })
        memory.onWrite = { _, _ in
            XCTAssertFalse(store.isPhysicallyIdle); generation = 1; generation = 2
            store.changeContext(to: .confirmed(userID: "reader-b")); store.changeContext(to: .confirmed(userID: "reader-a"))
        }
        await failure { try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { generation == 0 }) }
        XCTAssertEqual(memory.writes.count, 1); XCTAssertFalse(store.hasPlaybackAccess)
    }

    func testFinalPermissionHookCannotHideChangedReadback() async throws {
        let memory = try memory(), store = closedStore(memory), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        await failure {
            try await store.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: {
                XCTAssertFalse(store.isPhysicallyIdle)
                if memory.writes.count == 2 { memory.records[self.namespace().storageKey] = Data("changed after complete".utf8) }
                return true
            })
        }
        XCTAssertEqual(memory.records[namespace().storageKey], Data("changed after complete".utf8))
    }

    private func recovery() async throws -> (ReaderTransitionRecovery, ReaderTransitionRecoveryStore.DeletionCheckpoint, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("podcast-cleanup-" + UUID().uuidString)
        let recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        try await recovery.bootstrap()
        _ = try await recovery.seal(binding: .init(ownerUID: "reader-a", epoch: 7))
        _ = try await recovery.recordDeletion(request: .init(expectedUID: "reader-a", membershipEpoch: 7),
                                             phase: .parent, configurationDigest: String(repeating: "a", count: 64))
        let checkpoint = try await recovery.recordDeletion(request: .init(expectedUID: "reader-a", membershipEpoch: 7),
                                                          phase: .ledger, configurationDigest: String(repeating: "a", count: 64))
        return (recovery, checkpoint, directory)
    }

    func testColdRuntimeGetterIsInertAndOnlyOriginalExplicitPreparationConstructsRawStorage() async throws {
        let (recovery, cp, directory) = try await recovery(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = try memory(); var factories = 0
        let runtime = PodcastProgressRuntime(disabled: false, storageFactory: { factories += 1; return memory.storage }, recovery: recovery)
        let model = try XCTUnwrap(runtime.localCleanupStore())
        XCTAssertTrue(model === runtime.model); XCTAssertEqual(factories, 0)
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "reader-a")
        XCTAssertEqual(factories, 0); XCTAssertTrue(memory.reads.isEmpty)
        await failure { try await model.prepareLocalCleanup(checkpoint: checkpoint(), finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(factories, 0)
        let lease = try await model.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { true })
        XCTAssertEqual(factories, 1); XCTAssertFalse(model.hasPlaybackAccess)
        let receipt = try await model.commitLocalCleanup(lease, finalAdmission: permit(), stillCurrent: { true })
        XCTAssertTrue(receipt.isComplete); XCTAssertEqual(factories, 1)
        XCTAssertTrue(memory.reads.allSatisfy { $0 == namespace() }); XCTAssertFalse(model.hasPlaybackAccess)
    }

    func testColdFactoryAuthorityReentryDoesNotInstallAdapterOrRead() async throws {
        let (recovery, cp, directory) = try await recovery(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = try memory(); var current = true, factories = 0
        var runtime: PodcastProgressRuntime!
        runtime = PodcastProgressRuntime(disabled: false, storageFactory: {
            factories += 1; XCTAssertFalse(runtime.model.isPhysicallyIdle)
            runtime.prepareIfNeeded(); current = false
            return memory.storage
        }, recovery: recovery)
        await failure { try await runtime.localCleanupStore()!.prepareLocalCleanup(checkpoint: cp, finalAdmission: permit(), stillCurrent: { current }) }
        XCTAssertEqual(factories, 1); XCTAssertTrue(memory.reads.isEmpty); XCTAssertTrue(memory.writes.isEmpty)
        XCTAssertFalse(runtime.model.hasPlaybackAccess); XCTAssertTrue(runtime.model.isPhysicallyIdle)
    }

    func testDisabledRuntimeCleanupGetterAndLegacyNoRecoveryRemainInert() async throws {
        let memory = try memory(); var factories = 0
        let disabled = PodcastProgressRuntime(disabled: true, storageFactory: { factories += 1; return memory.storage })
        XCTAssertNil(disabled.localCleanupStore())
        let legacy = PodcastProgressRuntime(disabled: false, storageFactory: { factories += 1; return memory.storage })
        await failure { try await legacy.localCleanupStore()!.prepareLocalCleanup(checkpoint: checkpoint(), finalAdmission: permit(), stillCurrent: { true }) }
        XCTAssertEqual(factories, 0); XCTAssertTrue(memory.reads.isEmpty)
    }
}
