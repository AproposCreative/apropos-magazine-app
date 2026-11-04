import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderMutationFileJournalTests: XCTestCase {
    private typealias Journal = ReaderMutationFileJournal
    private typealias Record = ReaderMutationJournalRecord
    private typealias Codec = ReaderMutationJournalCodec
    private let uid = "reader_a"

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("reader-mutation-journal-" + UUID().uuidString, isDirectory: true)
    }
    private func request(owner: String = "reader_a", epoch: Int64 = 1, revision: Int64 = 0,
                         id: String = UUID().uuidString.lowercased(), articleID: String = "article-1") throws -> ReaderMutationContract.Request {
        try .init(binding: .init(ownerUID: owner, epoch: epoch), mutationID: id, expectedRevision: revision,
                  payload: .favoriteRemove(articleID: articleID))
    }
    private func read(_ journal: Journal, owner: String = "reader_a") async throws -> Record? {
        try await withCheckedThrowingContinuation { continuation in
            journal.read(ownerUID: owner) { continuation.resume(with: $0) }
        }
    }
    private func write(_ journal: Journal, _ record: Record, expected: UUID?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            journal.write(record, expectedRevision: expected) { continuation.resume(with: $0) }
        }
    }
    private func onlyFile(_ root: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1)
        return try XCTUnwrap(files.first)
    }
    private func receipt(_ request: ReaderMutationContract.Request) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "scope": ReaderMutationContract.scope,
            "requestID": request.requestID, "status": "committed", "committedRevision": request.expectedRevision + 1,
            "request": try JSONSerialization.jsonObject(with: ReaderMutationContract.encode(request))], options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func waitForStart(_ gate: Gate) async {
        let began = await Task.detached { gate.waitForStart() }.value
        XCTAssertTrue(began, "Actual journal replacement did not begin")
    }

    func testConstructionAndMissingReadAreInertAndNeverCreateDirectories() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = Journal(rootDirectory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let result = try await read(journal)
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testWriteRequiresSuccessfulReadForTheExactOriginalOwner() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = Journal(rootDirectory: root), original = try Record(ownerUID: uid).appending(request())
        do { try await write(journal, original, expected: nil); XCTFail("Unobserved record written") }
        catch { XCTAssertEqual(error as? Journal.Failure, .readRequired) }
        _ = try await read(journal, owner: "reader_b")
        do { try await write(journal, original, expected: nil); XCTFail("Another owner's read admitted write") }
        catch { XCTAssertEqual(error as? Journal.Failure, .readRequired) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testActualDiskRoundTripAndRestartPreserveOriginalEpochMutationAndResourceRevision() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let originalRequest = try request(epoch: 4, revision: 17)
        let newerMembership = try request(epoch: 5, revision: 0)
        let original = try Record(ownerUID: uid).appending(originalRequest).appending(newerMembership)
        let journal = Journal(rootDirectory: root)
        _ = try await read(journal)
        try await write(journal, original, expected: nil)
        let path = try onlyFile(root)
        XCTAssertFalse(path.lastPathComponent.contains(uid))
        XCTAssertEqual(try Data(contentsOf: path), try Codec.encode(original), "Completion precedes a real file commit")
        let restarted = Journal(rootDirectory: root)
        let loaded = try await read(restarted)
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(try Codec.encode(restored), try Codec.encode(original))
        XCTAssertEqual(restored.entries.map(\.request.membershipEpoch), [4, 5])
        XCTAssertEqual(restored.entries.map(\.request.expectedRevision), [17, 0])
        XCTAssertEqual(restored.entries.first?.request.mutationID, originalRequest.mutationID)
        XCTAssertTrue(restored.entries.allSatisfy { $0.receiptData == nil })
    }

    func testHistoricalReceiptAndLaterIntentRemainDistinctAcrossDiskRestart() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try request(epoch: 2, revision: 8), second = try request(epoch: 2, revision: 9)
        let received = try receipt(first)
        let original = try Record(ownerUID: uid).appending(first).appending(second)
        let acknowledged = try original.acknowledging(requestID: first.requestID, receiptData: received)
        let journal = Journal(rootDirectory: root); _ = try await read(journal)
        try await write(journal, original, expected: nil)
        try await write(journal, acknowledged, expected: original.recordRevision)
        let loaded = try await read(Journal(rootDirectory: root))
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.entries.map(\.request), [first, second])
        XCTAssertEqual(restored.entries[0].receiptData, received)
        XCTAssertNil(restored.entries[1].receiptData)
        XCTAssertEqual(try ReaderMutationContract.decodeReceipt(data: received, for: first).committedRevision, 9)
    }

    func testExplicitLegacySnapshotRoundTripPreservesOriginalBytesWithoutCreatingRequests() async throws {
        let root = directory(), oldDirectory = directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: oldDirectory) }
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
        let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": namespace.recordBinding, "entries": []], options: [.prettyPrinted])
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let oldFile = oldDirectory.appendingPathComponent("legacy-v1.json"); try bytes.write(to: oldFile)
        let original = try Record(ownerUID: uid).preservingLegacy(kind: .favoritesV1, data: bytes)
        let journal = Journal(rootDirectory: root); _ = try await read(journal)
        try await write(journal, original, expected: nil)
        let loaded = try await read(Journal(rootDirectory: root))
        let restored = try XCTUnwrap(loaded)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertEqual(restored.legacySnapshots.first?.rawData, bytes)
        XCTAssertEqual(try Data(contentsOf: oldFile), bytes)
    }

    func testParallelInstancesSharePhysicalCASAndOnlyOneStaleExpectedHeadCanWin() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let first = Journal(rootDirectory: root, replace: { try gate.replace($0, $1) })
        let second = Journal(rootDirectory: root)
        _ = try await read(first); _ = try await read(second)
        let winner = try Record(ownerUID: uid).appending(request()), stale = try Record(ownerUID: uid).appending(request(articleID: "stale"))
        let accepted = expectation(description: "First physical CAS commits"), rejected = expectation(description: "Second physical CAS sees changed disk head")
        first.write(winner, expectedRevision: nil) { result in
            if case .failure(let error) = result { XCTFail("First write failed: \(error)") }; accepted.fulfill()
        }
        await waitForStart(gate)
        second.write(stale, expectedRevision: nil) { result in
            guard case .failure(let error) = result else { XCTFail("Concurrent stale writer overwrote winner"); rejected.fulfill(); return }
            XCTAssertEqual(error as? Journal.Failure, .staleRevision); rejected.fulfill()
        }
        XCTAssertFalse(gate.wasMainThread)
        gate.release(); await fulfillment(of: [accepted, rejected], timeout: 5)
        XCTAssertEqual(try Codec.decode(Data(contentsOf: onlyFile(root)), ownerUID: uid), winner)
    }

    func testCommittedButUnreportedReplacementRetriesTheExactOriginalRecord() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = CommitThenFail()
        let journal = Journal(rootDirectory: root, replace: { try probe.replace($0, $1) })
        _ = try await read(journal)
        let original = try Record(ownerUID: uid).appending(request(epoch: 8, revision: 7))
        do { try await write(journal, original, expected: nil); XCTFail("Injected lost callback reported success") }
        catch { XCTAssertEqual(error as? Journal.Failure, .writeFailed) }
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(original))
        try await write(journal, original, expected: nil)
        XCTAssertEqual(probe.replacements, 1, "Exact retry must not physically rewrite an already committed record")
        let loaded = try await read(Journal(rootDirectory: root))
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.entries.first?.request, original.entries.first?.request)
    }

    func testSameDiskUUIDWithDifferentUnicodePayloadIsNotAnExactCommittedRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let mutationID = UUID().uuidString.lowercased()
        let original = try Record(ownerUID: uid).appending(request(id: mutationID, articleID: "café"))
        let other = try Record(ownerUID: uid).appending(request(id: mutationID, articleID: "cafe\u{301}"))
        let impersonating = try Record(ownerUID: uid, recordRevision: original.recordRevision, entries: other.entries)
        let journal = Journal(rootDirectory: root); _ = try await read(journal)
        try await write(journal, original, expected: nil)
        do { try await write(journal, impersonating, expected: original.recordRevision); XCTFail("Canonical String equality hid different request bytes") }
        catch { XCTAssertEqual(error as? Journal.Failure, .staleRevision) }
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(original))
    }

    func testKnownExistingFileDisappearanceCannotBeMistakenForAnEmptyJournal() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try Record(ownerUID: uid).appending(request())
        let journal = Journal(rootDirectory: root); _ = try await read(journal)
        try await write(journal, original, expected: nil)
        let path = try onlyFile(root); try FileManager.default.removeItem(at: path)
        do { try await write(journal, Record(ownerUID: uid), expected: nil); XCTFail("A known backlog was implicitly replaced with empty state") }
        catch { XCTAssertEqual(error as? Journal.Failure, .staleRevision) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testReplacementCannotDropOrRetagOriginalRequestsEvenWithCorrectDiskCAS() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try request(epoch: 1, revision: 7)
        let original = try Record(ownerUID: uid).appending(first)
        let retagged = try Record(ownerUID: uid).appending(request(epoch: 2, revision: 0, id: first.mutationID))
        let journal = Journal(rootDirectory: root); _ = try await read(journal); try await write(journal, original, expected: nil)
        for invalid in [try Record(ownerUID: uid), retagged] {
            do { try await write(journal, invalid, expected: original.recordRevision); XCTFail("Original persisted request was removed or retagged") } catch { }
            XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(original))
        }
    }

    func testReplacementCannotForgetDurablyAcknowledgedHistoricalReceipt() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try request(), pending = try Record(ownerUID: uid).appending(first)
        let acknowledged = try pending.acknowledging(requestID: first.requestID, receiptData: receipt(first))
        let discarded = try Record(ownerUID: uid, entries: pending.entries)
        let journal = Journal(rootDirectory: root); _ = try await read(journal); try await write(journal, acknowledged, expected: nil)
        do { try await write(journal, discarded, expected: acknowledged.recordRevision); XCTFail("Persisted acknowledgement was lost") } catch { }
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(acknowledged))
    }

    func testFailedReplacementPreservesPriorFileAndCanBeRetriedAfterFreshRead() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try Record(ownerUID: uid).appending(request())
        let good = Journal(rootDirectory: root); _ = try await read(good); try await write(good, original, expected: nil)
        let candidate = try original.appending(request(revision: 1))
        let broken = Journal(rootDirectory: root, replace: { _, _ in throw Journal.Failure.writeFailed })
        _ = try await read(broken)
        do { try await write(broken, candidate, expected: original.recordRevision); XCTFail("Failed replacement accepted") }
        catch { XCTAssertEqual(error as? Journal.Failure, .writeFailed) }
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(original))
        let retry = Journal(rootDirectory: root); _ = try await read(retry); try await write(retry, candidate, expected: original.recordRevision)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(candidate))
    }

    func testAllRegisteredSnapshotsCommitWithoutCoalescingAndReadRemainsAnOrderBarrier() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, replace: { try gate.replace($0, $1) }); _ = try await read(journal)
        let one = try Record(ownerUID: uid).appending(request())
        let two = try one.appending(request(revision: 1)), three = try two.appending(request(revision: 2))
        var completed: [Int] = []
        journal.write(one, expectedRevision: nil) { result in if case .success = result { completed.append(1) } else { XCTFail("First failed") } }
        await waitForStart(gate)
        journal.write(two, expectedRevision: one.recordRevision) { result in if case .success = result { completed.append(2) } else { XCTFail("Second was lost") } }
        journal.write(three, expectedRevision: two.recordRevision) { result in if case .success = result { completed.append(3) } else { XCTFail("Third failed") } }
        let done = expectation(description: "Read after every accepted snapshot")
        journal.read(ownerUID: uid) { result in
            XCTAssertEqual(try? result.get(), three); completed.append(4); done.fulfill()
        }
        XCTAssertTrue(completed.isEmpty)
        gate.release(); await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(completed, [1, 2, 3, 4]); XCTAssertEqual(gate.starts, 3)
    }

    func testCompletionReentryObservesAcceptedHeadBeforeRegisteringNextWrite() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = Journal(rootDirectory: root); _ = try await read(journal)
        let one = try Record(ownerUID: uid).appending(request()), two = try one.appending(request(revision: 1))
        let done = expectation(description: "Reentrant write and following read")
        var order: [String] = []
        journal.write(one, expectedRevision: nil) { result in
            if case .failure(let error) = result { XCTFail("First failed: \(error)") }
            order.append("one")
            journal.write(two, expectedRevision: one.recordRevision) { result in
                if case .failure(let error) = result { XCTFail("Reentrant write failed: \(error)") }; order.append("two")
            }
            journal.read(ownerUID: self.uid) { result in XCTAssertEqual(try? result.get(), two); order.append("read"); done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 5); XCTAssertEqual(order, ["one", "two", "read"])
    }

    func testCorruptUnsupportedAndForeignFilesArePreservedWithoutLegacyFallback() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let initial = Journal(rootDirectory: root), original = try Record(ownerUID: uid)
        _ = try await read(initial); try await write(initial, original, expected: nil)
        let path = try onlyFile(root), foreign = try Codec.encode(Record(ownerUID: "reader_b"))
        for bytes in [Data("broken".utf8), Data("{\"schemaVersion\":999}".utf8), foreign] {
            try bytes.write(to: path)
            let journal = Journal(rootDirectory: root)
            do { _ = try await read(journal); XCTFail("Invalid record was treated as missing") } catch { }
            do { try await write(journal, original, expected: nil); XCTFail("Unknown record overwritten") }
            catch { XCTAssertEqual(error as? Journal.Failure, .readRequired) }
            XCTAssertEqual(try Data(contentsOf: path), bytes)
        }
    }

    func testOversizedAndSymlinkFilesAreRefusedWithoutReplacingTheirContents() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try Record(ownerUID: uid), initial = Journal(rootDirectory: root)
        _ = try await read(initial); try await write(initial, original, expected: nil)
        let path = try onlyFile(root), bytes = Data(repeating: 32, count: Codec.maximumRecordBytes + 1)
        try bytes.write(to: path)
        do { _ = try await read(Journal(rootDirectory: root)); XCTFail("Overlarge file admitted") }
        catch { XCTAssertEqual(error as? Journal.Failure, .limitExceeded) }
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        try FileManager.default.removeItem(at: path)
        let outside = root.appendingPathComponent("preserved.data"); try Data("preserve".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
        do { _ = try await read(Journal(rootDirectory: root)); XCTFail("File symlink followed") }
        catch { XCTAssertEqual(error as? Journal.Failure, .readFailed) }
        XCTAssertEqual(try Data(contentsOf: outside), Data("preserve".utf8))
    }

    func testSymlinkAndNonDirectoryRootsAreRefusedWithoutOutsideWrites() async throws {
        let root = directory(), destination = directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: destination)
        do { _ = try await read(Journal(rootDirectory: root)); XCTFail("Root symlink followed") }
        catch { XCTAssertEqual(error as? Journal.Failure, .readFailed) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        try FileManager.default.removeItem(at: root); try Data("file root".utf8).write(to: root)
        do { _ = try await read(Journal(rootDirectory: root)); XCTFail("Regular file root accepted") }
        catch { XCTAssertEqual(error as? Journal.Failure, .readFailed) }
        XCTAssertEqual(try Data(contentsOf: root), Data("file root".utf8))
    }

    func testOwnerIsolationAndReadAfterAccountReturnKeepSeparateOriginalRequests() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try Record(ownerUID: uid).appending(request(epoch: 3)), b = try Record(ownerUID: "reader_b").appending(request(owner: "reader_b", epoch: 9))
        let journal = Journal(rootDirectory: root)
        _ = try await read(journal); _ = try await read(journal, owner: "reader_b")
        try await write(journal, a, expected: nil); try await write(journal, b, expected: nil)
        let loadedB = try await read(journal, owner: "reader_b"), returnedA = try await read(journal)
        XCTAssertEqual(loadedB, b); XCTAssertEqual(returnedA, a)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(files.count, 2); XCTAssertTrue(files.allSatisfy { !$0.contains("reader_") })
        XCTAssertEqual(returnedA?.entries.first?.request.membershipEpoch, 3)
    }

    func testUnsafeUIDIsRejectedBeforeDiskWorkOrOwnerAdmission() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = Journal(rootDirectory: root)
        for owner in ["", "../reader", "reader/child", "reader a", String(repeating: "u", count: 129)] {
            do { _ = try await read(journal, owner: owner); XCTFail("Unsafe owner admitted") }
            catch { XCTAssertEqual(error as? Journal.Failure, .readFailed) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testFailedQueuedRereadRevokesPreviouslyRegisteredWriteBeforeCallbackReentry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let initial = Journal(rootDirectory: root), original = try Record(ownerUID: uid).appending(request())
        _ = try await read(initial); try await write(initial, original, expected: nil)
        let originalPath = try onlyFile(root)
        let gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, replace: { try gate.replace($0, $1) })
        _ = try await read(journal); _ = try await read(journal, owner: "blocker")
        journal.write(try Record(ownerUID: "blocker"), expectedRevision: nil) { _ in }
        await waitForStart(gate)
        let corrupt = Data("corrupt after known successful read".utf8); try corrupt.write(to: originalPath)
        let readDone = expectation(description: "Failed reread revokes head"), writeDone = expectation(description: "Already queued write rejected")
        let later = try original.appending(request(revision: 1))
        journal.read(ownerUID: uid) { result in
            if case .success = result { XCTFail("Corrupt reread succeeded") }
            journal.write(later, expectedRevision: original.recordRevision) { reentrant in
                guard case .failure(let error) = reentrant else { XCTFail("Reentrant write reused revoked read"); return }
                XCTAssertEqual(error as? Journal.Failure, .readRequired)
            }
            readDone.fulfill()
        }
        journal.write(later, expectedRevision: original.recordRevision) { result in
            guard case .failure(let error) = result else { XCTFail("Queued write reused revoked read"); writeDone.fulfill(); return }
            XCTAssertEqual(error as? Journal.Failure, .readRequired); writeDone.fulfill()
        }
        gate.release(); await fulfillment(of: [readDone, writeDone], timeout: 5)
        XCTAssertEqual(gate.starts, 1); XCTAssertEqual(try Data(contentsOf: originalPath), corrupt)
    }

    func testPendingQueueLimitRejectsExcessWithoutReleasingHeldPhysicalWork() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, replace: { try gate.replace($0, $1) }); _ = try await read(journal)
        journal.write(try Record(ownerUID: uid), expectedRevision: nil) { _ in }
        await waitForStart(gate)
        let completed = expectation(description: "All bounded pending reads complete"); completed.expectedFulfillmentCount = Journal.maximumPendingJobs
        for _ in 0..<Journal.maximumPendingJobs { journal.read(ownerUID: uid) { _ in completed.fulfill() } }
        var refused = false
        journal.read(ownerUID: uid) { result in if case .failure(let error) = result { refused = error as? Journal.Failure == .limitExceeded } }
        XCTAssertTrue(refused); XCTAssertEqual(gate.starts, 1)
        gate.release(); await fulfillment(of: [completed], timeout: 5)
    }

    func testOwnerHeadLimitPreservesExistingOwnersInsteadOfEvictingProof() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = Journal(rootDirectory: root)
        for index in 0..<Journal.maximumOwners { _ = try await read(journal, owner: "reader_\(index)") }
        do { _ = try await read(journal, owner: "reader_extra"); XCTFail("Unbounded owner admission") }
        catch { XCTAssertEqual(error as? Journal.Failure, .limitExceeded) }
        let existing = try Record(ownerUID: "reader_0").appending(request(owner: "reader_0"))
        try await write(journal, existing, expected: nil)
        XCTAssertEqual(try Codec.decode(Data(contentsOf: onlyFile(root)), ownerUID: "reader_0"), existing)
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock(), started = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0)
        private var count = 0, main = false
        var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
        var wasMainThread: Bool { lock.lock(); defer { lock.unlock() }; return main }
        func waitForStart() -> Bool { started.wait(timeout: .now() + 5) == .success }
        func release() { released.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); count += 1; main = main || Thread.isMainThread; let first = count == 1; lock.unlock()
            if first {
                started.signal()
                guard released.wait(timeout: .now() + 10) == .success else { throw Journal.Failure.writeFailed }
            }
            try data.write(to: url, options: .atomic)
        }
    }
    private final class CommitThenFail: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var replacements: Int { lock.lock(); defer { lock.unlock() }; return count }
        func replace(_ data: Data, _ url: URL) throws {
            try data.write(to: url, options: .atomic)
            lock.lock(); count += 1; let first = count == 1; lock.unlock()
            if first { throw Journal.Failure.writeFailed }
        }
    }
}
