import Foundation
import XCTest
@testable import Apropos

@MainActor
final class FavoritesLocalCleanupTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("favorites-local-cleanup-" + UUID().uuidString, isDirectory: true)
    }
    private func owner(_ uid: String = "reader-a") throws -> FavoritesNamespace {
        try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
    }
    private func file(_ root: URL, _ namespace: FavoritesNamespace) -> URL {
        root.appendingPathComponent(namespace.recordBinding + ".json")
    }
    private func legacy(_ namespace: FavoritesNamespace, id: String = "original") throws -> Data {
        let article = Article(id: id, name: "Original", slug: id, content: "", intro: "", topicID: "topic", contentRevision: "r1")
        let entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode([FavoritesRecord.Metadata(article)]))
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": namespace.recordBinding, "entries": entries], options: [.sortedKeys])
    }
    private func read(_ journal: FavoritesFileJournal, _ namespace: FavoritesNamespace) async throws -> FavoritesRecord? {
        try await withCheckedThrowingContinuation { continuation in
            journal.storage.read(namespace) { continuation.resume(with: $0) }
        }
    }
    private func checkpoint(uid: String = "reader-a", epoch: Int64 = 7,
                            transition: UUID = UUID(), digest: String = String(repeating: "a", count: 64)) throws -> ReaderTransitionRecoveryStore.DeletionCheckpoint {
        try .init(marker: .init(binding: .init(ownerUID: uid, epoch: epoch), transitionID: transition),
                  request: .init(expectedUID: uid, membershipEpoch: epoch), phase: .ledger, configurationDigest: digest)
    }
    private func prepare(_ journal: FavoritesFileJournal, _ checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                         current: @escaping @MainActor () -> Bool = { true }) async throws -> FavoritesFileJournal.CleanupLease {
        try await withCheckedThrowingContinuation { continuation in
            journal.prepareLocalCleanup(checkpoint: checkpoint, stillCurrent: current) { continuation.resume(with: $0) }
        }
    }
    private func begin(_ journal: FavoritesFileJournal, _ lease: FavoritesFileJournal.CleanupLease,
                       current: @escaping @MainActor () -> Bool = { true }) async throws -> FavoritesFileJournal.CleanupReceipt {
        try await withCheckedThrowingContinuation { continuation in
            journal.beginLocalCleanup(lease, stillCurrent: current) { continuation.resume(with: $0) }
        }
    }
    private func commit(_ journal: FavoritesFileJournal, _ lease: FavoritesFileJournal.CleanupLease,
                        current: @escaping @MainActor () -> Bool = { true }) async throws -> FavoritesFileJournal.CleanupReceipt {
        try await withCheckedThrowingContinuation { continuation in
            journal.commitLocalCleanup(lease, stillCurrent: current) { continuation.resume(with: $0) }
        }
    }
    private func cleanupFile(_ root: URL, _ namespace: FavoritesNamespace) -> URL {
        root.appendingPathComponent(namespace.recordBinding + ".cleanup.json")
    }
    private func seed(_ root: URL, _ namespace: FavoritesNamespace, id: String = "original") throws -> Data {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = FavoritesRecord(articles: [Article(id: id, name: id, slug: id, content: "", intro: "", topicID: "topic", contentRevision: "r1")])
        let bytes = try FavoritesRecordCodec.encode(record, namespace: namespace)
        try bytes.write(to: file(root, namespace)); return bytes
    }
    private final class Legacy: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [FavoritesNamespace: Data] = [:]
        private var readCount = 0, deleteCount = 0
        func set(_ data: Data?, _ namespace: FavoritesNamespace) { lock.lock(); defer { lock.unlock() }; values[namespace] = data }
        func read(_ namespace: FavoritesNamespace) -> Data? { lock.lock(); defer { lock.unlock() }; readCount += 1; return values[namespace] }
        func delete(_ namespace: FavoritesNamespace, _ expected: Data) throws {
            lock.lock(); defer { lock.unlock() }
            guard values[namespace] == expected else { throw FavoritesFileJournal.CleanupFailure.changedSource }
            deleteCount += 1; values.removeValue(forKey: namespace)
        }
        var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
        var deletes: Int { lock.lock(); defer { lock.unlock() }; return deleteCount }
    }
    private final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var opened = false, started = false
        func hold() {
            condition.lock(); started = true; condition.broadcast()
            while !opened { condition.wait() }
            condition.unlock()
        }
        func release() { condition.lock(); opened = true; condition.broadcast(); condition.unlock() }
        var hasStarted: Bool { condition.lock(); defer { condition.unlock() }; return started }
    }
    @MainActor private final class Context { var current = true; var returned = false }
    private func waitForStart(_ gate: Gate) async {
        for _ in 0..<2_000 where !gate.hasStarted { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(gate.hasStarted)
    }
    private func journal(_ root: URL, _ legacy: Legacy,
                         replace: @escaping FavoritesFileJournal.Replace = { try $0.write(to: $1, options: .atomic) },
                         remove: @escaping FavoritesFileJournal.Remove = { try FileManager.default.removeItem(at: $0) },
                         legacyDelete: FavoritesFileJournal.LegacyDelete? = nil) -> FavoritesFileJournal {
        FavoritesFileJournal(rootDirectory: root, legacyRead: { legacy.read($0) }, replace: replace,
                             legacyDelete: legacyDelete ?? { try legacy.delete($0, $1) }, remove: remove)
    }

    /// Before reproduction: deleting v2 alone is insufficient while its v1 key
    /// remains. This unmarked legacy behavior is intentionally documented; the
    /// explicit cleanup/tombstone path must prevent this resurrection.
    func testBeforeReproductionRemovingV2AloneResurrectsRetainedOwnerV1() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let namespace = try owner(), v1 = try legacy(namespace)
        let journal = FavoritesFileJournal(rootDirectory: root, legacyRead: { requested in
            requested == namespace ? v1 : nil
        })
        let first = try await read(journal, namespace)
        XCTAssertEqual(first?.articles.map(\.id), ["original"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(root, namespace).path))
        try FileManager.default.removeItem(at: file(root, namespace))
        let restarted = FavoritesFileJournal(rootDirectory: root, legacyRead: { requested in
            requested == namespace ? v1 : nil
        })
        let resurrected = try await read(restarted, namespace)
        XCTAssertEqual(resurrected?.articles.map(\.id), ["original"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(root, namespace).path))
    }

    func testPrepareIsReadOnlyAndCommitCannotSkipConfirmedBegin() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(), v1 = try legacy(ns), v2 = try seed(root, ns)
        source.set(v1, ns); let journal = journal(root, source)
        let lease = try await prepare(journal, checkpoint())
        XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2); XCTAssertEqual(source.read(ns), v1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupFile(root, ns).path))
        do { _ = try await commit(journal, lease); XCTFail("Commit without a durable confirmed begin") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .missingBegin) }
        XCTAssertEqual(source.deletes, 0); XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2)
    }

    func testConfirmedBeginOnlySealsThenCompleteRemovesBothOriginalFormatsAndPreservesOtherOwners() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), other = try owner("reader-b"), source = Legacy()
        let a1 = try legacy(ns), a2 = try seed(root, ns), b1 = try legacy(other, id: "b"), b2 = try seed(root, other, id: "b")
        let guest1 = try legacy(.guest, id: "guest"), guest2 = try seed(root, .guest, id: "guest")
        source.set(a1, ns); source.set(b1, other); source.set(guest1, .guest)
        let journal = journal(root, source), restartedBeforeBegin = self.journal(root, source)
        _ = try await read(restartedBeforeBegin, ns)
        let original = try checkpoint(), lease = try await prepare(journal, original)
        let pending = try await begin(journal, lease)
        XCTAssertFalse(pending.isComplete); XCTAssertEqual(pending.phase, .v2)
        XCTAssertEqual(try Data(contentsOf: file(root, ns)), a2); XCTAssertEqual(source.read(ns), a1)
        do { _ = try await read(restartedBeforeBegin, ns); XCTFail("A second instance reopened a sealed namespace") } catch { }
        let writeDenied: Result<Void, Error> = await withCheckedContinuation { continuation in
            restartedBeforeBegin.storage.write(ns, .empty, nil) { continuation.resume(returning: $0) }
        }
        if case .success = writeDenied { XCTFail("A prior read authorized a post-tombstone write") }
        let snapshot: Result<FavoritesFileJournal.SnapshotLease, Error> = await withCheckedContinuation { continuation in
            _ = restartedBeforeBegin.freezeForTransition(namespace: ns) { continuation.resume(returning: $0) }
        }
        if case .success = snapshot { XCTFail("Raw legacy snapshot bypassed cleanup tombstone") }
        let complete = try await commit(journal, lease)
        XCTAssertTrue(complete.isComplete); XCTAssertEqual(complete.requestID, original.request.requestID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, ns).path)); XCTAssertNil(source.read(ns))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cleanupFile(root, ns).path))
        XCTAssertEqual(try Data(contentsOf: file(root, other)), b2); XCTAssertEqual(source.read(other), b1)
        XCTAssertEqual(try Data(contentsOf: file(root, .guest)), guest2); XCTAssertEqual(source.read(.guest), guest1)
        let restarted = self.journal(root, source)
        do { _ = try await read(restarted, ns); XCTFail("Completed cleanup resurrected v1") } catch { }
        let again = try await prepare(restarted, original)
        let finalReceipt = try await commit(restarted, again)
        XCTAssertTrue(finalReceipt.isComplete)
        XCTAssertEqual(source.deletes, 1)
    }

    func testClosedAndReentrantAdmissionDoNotReadOrOverrideNewerPrepare() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = Legacy(), journal = journal(root, source), checkpoint = try checkpoint()
        do { _ = try await prepare(journal, checkpoint, current: { false }); XCTFail("Denied preparation") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .denied) }
        XCTAssertEqual(source.reads, 0); XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let freshDone = expectation(description: "New reentrant prepare")
        var reentered = false, fresh: FavoritesFileJournal.CleanupLease?
        do {
            _ = try await prepare(journal, checkpoint, current: {
                if !reentered {
                    reentered = true
                    journal.prepareLocalCleanup(checkpoint: checkpoint, stillCurrent: { true }) {
                        fresh = try? $0.get(); freshDone.fulfill()
                    }
                }
                return true
            })
            XCTFail("Older reentrant preparation borrowed new ownership")
        } catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .denied) }
        await fulfillment(of: [freshDone], timeout: 5)
        XCTAssertNotNil(fresh); XCTAssertEqual(source.reads, 1)
    }

    func testFalseAcknowledgementOrFailedMarkerNeverDeletesSource() async throws {
        for throwInstead in [false, true] {
            let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
            let ns = try owner(), source = Legacy(), v1 = try legacy(ns), v2 = try seed(root, ns)
            source.set(v1, ns)
            let journal = journal(root, source, replace: { _, _ in
                if throwInstead { throw CocoaError(.fileWriteUnknown) }
            })
            let lease = try await prepare(journal, checkpoint())
            do { _ = try await begin(journal, lease); XCTFail("Unconfirmed marker admitted cleanup") } catch { }
            XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2); XCTAssertEqual(source.read(ns), v1)
            XCTAssertEqual(source.deletes, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupFile(root, ns).path))
        }
    }

    func testLostBeginReplyResumesOriginalFrozenRecordAfterRestart() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(), v1 = try legacy(ns), v2 = try seed(root, ns)
        source.set(v1, ns); let checkpoint = try checkpoint()
        let first = journal(root, source, replace: { data, url in
            try data.write(to: url, options: .atomic); throw CocoaError(.fileWriteUnknown)
        })
        let lease = try await prepare(first, checkpoint)
        do { _ = try await begin(first, lease); XCTFail("Lost reply reported success") } catch { }
        let marker = try Data(contentsOf: cleanupFile(root, ns))
        XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2); XCTAssertEqual(source.read(ns), v1)
        let restarted = journal(root, source), resumed = try await prepare(restarted, checkpoint)
        _ = try await begin(restarted, resumed)
        XCTAssertEqual(try Data(contentsOf: cleanupFile(root, ns)), marker)
        let finalReceipt = try await commit(restarted, resumed)
        XCTAssertTrue(finalReceipt.isComplete)
        XCTAssertNil(source.read(ns)); XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, ns).path))
    }

    func testLostRemoveReplyKeepsPendingFingerprintsAndRetryDoesNotRecreateV2() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(); source.set(try legacy(ns), ns); _ = try seed(root, ns)
        let checkpoint = try checkpoint(), first = journal(root, source, remove: { url in
            try FileManager.default.removeItem(at: url); throw CocoaError(.fileWriteUnknown)
        })
        let lease = try await prepare(first, checkpoint); _ = try await begin(first, lease)
        let frozen = try Data(contentsOf: cleanupFile(root, ns))
        do { _ = try await commit(first, lease); XCTFail("Lost remove reply") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, ns).path)); XCTAssertNotNil(source.read(ns))
        XCTAssertEqual(try Data(contentsOf: cleanupFile(root, ns)), frozen)
        let restarted = journal(root, source), resumed = try await prepare(restarted, checkpoint)
        _ = try await begin(restarted, resumed)
        XCTAssertEqual(try Data(contentsOf: cleanupFile(root, ns)), frozen)
        let finalReceipt = try await commit(restarted, resumed)
        XCTAssertTrue(finalReceipt.isComplete)
        XCTAssertNil(source.read(ns)); XCTAssertEqual(source.deletes, 1)
    }

    func testPartialLegacyFailureRejectsChangedBytesInsteadOfFreezingNewConsent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(), originalV1 = try legacy(ns)
        source.set(originalV1, ns); _ = try seed(root, ns)
        let checkpoint = try checkpoint(), first = journal(root, source, legacyDelete: { _, _ in })
        let lease = try await prepare(first, checkpoint); _ = try await begin(first, lease)
        do { _ = try await commit(first, lease); XCTFail("Ignored legacy delete") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .unconfirmed) }
        let pending = try Data(contentsOf: cleanupFile(root, ns))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, ns).path))
        let replacement = try legacy(ns, id: "new-unconfirmed-data"); source.set(replacement, ns)
        let restarted = journal(root, source)
        do { _ = try await prepare(restarted, checkpoint); XCTFail("Changed source was relabelled as original") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .changedSource) }
        XCTAssertEqual(source.read(ns), replacement); XCTAssertEqual(try Data(contentsOf: cleanupFile(root, ns)), pending)
        source.set(originalV1, ns)
        let resumed = try await prepare(restarted, checkpoint)
        let finalReceipt = try await commit(restarted, resumed)
        XCTAssertTrue(finalReceipt.isComplete)
    }

    func testFailedProgressCheckpointRetriesOriginalAbsentV2WithoutLosingV1() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(); source.set(try legacy(ns), ns); _ = try seed(root, ns)
        let checkpoint = try checkpoint(), first = journal(root, source, replace: { data, url in
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["phase"] as? String == "v1" { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let lease = try await prepare(first, checkpoint); _ = try await begin(first, lease)
        do { _ = try await commit(first, lease); XCTFail("Unwritten progress") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, ns).path)); XCTAssertNotNil(source.read(ns))
        let restarted = journal(root, source), resumed = try await prepare(restarted, checkpoint)
        let finalReceipt = try await commit(restarted, resumed)
        XCTAssertTrue(finalReceipt.isComplete)
        XCTAssertEqual(source.deletes, 1)
    }

    func testCorruptOversizedAndSymlinkTombstonesNeverPermitFallbackOrCleanup() async throws {
        for variant in 0..<3 {
            let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
            let ns = try owner(), source = Legacy(), v1 = try legacy(ns), v2 = try seed(root, ns)
            source.set(v1, ns)
            let marker = cleanupFile(root, ns), target = root.appendingPathComponent("preserve.txt")
            if variant == 2 {
                try Data("preserve".utf8).write(to: target)
                try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: target)
            } else { try Data(repeating: 120, count: variant == 0 ? 7 : 4_097).write(to: marker) }
            let journal = journal(root, source)
            do { _ = try await read(journal, ns); XCTFail("Invalid tombstone was treated as missing") } catch { }
            do { _ = try await prepare(journal, checkpoint()); XCTFail("Invalid tombstone admitted cleanup") } catch { }
            XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2); XCTAssertEqual(source.read(ns), v1)
            XCTAssertEqual(source.deletes, 0)
            if variant == 2 { XCTAssertEqual(try Data(contentsOf: target), Data("preserve".utf8)) }
        }
    }

    func testChangedV2BeforeBeginOrCommitIsPreservedWithOriginalFingerprint() async throws {
        for changeAfterBegin in [false, true] {
            let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
            let ns = try owner(), source = Legacy(); source.set(try legacy(ns), ns); _ = try seed(root, ns)
            let journal = journal(root, source), lease = try await prepare(journal, checkpoint())
            if changeAfterBegin { _ = try await begin(journal, lease) }
            let newer = try seed(root, ns, id: "changed")
            do {
                if changeAfterBegin { _ = try await commit(journal, lease) } else { _ = try await begin(journal, lease) }
                XCTFail("Changed bytes removed")
            } catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .changedSource) }
            XCTAssertEqual(try Data(contentsOf: file(root, ns)), newer); XCTAssertEqual(source.deletes, 0)
            XCTAssertEqual(FileManager.default.fileExists(atPath: cleanupFile(root, ns).path), changeAfterBegin)
        }
    }

    func testChangedFamilyAndForeignInstanceLeaseCannotResumeCleanup() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(); source.set(try legacy(ns), ns); let v2 = try seed(root, ns)
        let original = try checkpoint(), journal = journal(root, source), lease = try await prepare(journal, original)
        _ = try await begin(journal, lease)
        let changed = [try checkpoint(epoch: 8, transition: original.marker.transitionID),
                       try checkpoint(transition: UUID()),
                       try checkpoint(transition: original.marker.transitionID, digest: String(repeating: "b", count: 64))]
        for checkpoint in changed {
            do { _ = try await prepare(self.journal(root, source), checkpoint); XCTFail("Different family resumed") }
            catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .differentOriginal) }
        }
        do { _ = try await commit(self.journal(root, source), lease); XCTFail("Foreign instance lease") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .invalidLease) }
        XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2); XCTAssertEqual(source.deletes, 0)
    }

    func testPhysicalCleanupKeepsQueueOccupiedAfterCancellationAndPreservesGuest() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(), gate = Gate(), context = Context()
        defer { gate.release() }
        source.set(try legacy(ns), ns); _ = try seed(root, ns); let guest = try seed(root, .guest, id: "guest")
        let journal = journal(root, source, remove: { url in gate.hold(); try FileManager.default.removeItem(at: url) })
        let lease = try await prepare(journal, checkpoint()); _ = try await begin(journal, lease)
        let task = Task { let result = try await commit(journal, lease, current: { context.current }); context.returned = true; return result }
        await waitForStart(gate); context.current = false; task.cancel()
        XCTAssertFalse(journal.isPhysicallyIdle); XCTAssertFalse(context.returned)
        let queuedGuest = Task { try await read(journal, .guest) }
        gate.release(); let receipt = try await task.value; let guestRead = try await queuedGuest.value
        XCTAssertTrue(receipt.isComplete, "A historical original physical result does not grant new UI authority")
        XCTAssertEqual(guestRead?.articles.map(\.id), ["guest"])
        XCTAssertEqual(try Data(contentsOf: file(root, .guest)), guest)
        XCTAssertTrue(journal.isPhysicallyIdle); XCTAssertEqual(source.deletes, 1)
    }

    func testQueuedPrepareRechecksOriginalContextBeforePhysicalReads() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), other = try owner("reader-b"), source = Legacy(), gate = Gate(), context = Context()
        defer { gate.release() }
        source.set(try legacy(ns), ns); _ = try seed(root, ns); let b = try seed(root, other, id: "b")
        let journal = journal(root, source, replace: { data, url in gate.hold(); try data.write(to: url, options: .atomic) })
        let lease = try await prepare(journal, checkpoint())
        let first = Task { try await begin(journal, lease) }; await waitForStart(gate)
        let before = source.reads
        let denied = expectation(description: "Queued original denied")
        journal.prepareLocalCleanup(checkpoint: try checkpoint(uid: "reader-b"), stillCurrent: { context.current }) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .denied) }
            else { XCTFail("Old queued owner read") }
            denied.fulfill()
        }
        context.current = false; gate.release(); _ = try await first.value
        await fulfillment(of: [denied], timeout: 5)
        XCTAssertEqual(source.reads, before); XCTAssertEqual(try Data(contentsOf: file(root, other)), b)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupFile(root, other).path))
    }

    func testEmptyLegacyIsCorruptRatherThanMissingButAbsentFormatsCanBeConfirmed() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(), journal = journal(root, source)
        source.set(Data(), ns)
        do { _ = try await prepare(journal, checkpoint()); XCTFail("Empty legacy bytes treated as missing") } catch { }
        XCTAssertEqual(source.read(ns), Data()); XCTAssertEqual(source.deletes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupFile(root, ns).path))
        source.set(nil, ns)
        let lease = try await prepare(journal, checkpoint()); _ = try await begin(journal, lease)
        let result = try await commit(journal, lease)
        XCTAssertTrue(result.isComplete); XCTAssertEqual(source.deletes, 0)
    }

    func testCompletedTombstoneRejectsReappearedDataWithoutNewFingerprintOrRemoval() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let ns = try owner(), source = Legacy(), v1 = try legacy(ns), v2 = try seed(root, ns)
        source.set(v1, ns); let checkpoint = try checkpoint(), journal = journal(root, source)
        let lease = try await prepare(journal, checkpoint); _ = try await begin(journal, lease)
        _ = try await commit(journal, lease)
        let originalMarker = try Data(contentsOf: cleanupFile(root, ns))
        source.set(v1, ns); try v2.write(to: file(root, ns))
        let reopened = self.journal(root, source)
        do { _ = try await prepare(reopened, checkpoint); XCTFail("Completed receipt recaptured reappeared data") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .changedSource) }
        do { _ = try await read(reopened, ns); XCTFail("Reappeared data bypassed retained tombstone") } catch { }
        XCTAssertEqual(source.read(ns), v1); XCTAssertEqual(try Data(contentsOf: file(root, ns)), v2)
        XCTAssertEqual(try Data(contentsOf: cleanupFile(root, ns)), originalMarker); XCTAssertEqual(source.deletes, 1)
    }

    func testFinalCheckpointHookCannotReturnCompleteIfEitherOriginalFormatReappears() async throws {
        for restoreV1 in [true, false] {
            let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
            let ns = try owner(), source = Legacy(), v1 = try legacy(ns), v2 = try seed(root, ns)
            let originalFile = file(root, ns); source.set(v1, ns)
            let journal = journal(root, source, replace: { data, url in
                try data.write(to: url, options: .atomic)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if object?["phase"] as? String == "complete" {
                    if restoreV1 { source.set(v1, ns) } else { try v2.write(to: originalFile) }
                }
            })
            let checkpoint = try checkpoint(), lease = try await prepare(journal, checkpoint)
            _ = try await begin(journal, lease)
            do { _ = try await commit(journal, lease); XCTFail("Final hook restored source behind a complete receipt") }
            catch { XCTAssertEqual(error as? FavoritesFileJournal.CleanupFailure, .changedSource) }
            if restoreV1 { XCTAssertEqual(source.read(ns), v1) }
            else { XCTAssertEqual(try Data(contentsOf: originalFile), v2) }
            let reopened = self.journal(root, source)
            do { _ = try await read(reopened, ns); XCTFail("Final hook reopened legacy access") } catch { }
            do { _ = try await prepare(reopened, checkpoint); XCTFail("Restored source was silently recaptured") } catch { }
        }
    }
}
