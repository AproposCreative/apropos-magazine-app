import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderMutationDispatchStoreTests: XCTestCase {
    private typealias Store = ReaderMutationDispatchStore
    private typealias Journal = ReaderMutationFileJournal
    private typealias Record = ReaderMutationJournalRecord
    private typealias Codec = ReaderMutationJournalCodec
    private typealias Request = ReaderMutationContract.Request

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("reader-dispatch-store-" + UUID().uuidString, isDirectory: true)
    }
    private func request(owner: String = "reader_a", epoch: Int64 = 2, revision: Int64 = 7,
                         id: String = UUID().uuidString.lowercased(), article: String = "article-1") throws -> Request {
        try Request(binding: .init(ownerUID: owner, epoch: epoch), mutationID: id, expectedRevision: revision,
                    payload: .favoriteRemove(articleID: article))
    }
    private func receipt(_ request: Request, pretty: Bool = false) throws -> Data {
        let object: [String: Any] = ["schemaVersion": 1, "scope": ReaderMutationContract.scope,
            "requestID": request.requestID, "status": "committed", "committedRevision": request.expectedRevision + 1,
            "request": try JSONSerialization.jsonObject(with: ReaderMutationContract.encode(request))]
        return try JSONSerialization.data(withJSONObject: object,
            options: pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes])
    }
    private func legacyBytes(owner: String = "reader_a") throws -> Data {
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: owner).namespace)
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "namespace": namespace.recordBinding, "entries": []], options: [.prettyPrinted])
    }
    private func read(_ journal: Journal, owner: String = "reader_a") async throws -> Record? {
        try await withCheckedThrowingContinuation { continuation in
            journal.read(ownerUID: owner) { continuation.resume(with: $0) }
        }
    }
    private func write(_ journal: Journal, record: Record, expected: UUID?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            journal.write(record, expectedRevision: expected) { continuation.resume(with: $0) }
        }
    }
    private func seed(_ root: URL, _ record: Record) async throws {
        let journal = Journal(rootDirectory: root)
        _ = try await read(journal, owner: record.ownerUID)
        try await write(journal, record: record, expected: nil)
    }
    private func onlyFile(_ root: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1)
        return try XCTUnwrap(files.first)
    }
    private func failure<T>(_ operation: () async throws -> T) async -> Error? {
        do { _ = try await operation(); XCTFail("Expected failure"); return nil }
        catch { return error }
    }

    func testReservationIsInertExclusiveAcrossOwnersAndOriginalLeaseOnly() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(journal: Journal(rootDirectory: root))
        let other = Store(journal: Journal(rootDirectory: root))
        let first = try request(), second = try request(owner: "reader_b")
        let lease = try XCTUnwrap(store.reserve(request: first))
        let foreign = try XCTUnwrap(other.reserve(request: first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertNil(store.reserve(request: second))
        XCTAssertTrue(store.owns(lease)); XCTAssertFalse(store.owns(foreign))
        XCTAssertFalse(store.release(foreign)); XCTAssertTrue(store.owns(lease))
        XCTAssertTrue(store.release(lease)); XCTAssertFalse(store.release(lease))
        let newer = try XCTUnwrap(store.reserve(request: second))
        XCTAssertFalse(store.release(lease)); XCTAssertTrue(store.owns(newer))
    }

    func testLoadReadsActualOriginalJournalAgainAfterRestartAndKeepsReservation() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(epoch: 12, revision: 41)
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        for _ in 0..<2 {
            let store = Store(journal: Journal(rootDirectory: root))
            let lease = try XCTUnwrap(store.reserve(request: original))
            let entry = try await store.load(lease)
            XCTAssertEqual(entry.request, original); XCTAssertNil(entry.receiptData)
            XCTAssertEqual(entry.request.membershipEpoch, 12); XCTAssertEqual(entry.request.expectedRevision, 41)
            XCTAssertTrue(store.owns(lease)); XCTAssertTrue(store.release(lease))
        }
    }

    func testMissingJournalCannotBeCreatedByLoadOrAcknowledgement() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), store = Store(journal: Journal(rootDirectory: root))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let loadError = await failure { try await store.load(lease) }
        XCTAssertEqual(loadError as? Store.Failure, .missingMutation)
        let ackError = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(ackError as? Store.Failure, .missingMutation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path)); XCTAssertTrue(store.owns(lease))
    }

    func testLegacyOnlyAndDifferentOriginalEntryNeverBecomeDispatchable() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), different = try request(article: "unrelated")
        let record = try Record(ownerUID: original.expectedUID).appending(different)
            .preservingLegacy(kind: .favoritesV1, data: legacyBytes())
        try await seed(root, record)
        let before = try Data(contentsOf: onlyFile(root)), store = Store(journal: Journal(rootDirectory: root))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let error = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(error as? Store.Failure, .missingMutation)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), before)
        XCTAssertTrue(store.release(lease))
    }

    func testExactRequestComparisonRejectsSameIDWithDifferentUnicodeBytes() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString.lowercased()
        let original = try request(id: id, article: "café"), changed = try request(id: id, article: "cafe\u{301}")
        XCTAssertEqual(original.requestID, changed.requestID)
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        let before = try Data(contentsOf: onlyFile(root)), store = Store(journal: Journal(rootDirectory: root))
        let lease = try XCTUnwrap(store.reserve(request: changed))
        let loadError = await failure { try await store.load(lease) }
        XCTAssertEqual(loadError as? Store.Failure, .changedMutation)
        let ackError = await failure { try await store.acknowledge(lease, receiptData: receipt(changed)) }
        XCTAssertEqual(ackError as? Store.Failure, .changedMutation)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), before)
    }

    func testForeignOwnerFileIsRefusedAndPreserved() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request()
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        let path = try onlyFile(root), foreign = try Codec.encode(Record(ownerUID: "reader_b"))
        try foreign.write(to: path, options: .atomic)
        let store = Store(journal: Journal(rootDirectory: root)), lease = try XCTUnwrap(store.reserve(request: original))
        let error = await failure { try await store.load(lease) }
        XCTAssertEqual(error as? Codec.Failure, .wrongOwner)
        XCTAssertEqual(try Data(contentsOf: path), foreign)
        XCTAssertTrue(store.release(lease))
    }

    func testForeignAndReleasedLeasesCannotStartPhysicalOperations() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), store = Store(journal: Journal(rootDirectory: root))
        let other = Store(journal: Journal(rootDirectory: root)), foreign = try XCTUnwrap(other.reserve(request: original))
        let foreignError = await failure { try await store.load(foreign) }
        XCTAssertEqual(foreignError as? Store.Failure, .invalidLease)
        let lease = try XCTUnwrap(store.reserve(request: original)); XCTAssertTrue(store.release(lease))
        let releasedError = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(releasedError as? Store.Failure, .invalidLease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testAcknowledgementReadbackAndRestartPreserveAllOriginalEntriesAndLegacy() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try request(epoch: 2), later = try request(epoch: 3, revision: 0, article: "next")
        let raw = try legacyBytes(), data = try receipt(first)
        let record = try Record(ownerUID: first.expectedUID).appending(first).appending(later)
            .preservingLegacy(kind: .favoritesV1, data: raw)
        try await seed(root, record)
        let store = Store(journal: Journal(rootDirectory: root)), lease = try XCTUnwrap(store.reserve(request: first))
        let accepted = try await store.acknowledge(lease, receiptData: data)
        let loaded = try await read(Journal(rootDirectory: root)), restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.entries.map(\.request), [first, later])
        XCTAssertEqual(restored.entries[0].receiptData, data); XCTAssertNil(restored.entries[1].receiptData)
        XCTAssertEqual(restored.legacySnapshots.first?.rawData, raw)
        XCTAssertEqual(accepted.receiptData, data); XCTAssertEqual(accepted.journalRevision, restored.recordRevision)
        XCTAssertEqual(accepted.receipt.committedRevision, first.expectedRevision + 1)
        XCTAssertNotEqual(accepted.journalRevision, record.recordRevision); XCTAssertTrue(store.owns(lease))
    }

    func testEquivalentReceiptRetryPreservesFirstBytesAndAvoidsAnyRewrite() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), compact = try receipt(original), formatted = try receipt(original, pretty: true)
        XCTAssertNotEqual(compact, formatted)
        let record = try Record(ownerUID: original.expectedUID).appending(original)
            .acknowledging(requestID: original.requestID, receiptData: formatted)
        try await seed(root, record)
        let probe = ReplaceProbe { _, _, _ in throw Journal.Failure.writeFailed }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let result = try await store.acknowledge(lease, receiptData: compact)
        XCTAssertEqual(result.receiptData, formatted); XCTAssertEqual(result.journalRevision, record.recordRevision)
        XCTAssertEqual(probe.count, 0); XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(record))
    }

    func testMalformedOrAnotherMutationsReceiptNeverChangesDisk() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), other = try request(article: "another")
        let record = try Record(ownerUID: original.expectedUID).appending(original)
        try await seed(root, record)
        let store = Store(journal: Journal(rootDirectory: root)), lease = try XCTUnwrap(store.reserve(request: original))
        for bytes in [Data("not a receipt".utf8), try receipt(other)] {
            let error = await failure { try await store.acknowledge(lease, receiptData: bytes) }
            XCTAssertNotNil(error); XCTAssertTrue(store.owns(lease))
            XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(record))
        }
    }

    func testFreshAcknowledgementReadRefusesSourceRemovedOrMutatedAfterLoad() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), record = try Record(ownerUID: original.expectedUID).appending(original)
        try await seed(root, record)
        let store = Store(journal: Journal(rootDirectory: root)), lease = try XCTUnwrap(store.reserve(request: original))
        _ = try await store.load(lease)
        let path = try onlyFile(root)
        let changed = try request(id: original.mutationID, article: "different")
        try Codec.encode(Record(ownerUID: original.expectedUID).appending(changed)).write(to: path, options: .atomic)
        let changedError = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(changedError as? Store.Failure, .changedMutation)
        try FileManager.default.removeItem(at: path)
        let removedError = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(removedError as? Store.Failure, .missingMutation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testBusyReservationSurvivesCancellationUntilPhysicalWriteAndReadbackReturn() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), data = try receipt(original)
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        let gate = Gate(); defer { gate.release() }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try gate.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original))
        var completed = false
        let task = Task { let result = try await store.acknowledge(lease, receiptData: data); completed = true; return result }
        let started = await Task.detached { gate.waitForStart() }.value
        XCTAssertTrue(started); task.cancel()
        XCTAssertFalse(completed); XCTAssertFalse(store.release(lease))
        XCTAssertNil(store.reserve(request: try request(owner: "reader_b")))
        let loadError = await failure { try await store.load(lease) }
        let ackError = await failure { try await store.acknowledge(lease, receiptData: data) }
        XCTAssertEqual(loadError as? Store.Failure, .busy); XCTAssertEqual(ackError as? Store.Failure, .busy)
        gate.release()
        let result = try await task.value
        XCTAssertTrue(completed); XCTAssertEqual(result.receiptData, data)
        XCTAssertTrue(store.release(lease))
        let loaded = try await read(Journal(rootDirectory: root))
        XCTAssertEqual(loaded?.entries.first?.receiptData, data)
    }

    func testFailureBeforeReplacementDoesNotRetryTransportOrLoseOriginalIntentAndSameLeaseCanRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), record = try Record(ownerUID: original.expectedUID).appending(original)
        try await seed(root, record)
        let probe = ReplaceProbe { attempt, data, url in
            if attempt == 1 { throw Journal.Failure.writeFailed }
            try data.write(to: url, options: .atomic)
        }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original)), data = try receipt(original)
        let error = await failure { try await store.acknowledge(lease, receiptData: data) }
        XCTAssertEqual(error as? Journal.Failure, .writeFailed); XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(record)); XCTAssertTrue(store.owns(lease))
        let recovered = try await store.acknowledge(lease, receiptData: data)
        XCTAssertEqual(recovered.receiptData, data); XCTAssertEqual(probe.count, 2)
    }

    func testReplacementCommittedBeforeFailureIsConfirmedByActualReadbackWithoutRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), data = try receipt(original)
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        let probe = ReplaceProbe { _, data, url in
            try data.write(to: url, options: .atomic)
            throw Journal.Failure.writeFailed
        }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let result = try await store.acknowledge(lease, receiptData: data)
        XCTAssertEqual(result.receiptData, data); XCTAssertEqual(probe.count, 1)
        XCTAssertTrue(store.release(lease))
        let restarted = Store(journal: Journal(rootDirectory: root))
        let newLease = try XCTUnwrap(restarted.reserve(request: original))
        let entry = try await restarted.load(newLease)
        XCTAssertEqual(entry.receiptData, data)
    }

    func testSuccessfulCallbackWithoutPhysicalReplacementIsNotAcknowledged() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), record = try Record(ownerUID: original.expectedUID).appending(original)
        try await seed(root, record)
        let probe = ReplaceProbe { _, _, _ in }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let error = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(error as? Store.Failure, .unconfirmedAcknowledgement); XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), try Codec.encode(record)); XCTAssertTrue(store.owns(lease))
    }

    func testReadbackFailureCannotPublishSuccessOrRecreateCorruptData() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request()
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        let corrupt = Data("corrupt-after-replace".utf8)
        let probe = ReplaceProbe { _, data, url in
            try data.write(to: url, options: .atomic)
            try corrupt.write(to: url, options: .atomic)
        }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let error = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertNotNil(error); XCTAssertEqual(probe.count, 1)
        let repeated = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertNotNil(repeated); XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), corrupt); XCTAssertTrue(store.release(lease))
    }

    func testCASConflictRebasesOnlyAcknowledgementOverCompetingAppendAndLegacy() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request(), later = try request(epoch: 3, revision: 0, article: "later")
        let record = try Record(ownerUID: original.expectedUID).appending(original)
            .preservingLegacy(kind: .favoritesV1, data: legacyBytes())
        try await seed(root, record)
        // The injected replacement boundary reports a lost CAS and persists a
        // competing valid head. All subsequent merging/readback uses real disk.
        let probe = ReplaceProbe { attempt, data, url in
            if attempt == 1 {
                let current = try Codec.decode(Data(contentsOf: url), ownerUID: original.expectedUID)
                try Codec.encode(current.appending(later)).write(to: url, options: .atomic)
                throw Journal.Failure.staleRevision
            }
            try data.write(to: url, options: .atomic)
        }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original)), data = try receipt(original)
        let accepted = try await store.acknowledge(lease, receiptData: data)
        let loaded = try await read(Journal(rootDirectory: root)), restored = try XCTUnwrap(loaded)
        XCTAssertEqual(probe.count, 2); XCTAssertEqual(restored.entries.map(\.request), [original, later])
        XCTAssertEqual(restored.entries[0].receiptData, data); XCTAssertNil(restored.entries[1].receiptData)
        XCTAssertEqual(restored.legacySnapshots, record.legacySnapshots)
        XCTAssertEqual(accepted.journalRevision, restored.recordRevision)
    }

    func testRepeatedCASConflictsAreBoundedAndPreserveEveryCompetingIntent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try request()
        try await seed(root, Record(ownerUID: original.expectedUID).appending(original))
        let competitors = try (0..<Store.maximumCASAttempts).map { try request(article: "competing-\($0)") }
        let probe = ReplaceProbe { attempt, _, url in
            let current = try Codec.decode(Data(contentsOf: url), ownerUID: original.expectedUID)
            try Codec.encode(current.appending(competitors[attempt - 1])).write(to: url, options: .atomic)
            throw Journal.Failure.staleRevision
        }
        let store = Store(journal: Journal(rootDirectory: root, replace: { try probe.replace($0, $1) }))
        let lease = try XCTUnwrap(store.reserve(request: original))
        let error = await failure { try await store.acknowledge(lease, receiptData: receipt(original)) }
        XCTAssertEqual(error as? Store.Failure, .conflictLimitReached); XCTAssertEqual(probe.count, 3)
        let loaded = try await read(Journal(rootDirectory: root)), restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.entries.map(\.request), [original] + competitors)
        XCTAssertTrue(restored.entries.allSatisfy { $0.receiptData == nil }); XCTAssertTrue(store.owns(lease))
    }

    func testTwoActualStoreInstancesAcknowledgeDifferentEntriesWithoutLosingEitherReceipt() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try request(), second = try request(article: "second")
        try await seed(root, Record(ownerUID: first.expectedUID).appending(first).appending(second))
        let one = Store(journal: Journal(rootDirectory: root)), two = Store(journal: Journal(rootDirectory: root))
        let firstLease = try XCTUnwrap(one.reserve(request: first)), secondLease = try XCTUnwrap(two.reserve(request: second))
        let firstData = try receipt(first), secondData = try receipt(second)
        async let firstACK = one.acknowledge(firstLease, receiptData: firstData)
        async let secondACK = two.acknowledge(secondLease, receiptData: secondData)
        _ = try await (firstACK, secondACK)
        let loaded = try await read(Journal(rootDirectory: root)), restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.entries.map(\.request), [first, second])
        XCTAssertEqual(restored.entries.map(\.receiptData), [firstData, secondData])
        XCTAssertTrue(one.release(firstLease)); XCTAssertTrue(two.release(secondLease))
    }

    private final class ReplaceProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private let action: @Sendable (Int, Data, URL) throws -> Void
        init(_ action: @escaping @Sendable (Int, Data, URL) throws -> Void) { self.action = action }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); calls += 1; let call = calls; lock.unlock()
            try action(call, data, url)
        }
    }
    private final class Gate: @unchecked Sendable {
        private let started = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        func waitForStart() -> Bool { started.wait(timeout: .now() + 5) == .success }
        func release() { released.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            started.signal()
            guard released.wait(timeout: .now() + 5) == .success else { throw Journal.Failure.writeFailed }
            try data.write(to: url, options: .atomic)
        }
    }
}
