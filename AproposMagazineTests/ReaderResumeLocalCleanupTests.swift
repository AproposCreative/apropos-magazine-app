import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderResumeLocalCleanupTests: XCTestCase {
    private func owner(_ uid: String = "reader-a") -> String {
        ReadingHistoryContext.confirmed(userID: uid).namespace!.recordBinding
    }
    private func item(_ id: String = "article") -> ReaderResumeIdentity {
        ReaderResumeIdentity(articleID: id, sourceRevision: "r1", html: "<p>Exact local article</p>")!
    }
    private func anchor(_ index: Int = 4) -> ReaderResumeAnchor { .init(index: index, fingerprint: "1234abcd") }
    private func checkpoint(uid: String = "reader-a", epoch: Int64 = 7, transition: UUID = UUID(),
                            digest: String = String(repeating: "a", count: 64)) throws -> ReaderTransitionRecoveryStore.DeletionCheckpoint {
        try .init(marker: .init(binding: .init(ownerUID: uid, epoch: epoch), transitionID: transition),
                  request: .init(expectedUID: uid, membershipEpoch: epoch), phase: .ledger, configurationDigest: digest)
    }
    private func seeded() throws -> Memory {
        Memory(try ReaderResumeRecord.encode(.init(entries: [
            .init(owner: owner(), source: item(), anchor: anchor()),
            .init(owner: owner("reader-b"), source: item(), anchor: anchor(8)),
            .init(owner: "guest", source: item(), anchor: anchor(12))
        ])))
    }
    private func failure<Value>(_ work: () async throws -> Value,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await work(); XCTFail("Unexpected success", file: file, line: line) } catch { }
    }
    private func wait(_ gate: Gate) async {
        for _ in 0..<2_000 where !gate.started { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(gate.started)
    }
    private final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var didStart = false, open = false
        var started: Bool { condition.lock(); defer { condition.unlock() }; return didStart }
        func hold() {
            condition.lock(); didStart = true; condition.broadcast()
            while !open { condition.wait() }
            condition.unlock()
        }
        func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    }
    private final class Memory: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?
        private var reads = 0, writes = 0
        private var failureAfterWrite: Int?
        private var failNextRead = false
        private var failedWrite: Int?
        private var droppedWrite: Int?
        private var readHook: (@Sendable (Int) -> Void)?
        private var writeHook: (@Sendable (Int) -> Void)?
        init(_ data: Data? = nil) { value = data }
        var bytes: Data? { lock.withLock { value } }
        var readCount: Int { lock.withLock { reads } }
        var writeCount: Int { lock.withLock { writes } }
        func replace(_ data: Data?) { lock.withLock { value = data } }
        func failReadback(afterWrite number: Int) { lock.withLock { failureAfterWrite = number } }
        func failWrite(_ number: Int) { lock.withLock { failedWrite = number } }
        func dropWrite(_ number: Int) { lock.withLock { droppedWrite = number } }
        func onRead(_ hook: (@Sendable (Int) -> Void)?) { lock.withLock { readHook = hook } }
        func onWrite(_ hook: (@Sendable (Int) -> Void)?) { lock.withLock { writeHook = hook } }
        var storage: ReaderResumeStore.Storage {
            .init(read: { [self] in
                let call = lock.withLock { reads += 1; return (reads, readHook) }
                call.1?(call.0)
                return try lock.withLock {
                    if failNextRead { failNextRead = false; throw ReaderResumeRecord.Failure.unavailable }
                    return value
                }
            }, write: { [self] data in
                let call = lock.withLock { writes += 1; return (writes, writeHook) }
                call.1?(call.0)
                try lock.withLock {
                    if failedWrite == call.0 { throw ReaderResumeRecord.Failure.unavailable }
                    if droppedWrite != call.0 { value = data }
                    if failureAfterWrite == call.0 { failNextRead = true }
                }
            })
        }
    }

    func testExistingResumeStoreRetainsAAndOtherOwnersUntilSeparateCleanup() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage)
        let before = memory.bytes
        let a = try await store.load(owner: owner(), source: item())
        let b = try await store.load(owner: owner("reader-b"), source: item())
        let guest = try await store.load(owner: "guest", source: item())
        XCTAssertEqual(a, anchor()); XCTAssertEqual(b, anchor(8)); XCTAssertEqual(guest, anchor(12))
        XCTAssertEqual(memory.bytes, before); XCTAssertEqual(memory.writeCount, 0)
    }

    func testPrepareIsReadOnlyUsesReadingHistoryNamespaceAndLegacyEncoding() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), before = memory.bytes
        let lease = try await store.prepareLocalCleanup(checkpoint: checkpoint(), stillCurrent: { true })
        XCTAssertEqual(lease.owner, owner()); XCTAssertEqual(lease.originalEntryCount, 1)
        XCTAssertNotEqual(lease.owner, FavoritesContext.confirmed(userID: "reader-a").namespace!.recordBinding)
        XCTAssertEqual(memory.bytes, before); XCTAssertEqual(memory.writeCount, 0)
        XCTAssertFalse(String(decoding: before!, as: UTF8.self).contains("cleanups"))
    }

    func testConfirmedCleanupPreservesOtherEntriesAndClosesOriginalNormalReadsAndWrites() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        let others = try ReaderResumeRecord.decode(memory.bytes).entries.filter { $0.owner != owner() }
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        let receipt = try await store.commitLocalCleanup(lease, stillCurrent: { true })
        XCTAssertTrue(receipt.isComplete); XCTAssertTrue(receipt.belongs(to: cp))
        XCTAssertEqual(receipt.owner, owner()); XCTAssertEqual(receipt.originalEntryCount, 1)
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).entries, others)
        XCTAssertEqual(memory.writeCount, 2)
        await failure { try await store.load(owner: owner(), source: item()) }
        await failure { try await store.save(owner: owner(), source: item(), anchor: anchor(20)) }
        try await store.save(owner: owner("reader-b"), source: item("new"), anchor: anchor())
        let guest = try await store.load(owner: "guest", source: item())
        XCTAssertEqual(guest, anchor(12))
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).cleanups.count, 1)
    }

    func testNilSourceIsReadOnlyUntilConfirmationAndCannotResurrectAfterReconstruction() async throws {
        let memory = Memory(), cp = try checkpoint(), first = ReaderResumeStore(storage: memory.storage)
        let lease = try await first.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        XCTAssertNil(memory.bytes); XCTAssertEqual(lease.originalEntryCount, 0)
        _ = try await first.commitLocalCleanup(lease, stillCurrent: { true })
        // Logical object reconstruction, not a killed process or a Defaults/fsync test.
        let reconstructed = ReaderResumeStore(storage: memory.storage)
        await failure { try await reconstructed.save(owner: owner(), source: item(), anchor: anchor()) }
        let fresh = try await reconstructed.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        let writes = memory.writeCount
        let receipt = try await reconstructed.commitLocalCleanup(fresh, stillCurrent: { true })
        XCTAssertTrue(receipt.isComplete); XCTAssertEqual(memory.writeCount, writes)
    }

    func testLeaseCannotCrossStoresOrBeReusedAfterAcceptedDenial() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        let other = ReaderResumeStore(storage: memory.storage)
        await failure { try await other.commitLocalCleanup(lease, stillCurrent: { true }) }
        await failure { try await store.commitLocalCleanup(lease, stillCurrent: { false }) }
        await failure { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
        XCTAssertEqual(memory.writeCount, 0)
    }

    func testClosedPrepareDoesNoStorageIOAndRepeatedAbandonedPreparesDoNotLeakCapacity() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        await failure { try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { false }) }
        XCTAssertEqual(memory.readCount, 0)
        for _ in 0...ReaderResumeStore.maximumPendingOperations {
            _ = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        }
        XCTAssertEqual(memory.writeCount, 0)
    }

    func testChangedSharedRecordRejectsOldConfirmationAndFreshSnapshotPreservesNewB() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        let old = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        try await store.save(owner: owner("reader-b"), source: item(), anchor: anchor(30))
        await failure { try await store.commitLocalCleanup(old, stillCurrent: { true }) }
        let fresh = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        _ = try await store.commitLocalCleanup(fresh, stillCurrent: { true })
        let b = try await store.load(owner: owner("reader-b"), source: item())
        XCTAssertEqual(b, anchor(30))
    }

    func testUnknownRepeatedOrMalformedFieldsAreNotDestructivelyCanonicalized() async throws {
        let original = try XCTUnwrap(try seeded().bytes), text = String(decoding: original, as: UTF8.self)
        let cases = [Data(), Data("garbage".utf8),
                     Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"unknown\":true").utf8),
                     Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1").utf8),
                     Data(text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"cleanups\":null").utf8),
                     Data(text.replacingOccurrences(of: "\"anchor\":", with: "\"futureField\":true,\"anchor\":").utf8)]
        for bytes in cases {
            let memory = Memory(bytes), store = ReaderResumeStore(storage: memory.storage)
            await failure { try await store.prepareLocalCleanup(checkpoint: checkpoint(), stillCurrent: { true }) }
            XCTAssertEqual(memory.bytes, bytes); XCTAssertEqual(memory.writeCount, 0)
        }
    }

    func testPrepareFinalReadbackCatchesReentrantSourceChange() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), changed = Data("changed".utf8)
        var checks = 0
        await failure {
            try await store.prepareLocalCleanup(checkpoint: checkpoint(), stillCurrent: {
                checks += 1
                if checks == 2 { memory.replace(changed) }
                return true
            })
        }
        XCTAssertEqual(memory.bytes, changed); XCTAssertEqual(memory.writeCount, 0)
    }

    func testPendingSealSurvivesDeniedRemovalAndFreshOriginalRetryPreservesBChanges() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        var calls = 0
        await failure { try await store.commitLocalCleanup(lease, stillCurrent: { calls += 1; return calls < 2 }) }
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).cleanups.first?.phase, .pending)
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).entries.filter { $0.owner == owner() }.count, 1)
        await failure { try await store.save(owner: owner(), source: item(), anchor: anchor(20)) }
        try await store.save(owner: owner("reader-b"), source: item(), anchor: anchor(25))
        let fresh = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        let receipt = try await store.commitLocalCleanup(fresh, stillCurrent: { true })
        XCTAssertTrue(receipt.isComplete)
        let b = try await store.load(owner: owner("reader-b"), source: item())
        XCTAssertEqual(b, anchor(25))
    }

    func testPendingAndCompleteReadbackFailuresNeedFreshConfirmationWithoutAdoptingNewA() async throws {
        for write in [1, 2] {
            let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
            memory.failReadback(afterWrite: write)
            let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
            await failure { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
            await failure { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
            let reconstructed = ReaderResumeStore(storage: memory.storage)
            let fresh = try await reconstructed.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
            let receipt = try await reconstructed.commitLocalCleanup(fresh, stillCurrent: { true })
            XCTAssertTrue(receipt.isComplete)
            var changed = try ReaderResumeRecord.decode(memory.bytes)
            changed.entries.append(.init(owner: owner(), source: item("injected"), anchor: anchor()))
            // Bypass the validating writer to model external bytes changed after cleanup.
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            memory.replace(try encoder.encode(changed))
            await failure { try await reconstructed.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true }) }
        }
    }

    func testDroppedPendingWriteRetainsOriginalSnapshotInSameStore() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        memory.dropWrite(1)
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        await failure { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
        await failure { try await store.save(owner: owner(), source: item(), anchor: anchor(20)) }
        var record = try ReaderResumeRecord.decode(memory.bytes)
        record.entries[0] = .init(owner: owner(), source: item(), anchor: anchor(30))
        let changed = try ReaderResumeRecord.encode(record); memory.replace(changed)
        await failure { try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true }) }
        XCTAssertEqual(memory.bytes, changed); XCTAssertEqual(memory.writeCount, 1)
    }

    func testRemovalWriteFailureRetainsPendingAndCanRetrySameOriginal() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        memory.failWrite(2)
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        await failure { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).cleanups.first?.phase, .pending)
        let fresh = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        let receipt = try await store.commitLocalCleanup(fresh, stillCurrent: { true })
        XCTAssertTrue(receipt.isComplete)
    }

    func testOriginalEpochTransitionAndConfigurationCannotBeSubstituted() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        _ = try await store.commitLocalCleanup(lease, stillCurrent: { true })
        for changed in [try checkpoint(epoch: 8, transition: cp.marker.transitionID),
                        try checkpoint(transition: UUID()),
                        try checkpoint(transition: cp.marker.transitionID, digest: String(repeating: "b", count: 64))] {
            await failure { try await store.prepareLocalCleanup(checkpoint: changed, stillCurrent: { true }) }
        }
        XCTAssertEqual(memory.writeCount, 2)
    }

    func testFinalHookMutationCannotProduceCompleteReceipt() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        var calls = 0
        await failure {
            try await store.commitLocalCleanup(lease, stillCurrent: {
                calls += 1
                if calls == 3 { memory.replace(Data("externally changed".utf8)) }
                return true
            })
        }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(memory.bytes, Data("externally changed".utf8))
    }

    func testPrepareWaitsForAcceptedPhysicalWriteAndIncludesItsFinalAnchor() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), gate = Gate(), cp = try checkpoint()
        memory.onWrite { if $0 == 1 { gate.hold() } }
        let oldWrite = try store.accept(owner: owner(), source: item(), anchor: anchor(25))
        await wait(gate)
        var prepared = false
        let task = Task { let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true }); prepared = true; return lease }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(prepared); gate.release()
        try await oldWrite.value()
        let lease = try await task.value
        _ = try await store.commitLocalCleanup(lease, stillCurrent: { true })
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).entries.count, 2)
    }

    func testCancelledPrewriteReadDoesNotStartWriteAndDrainStillWaitsForPhysicalRead() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint(), gate = Gate()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        let firstCommitRead = memory.readCount + 1
        memory.onRead { if $0 == firstCommitRead { gate.hold() } }
        let task = Task { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
        await wait(gate); task.cancel()
        var drained = false
        let barrier = Task { await store.waitForPhysicalIdle(); drained = true }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(drained); XCTAssertEqual(memory.writeCount, 0)
        gate.release(); await failure { try await task.value }; await barrier.value
        XCTAssertTrue(drained); XCTAssertEqual(memory.writeCount, 0)
    }

    func testCancellationInsideStartedWriteRetainsSlotThroughReadbackAndPreventsRemoval() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint(), gate = Gate()
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        memory.onWrite { if $0 == 1 { gate.hold() } }
        let task = Task { try await store.commitLocalCleanup(lease, stillCurrent: { true }) }
        await wait(gate); task.cancel()
        var drained = false
        let barrier = Task { await store.waitForPhysicalIdle(); drained = true }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(drained)
        gate.release(); await failure { try await task.value }; await barrier.value
        XCTAssertEqual(memory.writeCount, 1)
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).cleanups.first?.phase, .pending)
        let fresh = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true })
        _ = try await store.commitLocalCleanup(fresh, stillCurrent: { true })
    }

    func testOriginalGenerationRejectsAToBToAWhilePhysicalWriteIsHeld() async throws {
        let memory = try seeded(), store = ReaderResumeStore(storage: memory.storage), cp = try checkpoint(), gate = Gate()
        var generation = 0
        let lease = try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { generation == 0 })
        memory.onWrite { if $0 == 1 { gate.hold() } }
        let task = Task { try await store.commitLocalCleanup(lease, stillCurrent: { generation == 0 }) }
        await wait(gate); generation = 1; generation = 2; gate.release()
        await failure { try await task.value }
        XCTAssertEqual(memory.writeCount, 1)
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).entries.count, 3)
    }

    func testBoundedTombstonesAreNeverEvictedToAdmitNewOwner() async throws {
        let cp = try checkpoint(), memory = Memory()
        var records: [ReaderResumeLocalCleanupRecord] = []
        for index in 0..<ReaderResumeRecord.maximumCleanups {
            var record = try ReaderResumeLocalCleanupRecord(checkpoint: checkpoint(uid: "closed-\(index)"), entries: [])
            record.phase = .complete; records.append(record)
        }
        let original = try ReaderResumeRecord.encode(.init(cleanups: records)); memory.replace(original)
        let store = ReaderResumeStore(storage: memory.storage)
        await failure { try await store.prepareLocalCleanup(checkpoint: cp, stillCurrent: { true }) }
        XCTAssertEqual(memory.bytes, original); XCTAssertEqual(memory.writeCount, 0)
    }
}
