import XCTest
@testable import Apropos

/// Real temporary-file/serial-queue tests. Source freezing preserves old data;
/// it does not grant membership, migrate an epoch or stop another journal.
@MainActor
final class FavoritesJournalTransitionTests: XCTestCase {
    private typealias Journal = FavoritesFileJournal
    private typealias Ticket = Journal.TransitionTicket
    private typealias Lease = Journal.SnapshotLease

    func testMissingSnapshotDoesNotCreateDirectoryOrGrantOrdinaryWriteReadiness() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), journal = Journal(rootDirectory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let (ticket, lease) = try await freeze(journal, owner)
        XCTAssertNil(lease.rawV1); XCTAssertNil(lease.rawV2)
        XCTAssertTrue(journal.isCurrent(lease))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(journal.resumeAfterAbortedTransition(ticket))
        do { try await write(journal.storage, owner, .empty, expected: nil); XCTFail("Snapshot granted a normal read head") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed) }
    }

    func testGuestFreezeReturnsNilAndExactlyOneFailureWithoutChangingGuestStorage() async throws {
        let root = directory(); defer { remove(root) }
        let journal = Journal(rootDirectory: root)
        var callbacks = 0
        let ticket = journal.freezeForTransition(namespace: .guest) { result in
            callbacks += 1
            guard case .failure(let error) = result else { XCTFail("Guest was adopted"); return }
            XCTAssertEqual(error as? Journal.TransitionFailure, .invalidTicket)
        }
        XCTAssertNil(ticket); XCTAssertEqual(callbacks, 1)
        let value = try await read(journal.storage, .guest)
        XCTAssertNil(value)
    }

    func testV1OnlySnapshotPreservesOriginalBytesWithoutFallbackMigration() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), raw = try v1(namespace())
        let probe = LegacyBox(raw)
        let journal = Journal(rootDirectory: root, legacyRead: { _ in probe.read() })
        let (_, lease) = try await freeze(journal, owner)
        XCTAssertEqual(lease.rawV1, raw); XCTAssertNil(lease.rawV2)
        XCTAssertFalse(probe.wasMainThread, "Snapshot must read/validate away from MainActor")
        XCTAssertEqual(probe.read(), raw)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testBothRawVersionsKeepFormattingIntentIDsAndPendingAcknowledgementPhases() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), rawV1 = try v1(namespace())
        let started = FavoritesRecord.Pending(intentID: UUID(), payload: .init(article("started")), enabled: true,
                                              phase: .started, attemptID: UUID())
        let acknowledged = FavoritesRecord.Pending(intentID: UUID(), payload: .init(article("ack")), enabled: false,
                                                   phase: .acknowledged, attemptID: UUID())
        let original = FavoritesRecord(base: [], pending: [started, acknowledged], requiresRecovery: true)
        let rawV2 = try formatted(original, owner)
        try install(rawV2, root: root, owner: owner)
        let journal = Journal(rootDirectory: root, legacyRead: { _ in rawV1 })
        let (_, lease) = try await freeze(journal, owner)
        XCTAssertEqual(lease.rawV1, rawV1); XCTAssertEqual(lease.rawV2, rawV2)
        let restored = try FavoritesRecordCodec.decode(try XCTUnwrap(lease.rawV2), namespace: owner)
        XCTAssertEqual(restored.recordRevision, original.recordRevision)
        XCTAssertEqual(restored.pending.map(\.intentID), original.pending.map(\.intentID))
        XCTAssertEqual(restored.pending.map(\.phase), original.pending.map(\.phase))
        XCTAssertEqual(try Data(contentsOf: file(root, owner)), rawV2)
    }

    func testFreezeRejectsNewWorkSynchronouslyButDrainsAcceptedCoalescedWritesAndCallbackReentry() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, replace: { try gate.replace($0, $1) }), storage = journal.storage
        _ = try await read(storage, owner)
        let one = FavoritesRecord(articles: [article("one")])
        let two = FavoritesRecord(articles: [article("two")])
        let three = FavoritesRecord(articles: [article("three")])
        var order: [String] = [], reentrantRefused = false
        storage.write(owner, one, nil) { result in
            if case .failure(let error) = result { XCTFail("First accepted write failed: \(error)") }
            order.append("one")
            storage.write(owner, .empty, one.recordRevision) { late in
                if case .failure(let error) = late { reentrantRefused = error as? Journal.TransitionFailure == .frozen }
            }
        }
        await waitForStart(gate)
        var superseded = false
        storage.write(owner, two, one.recordRevision) { result in
            if case .failure(let error) = result { superseded = error as? FavoritesJournalFailure == .superseded }
        }
        storage.write(owner, three, two.recordRevision) { result in
            if case .failure(let error) = result { XCTFail("Coalesced accepted write failed: \(error)") }
            order.append("three")
        }
        let done = expectation(description: "Snapshot follows accepted source commits")
        var result: Result<Lease, Error>?
        let ticket = try XCTUnwrap(journal.freezeForTransition(namespace: owner) {
            result = $0; order.append("snapshot"); done.fulfill()
        })
        XCTAssertTrue(superseded)
        XCTAssertFalse(journal.canResumeAfterAbortedTransition(ticket))
        assertFrozen(storage, owner)
        gate.release(); await fulfillment(of: [done], timeout: 5)
        let lease = try XCTUnwrap(result).get()
        XCTAssertEqual(order, ["one", "three", "snapshot"])
        XCTAssertTrue(reentrantRefused)
        XCTAssertEqual(try FavoritesRecordCodec.decode(try XCTUnwrap(lease.rawV2), namespace: owner), three)
        XCTAssertEqual(gate.starts, 2)
        XCTAssertTrue(journal.isCurrent(lease))
    }

    func testReadAcceptedBeforeFreezeMayFinishItsExistingMigrationBeforeRawSnapshot() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), rawV1 = try v1(namespace()), gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, legacyRead: { _ in try gate.holdOnce(); return rawV1 })
        let readDone = expectation(description: "Previously admitted legacy read")
        journal.storage.read(owner) { result in
            if case .failure(let error) = result { XCTFail("Previously admitted read failed: \(error)") }
            readDone.fulfill()
        }
        await waitForStart(gate)
        let snapshotDone = expectation(description: "Snapshot after prior migration")
        var result: Result<Lease, Error>?
        let ticket = journal.freezeForTransition(namespace: owner) { result = $0; snapshotDone.fulfill() }
        XCTAssertNotNil(ticket); assertFrozen(journal.storage, owner)
        gate.release(); await fulfillment(of: [readDone, snapshotDone], timeout: 5)
        let lease = try XCTUnwrap(result).get()
        XCTAssertEqual(lease.rawV1, rawV1)
        XCTAssertEqual(lease.rawV2, try Data(contentsOf: file(root, owner)))
        XCTAssertNotNil(lease.rawV2)
    }

    func testMalformedWrongOwnerAndOversizedV2FailClosedWithoutFallbackOrReplacement() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), other = try namespace("B"), rawV1 = try v1(namespace())
        let samples = [Data("broken".utf8), Data("{\"schemaVersion\":99}".utf8),
                       try FavoritesRecordCodec.encode(.empty, namespace: other),
                       Data(repeating: 32, count: FavoritesRecordCodec.maximumRecordBytes + 1)]
        for raw in samples {
            try install(raw, root: root, owner: owner)
            let journal = Journal(rootDirectory: root, legacyRead: { _ in rawV1 })
            let (ticket, result) = await freezeResult(journal, owner)
            XCTAssertNotNil(ticket)
            if case .success = result { XCTFail("Invalid v2 produced a lease") }
            assertFrozen(journal.storage, owner)
            XCTAssertEqual(try Data(contentsOf: file(root, owner)), raw)
        }
    }

    func testValidV2CannotHideCorruptForeignOrOversizedV1() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), rawV2 = try formatted(.empty, namespace())
        try install(rawV2, root: root, owner: owner)
        let samples = [Data("bad v1".utf8), try v1(namespace("B")),
                       Data(repeating: 32, count: FavoritesRecordCodec.maximumRecordBytes + 1)]
        for rawV1 in samples {
            let journal = Journal(rootDirectory: root, legacyRead: { _ in rawV1 })
            let (_, result) = await freezeResult(journal, owner)
            if case .success = result { XCTFail("Invalid v1 was hidden by valid v2") }
            assertFrozen(journal.storage, owner)
            XCTAssertEqual(try Data(contentsOf: file(root, owner)), rawV2)
        }
    }

    func testSourceSymlinkIsNotFollowedAndBytesRemainUntouched() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("external.json"), bytes = try formatted(.empty, owner)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: file(root, owner), withDestinationURL: target)
        let journal = Journal(rootDirectory: root)
        let (_, result) = await freezeResult(journal, owner)
        if case .success = result { XCTFail("Symlink followed") }
        assertFrozen(journal.storage, owner)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testFailedSnapshotCanRetryOnlyOriginalTicketAndRemainsClosedBetweenAttempts() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), box = LegacyBox(Data("invalid".utf8))
        let journal = Journal(rootDirectory: root, legacyRead: { _ in box.read() })
        let (value, result) = await freezeResult(journal, owner), ticket = try XCTUnwrap(value)
        if case .success = result { XCTFail("Invalid source accepted") }
        assertFrozen(journal.storage, owner)
        let valid = try v1(owner); box.set(valid)
        let lease = try await retry(journal, ticket)
        XCTAssertEqual(lease.rawV1, valid)
        XCTAssertTrue(journal.isCurrent(lease))
        assertFrozen(journal.storage, owner)
    }

    func testExplicitAbortAfterFailedSnapshotReopensWithoutFabricatingLease() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), box = LegacyBox(Data("invalid".utf8))
        let journal = Journal(rootDirectory: root, legacyRead: { _ in box.read() })
        let (value, _) = await freezeResult(journal, owner), ticket = try XCTUnwrap(value)
        XCTAssertTrue(journal.canResumeAfterAbortedTransition(ticket))
        XCTAssertTrue(journal.resumeAfterAbortedTransition(ticket))
        XCTAssertFalse(journal.resumeAfterAbortedTransition(ticket))
        box.set(nil)
        let missing = try await read(journal.storage, owner)
        XCTAssertNil(missing)
        try await write(journal.storage, owner, .empty, expected: nil)
    }

    func testForeignJournalCannotAcceptSnapshotTicketOrResumeAnotherInstance() async throws {
        let root = directory(), secondRoot = directory(); defer { remove(root); remove(secondRoot) }
        let owner = try namespace(), first = Journal(rootDirectory: root), second = Journal(rootDirectory: secondRoot)
        let (ticket, lease) = try await freeze(first, owner)
        XCTAssertFalse(second.isCurrent(lease))
        XCTAssertFalse(second.canResumeAfterAbortedTransition(ticket))
        XCTAssertFalse(second.resumeAfterAbortedTransition(ticket))
        do { _ = try await retry(second, ticket); XCTFail("Foreign ticket accepted") }
        catch { XCTAssertEqual(error as? Journal.TransitionFailure, .invalidTicket) }
        XCTAssertTrue(first.isCurrent(lease)); assertFrozen(first.storage, owner)
    }

    func testFreshIdleFreezeReplacesTokenAndInvalidatesEveryOldLeaseAndAbortHandle() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), journal = Journal(rootDirectory: root)
        let (oldTicket, oldLease) = try await freeze(journal, owner)
        let (newTicket, newLease) = try await freeze(journal, owner)
        XCTAssertNotEqual(oldTicket, newTicket)
        XCTAssertFalse(journal.isCurrent(oldLease)); XCTAssertTrue(journal.isCurrent(newLease))
        XCTAssertFalse(journal.resumeAfterAbortedTransition(oldTicket))
        do { _ = try await retry(journal, oldTicket); XCTFail("Old action revived") }
        catch { XCTAssertEqual(error as? Journal.TransitionFailure, .invalidTicket) }
        XCTAssertTrue(journal.resumeAfterAbortedTransition(newTicket))
    }

    func testBusyFreezeCannotBeReplacedOrAbortedUntilItsPhysicalSnapshotReturns() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, legacyRead: { _ in try gate.holdOnce(); return nil })
        let done = expectation(description: "Original snapshot completed")
        var lease: Lease?
        let original = try XCTUnwrap(journal.freezeForTransition(namespace: owner) { lease = try? $0.get(); done.fulfill() })
        await waitForStart(gate)
        var refusals = 0
        let rejected = journal.freezeForTransition(namespace: owner) { result in
            if case .failure = result { refusals += 1 }
        }
        XCTAssertNil(rejected); XCTAssertEqual(refusals, 1)
        XCTAssertFalse(journal.canResumeAfterAbortedTransition(original))
        XCTAssertFalse(journal.resumeAfterAbortedTransition(original))
        gate.release(); await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(journal.isCurrent(try XCTUnwrap(lease)))
        XCTAssertTrue(journal.resumeAfterAbortedTransition(original))
    }

    func testRetryInvalidatesPriorLeaseBeforeItsQueuedPhysicalRead() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), journal = Journal(rootDirectory: root)
        let (ticket, first) = try await freeze(journal, owner)
        let done = expectation(description: "Fresh retry snapshot")
        var latest: Lease?
        journal.retryTransitionSnapshot(ticket) { latest = try? $0.get(); done.fulfill() }
        XCTAssertFalse(journal.isCurrent(first))
        XCTAssertFalse(journal.resumeAfterAbortedTransition(ticket))
        await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(journal.isCurrent(try XCTUnwrap(latest)))
    }

    func testQueueFullFreezeStillClosesSourceAndOriginalTicketCanRetryAfterDrain() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), gate = Gate(); defer { gate.release() }
        let journal = Journal(rootDirectory: root, replace: { try gate.replace($0, $1) }), storage = journal.storage
        _ = try await read(storage, owner)
        storage.write(owner, .empty, nil) { _ in }
        await waitForStart(gate)
        let drained = expectation(description: "All previously accepted reads complete")
        drained.expectedFulfillmentCount = Journal.maximumPendingJobs
        for _ in 0..<Journal.maximumPendingJobs { storage.read(owner) { _ in drained.fulfill() } }
        var callbackCount = 0
        let ticket = try XCTUnwrap(journal.freezeForTransition(namespace: owner) { result in
            callbackCount += 1
            guard case .failure(let error) = result else { XCTFail("Overfilled queue admitted snapshot"); return }
            XCTAssertEqual(error as? FavoritesRecordCodec.Failure, .limitExceeded)
        })
        XCTAssertEqual(callbackCount, 1); assertFrozen(storage, owner)
        XCTAssertFalse(journal.resumeAfterAbortedTransition(ticket))
        gate.release(); await fulfillment(of: [drained], timeout: 5)
        let lease = try await retry(journal, ticket)
        XCTAssertNotNil(lease.rawV2); XCTAssertTrue(journal.isCurrent(lease))
    }

    func testFreezingOneNamespaceLeavesOtherOwnersUnchanged() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), other = try namespace("B"), journal = Journal(rootDirectory: root)
        let (_, lease) = try await freeze(journal, owner)
        _ = try await read(journal.storage, other)
        let record = FavoritesRecord(articles: [article("B-only")])
        try await write(journal.storage, other, record, expected: nil)
        XCTAssertTrue(journal.isCurrent(lease))
        assertFrozen(journal.storage, owner)
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: file(root, other)), namespace: other), record)
    }

    func testSnapshotCallbackReentryCannotKeepEarlierLeaseCurrent() async throws {
        let root = directory(); defer { remove(root) }
        let owner = try namespace(), journal = Journal(rootDirectory: root)
        let done = expectation(description: "Reentrant new transition")
        var oldLease: Lease?, newLease: Lease?
        journal.freezeForTransition(namespace: owner) { first in
            oldLease = try? first.get()
            journal.freezeForTransition(namespace: owner) { second in newLease = try? second.get(); done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertFalse(journal.isCurrent(try XCTUnwrap(oldLease)))
        XCTAssertTrue(journal.isCurrent(try XCTUnwrap(newLease)))
    }

    private func namespace(_ uid: String = "A") throws -> FavoritesNamespace {
        try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
    }
    private func article(_ id: String) -> Article {
        Article(id: id, name: "Original æøå", slug: id, content: "", intro: "", topicID: "culture", contentRevision: "r1")
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("favorites-transition-" + UUID().uuidString)
    }
    private func remove(_ root: URL) { try? FileManager.default.removeItem(at: root) }
    private func file(_ root: URL, _ owner: FavoritesNamespace) -> URL { root.appendingPathComponent(owner.recordBinding + ".json") }
    private func install(_ data: Data, root: URL, owner: FavoritesNamespace) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: file(root, owner))
    }
    private func formatted(_ record: FavoritesRecord, _ owner: FavoritesNamespace) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: FavoritesRecordCodec.encode(record, namespace: owner))
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
    private func v1(_ owner: FavoritesNamespace) throws -> Data {
        let entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode([FavoritesRecord.Metadata(article("legacy"))]))
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": owner.recordBinding,
            "entries": entries], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
    private func freezeResult(_ journal: Journal, _ owner: FavoritesNamespace) async -> (Ticket?, Result<Lease, Error>) {
        var ticket: Ticket?
        let result: Result<Lease, Error> = await withCheckedContinuation { continuation in
            ticket = journal.freezeForTransition(namespace: owner) { continuation.resume(returning: $0) }
        }
        return (ticket, result)
    }
    private func freeze(_ journal: Journal, _ owner: FavoritesNamespace) async throws -> (Ticket, Lease) {
        let (ticket, result) = await freezeResult(journal, owner)
        return (try XCTUnwrap(ticket), try result.get())
    }
    private func retry(_ journal: Journal, _ ticket: Ticket) async throws -> Lease {
        try await withCheckedThrowingContinuation { continuation in
            journal.retryTransitionSnapshot(ticket) { continuation.resume(with: $0) }
        }
    }
    private func read(_ storage: FavoritesModel.Storage, _ owner: FavoritesNamespace) async throws -> FavoritesRecord? {
        try await withCheckedThrowingContinuation { continuation in storage.read(owner) { continuation.resume(with: $0) } }
    }
    private func write(_ storage: FavoritesModel.Storage, _ owner: FavoritesNamespace, _ record: FavoritesRecord,
                       expected: UUID?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.write(owner, record, expected) { continuation.resume(with: $0) }
        }
    }
    private func assertFrozen(_ storage: FavoritesModel.Storage, _ owner: FavoritesNamespace,
                              file: StaticString = #filePath, line: UInt = #line) {
        var count = 0
        storage.read(owner) { result in
            count += 1
            guard case .failure(let error) = result else { XCTFail("Frozen read admitted", file: file, line: line); return }
            XCTAssertEqual(error as? Journal.TransitionFailure, .frozen, file: file, line: line)
        }
        storage.write(owner, .empty, nil) { result in
            count += 1
            guard case .failure(let error) = result else { XCTFail("Frozen write admitted", file: file, line: line); return }
            XCTAssertEqual(error as? Journal.TransitionFailure, .frozen, file: file, line: line)
        }
        XCTAssertEqual(count, 2, "Admission must close synchronously", file: file, line: line)
    }
    private func waitForStart(_ gate: Gate) async {
        let started = await Task.detached { gate.waitForStart() }.value
        XCTAssertTrue(started)
    }
    private final class LegacyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?
        private var main = false
        init(_ value: Data?) { self.value = value }
        var wasMainThread: Bool { lock.lock(); defer { lock.unlock() }; return main }
        func read() -> Data? { lock.lock(); defer { lock.unlock() }; main = main || Thread.isMainThread; return value }
        func set(_ value: Data?) { lock.lock(); defer { lock.unlock() }; self.value = value }
    }
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock(), started = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0)
        private var count = 0
        var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
        func waitForStart() -> Bool { started.wait(timeout: .now() + 5) == .success }
        func release() { released.signal() }
        func holdOnce() throws {
            lock.lock(); count += 1; let first = count == 1; lock.unlock()
            if first {
                started.signal()
                guard released.wait(timeout: .now() + 10) == .success else { throw FavoritesJournalFailure.readFailed }
            }
        }
        func replace(_ data: Data, _ url: URL) throws { try holdOnce(); try data.write(to: url, options: .atomic) }
    }
}
