import XCTest
@testable import Apropos

@MainActor
final class FavoritesFileJournalTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("favorites-journal-" + UUID().uuidString, isDirectory: true)
    }
    private func article(_ id: String = "article") -> Article {
        Article(id: id, name: "Titel", slug: id, content: "PRIVATE BODY", intro: "PRIVATE INTRO", topicID: "topic", contentRevision: "r1")
    }
    private func read(_ storage: FavoritesModel.Storage, _ namespace: FavoritesNamespace = .guest) async throws -> FavoritesRecord? {
        try await withCheckedThrowingContinuation { continuation in
            storage.read(namespace) { continuation.resume(with: $0) }
        }
    }
    private func write(_ storage: FavoritesModel.Storage, _ record: FavoritesRecord,
                       expected: UUID?, namespace: FavoritesNamespace = .guest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.write(namespace, record, expected) { continuation.resume(with: $0) }
        }
    }
    private func file(_ root: URL, _ namespace: FavoritesNamespace = .guest) -> URL {
        root.appendingPathComponent(namespace.recordBinding + ".json")
    }
    private func waitForStart(_ gate: Gate) async {
        for _ in 0..<500 where gate.starts == 0 { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertGreaterThan(gate.starts, 0, "Actual I/O did not begin")
    }

    func testConstructionIsInertAndMissingReadDoesNotCreateFiles() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = FavoritesFileJournal(rootDirectory: root)
        let storage = journal.storage
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let missing = try await read(storage)
        XCTAssertNil(missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testActualAtomicRoundTripHasLightMetadataAndCallbackAfterCommit() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = FavoritesFileJournal(rootDirectory: root).storage
        _ = try await read(storage)
        let record = FavoritesRecord(articles: [article()])
        try await write(storage, record, expected: nil)
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: file(root)), namespace: .guest), record)
        let restarted = FavoritesFileJournal(rootDirectory: root).storage
        let restored = try await read(restarted)
        XCTAssertEqual(restored, record)
        let json = String(decoding: try Data(contentsOf: file(root)), as: UTF8.self)
        XCTAssertFalse(json.contains("PRIVATE BODY")); XCTAssertFalse(json.contains("PRIVATE INTRO"))
    }

    func testWriteRequiresSuccessfulOwnerReadAndDoesNotCreateUnknownRecord() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = FavoritesFileJournal(rootDirectory: root).storage
        do { try await write(storage, .init(articles: [article()]), expected: nil); XCTFail("Unobserved overwrite") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testV1KnownOwnerMigrationCommitsV2WithoutInventingIntentsOrChangingLegacy() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = try XCTUnwrap(FavoritesContext.confirmed(userID: "known-owner").namespace)
        let metadata = try JSONSerialization.jsonObject(with: JSONEncoder().encode([FavoritesRecord.Metadata(article())]))
        let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": owner.recordBinding, "entries": metadata])
        let storage = FavoritesFileJournal(rootDirectory: root, legacyRead: { namespace in
            guard namespace == owner else { throw FavoritesJournalFailure.readFailed }; return legacy
        }).storage
        let migratedValue = try await read(storage, owner)
        let migrated = try XCTUnwrap(migratedValue)
        XCTAssertEqual(migrated.articles.map(\.id), ["article"]); XCTAssertTrue(migrated.pending.isEmpty)
        XCTAssertTrue(migrated.requiresRecovery)
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: file(root, owner)), namespace: owner), migrated)
        XCTAssertEqual(try FavoritesRecordCodec.migrateLegacyV1(legacy, namespace: owner).articles.map(\.id), ["article"])
        let new = FavoritesRecord(base: migrated.base, requiresRecovery: true)
        try await write(storage, new, expected: migrated.recordRevision, namespace: owner)
    }

    func testFailedMigrationPreservesLegacyAndDoesNotGrantWriteAdmission() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": "guest", "entries": []])
        let storage = FavoritesFileJournal(rootDirectory: root, legacyRead: { _ in legacy }, replace: { _, _ in
            throw FavoritesJournalFailure.writeFailed
        }).storage
        do { _ = try await read(storage); XCTFail("Migration committed") } catch { }
        do { try await write(storage, .empty, expected: nil); XCTFail("Unknown record admitted") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root).path))
        XCTAssertEqual(try FavoritesRecordCodec.migrateLegacyV1(legacy, namespace: .guest).base.count, 0)
    }

    func testCorruptUnknownAndForeignRecordsArePreservedWithoutBlindReplacement() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let foreign = try XCTUnwrap(FavoritesContext.confirmed(userID: "other-owner").namespace)
        let samples = [Data("broken".utf8), Data("{\"schemaVersion\":99}".utf8),
                       try FavoritesRecordCodec.encode(.empty, namespace: foreign)]
        for bytes in samples {
            try bytes.write(to: file(root))
            let storage = FavoritesFileJournal(rootDirectory: root).storage
            do { _ = try await read(storage); XCTFail("Invalid record accepted") } catch { }
            do { try await write(storage, .empty, expected: nil); XCTFail("Invalid record replaced") }
            catch { XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed) }
            XCTAssertEqual(try Data(contentsOf: file(root)), bytes)
        }
    }

    func testOversizedAndSymlinkRecordsAreRefusedAndPreserved() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = Data(repeating: 32, count: FavoritesRecordCodec.maximumRecordBytes + 1)
        try bytes.write(to: file(root))
        do { _ = try await read(FavoritesFileJournal(rootDirectory: root).storage); XCTFail("Oversize accepted") }
        catch { XCTAssertEqual(error as? FavoritesRecordCodec.Failure, .limitExceeded) }
        XCTAssertEqual(try Data(contentsOf: file(root)), bytes)
        try FileManager.default.removeItem(at: file(root))
        let target = root.appendingPathComponent("external.json"); try Data("preserve".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file(root), withDestinationURL: target)
        do { _ = try await read(FavoritesFileJournal(rootDirectory: root).storage); XCTFail("Symlink followed") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed) }
        XCTAssertEqual(try Data(contentsOf: target), Data("preserve".utf8))
    }

    func testSymlinkRootIsNotFollowed() async throws {
        let root = directory(), destination = directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: destination)
        do { _ = try await read(FavoritesFileJournal(rootDirectory: root).storage); XCTFail("Symlink root followed") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    func testCompareAndSwapRejectsStaleWriterButExactCommittedRetryIsIdempotent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = FavoritesFileJournal(rootDirectory: root).storage, second = FavoritesFileJournal(rootDirectory: root).storage
        _ = try await read(first); _ = try await read(second)
        let accepted = FavoritesRecord(articles: [article("accepted")])
        try await write(first, accepted, expected: nil)
        do { try await write(second, .init(articles: [article("stale")]), expected: nil); XCTFail("Stale writer replaced current record") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .staleRevision) }
        try await write(first, accepted, expected: nil)
        let impersonating = FavoritesRecord(recordRevision: accepted.recordRevision, base: [.init(article("other"))])
        do { try await write(first, impersonating, expected: accepted.recordRevision); XCTFail("Revision reused") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .staleRevision) }
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: file(root)), namespace: .guest), accepted)
    }

    func testFailedReplacementLeavesPriorRecordIntact() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = FavoritesRecord(articles: [article("before")])
        let initial = FavoritesFileJournal(rootDirectory: root).storage
        _ = try await read(initial); try await write(initial, original, expected: nil)
        let failing = FavoritesFileJournal(rootDirectory: root, replace: { _, _ in throw FavoritesJournalFailure.writeFailed }).storage
        _ = try await read(failing)
        do { try await write(failing, .init(articles: [article("after")]), expected: original.recordRevision); XCTFail("Replacement succeeded") }
        catch { XCTAssertEqual(error as? FavoritesJournalFailure, .writeFailed) }
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: file(root)), namespace: .guest), original)
    }

    func testHeldReplacementRunsOffMainAndRetainsOrderThroughReadBarrier() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let storage = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, $1) }).storage
        _ = try await read(storage)
        let one = FavoritesRecord(articles: [article("one")]), two = FavoritesRecord(articles: [article("two")])
        var events: [String] = []
        storage.write(.guest, one, nil) { result in if case .success = result { events.append("one") } }
        await waitForStart(gate)
        XCTAssertFalse(gate.wasMainThread); XCTAssertTrue(events.isEmpty)
        storage.write(.guest, two, one.recordRevision) { result in if case .success = result { events.append("two") } }
        let readDone = expectation(description: "Read after both commits")
        storage.read(.guest) { result in
            XCTAssertEqual(try? result.get(), two); events.append("read"); readDone.fulfill()
        }
        XCTAssertTrue(events.isEmpty)
        gate.release(); await fulfillment(of: [readDone], timeout: 5)
        XCTAssertEqual(events, ["one", "two", "read"])
    }

    func testConsecutiveQueuedWritesCoalesceLatestAndPreserveOriginalCAS() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let storage = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, $1) }).storage
        _ = try await read(storage)
        let one = FavoritesRecord(articles: [article("one")]), two = FavoritesRecord(articles: [article("two")]), three = FavoritesRecord(articles: [article("three")])
        storage.write(.guest, one, nil) { _ in }
        await waitForStart(gate)
        var superseded = false
        storage.write(.guest, two, one.recordRevision) { result in
            if case .failure(let error) = result { superseded = error as? FavoritesJournalFailure == .superseded }
        }
        let done = expectation(description: "Latest snapshot committed")
        storage.write(.guest, three, two.recordRevision) { result in
            if case .failure(let error) = result { XCTFail("Latest write failed: \(error)") }; done.fulfill()
        }
        XCTAssertTrue(superseded)
        gate.release(); await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(gate.starts, 2)
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: file(root)), namespace: .guest), three)
    }

    func testPendingCapacityRefusesAdditionalWorkWithoutReleasingHeldIO() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let storage = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, $1) }).storage
        _ = try await read(storage)
        storage.write(.guest, .empty, nil) { _ in }
        await waitForStart(gate)
        let callbacks = expectation(description: "Bounded admitted reads"); callbacks.expectedFulfillmentCount = FavoritesFileJournal.maximumPendingJobs
        for _ in 0..<FavoritesFileJournal.maximumPendingJobs { storage.read(.guest) { _ in callbacks.fulfill() } }
        var refused = false
        storage.read(.guest) { result in
            if case .failure(let error) = result { refused = error as? FavoritesRecordCodec.Failure == .limitExceeded }
        }
        XCTAssertTrue(refused); XCTAssertEqual(gate.starts, 1)
        gate.release(); await fulfillment(of: [callbacks], timeout: 5)
    }

    func testActualModelAccountReturnWaitsForRegisteredOldCommitAndRestoresIntent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let storage = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, $1) }).storage
        let model = FavoritesModel(storage: storage)
        model.changeContext(to: .confirmed(userID: "A")); _ = await model.waitForStorage()
        let original = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        await waitForStart(gate)
        model.changeContext(to: .guest)
        model.changeContext(to: .confirmed(userID: "A"))
        XCTAssertEqual(model.snapshot.state, .loading)
        XCTAssertTrue(model.snapshot.articles.isEmpty)
        gate.release(); _ = await model.waitForStorage()
        XCTAssertEqual(model.snapshot.articles.map(\.id), ["article"])
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["article"])
        let restored = try XCTUnwrap(model.pendingMutations.first)
        XCTAssertEqual(restored.id, original.id); XCTAssertNotEqual(restored.generation, original.generation)
        XCTAssertFalse(model.isCurrent(original)); XCTAssertFalse(model.snapshot.recoveryReady)
        XCTAssertFalse(model.snapshot.serverConfirmed)
    }

    func testSupersededCallbackReentryObservesReplacedQueueMetadata() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let storage = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, $1) }).storage
        _ = try await read(storage)
        let one = FavoritesRecord(articles: [article("one")]), two = FavoritesRecord(articles: [article("two")]), three = FavoritesRecord(articles: [article("three")])
        storage.write(.guest, one, nil) { _ in }
        await waitForStart(gate)
        let done = expectation(description: "Reentrant read follows replacement")
        storage.write(.guest, two, one.recordRevision) { result in
            guard case .failure(let error) = result, error as? FavoritesJournalFailure == .superseded else {
                XCTFail("Expected queued supersession"); return
            }
            storage.read(.guest) { result in
                XCTAssertEqual(try? result.get(), three); done.fulfill()
            }
        }
        storage.write(.guest, three, two.recordRevision) { result in
            if case .failure(let error) = result { XCTFail("Replacement failed: \(error)") }
        }
        gate.release(); await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(gate.starts, 2)
    }

    func testKnownNamespaceCapacityIsBoundedWithoutDroppingExistingHeads() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = FavoritesFileJournal(rootDirectory: root).storage
        for index in 0..<FavoritesFileJournal.maximumNamespaces {
            let owner = try XCTUnwrap(FavoritesContext.confirmed(userID: "owner-\(index)").namespace)
            let missing = try await read(storage, owner); XCTAssertNil(missing)
        }
        let extra = try XCTUnwrap(FavoritesContext.confirmed(userID: "extra").namespace)
        do { _ = try await read(storage, extra); XCTFail("Unbounded namespace cache") }
        catch { XCTAssertEqual(error as? FavoritesRecordCodec.Failure, .limitExceeded) }
        let first = try XCTUnwrap(FavoritesContext.confirmed(userID: "owner-0").namespace)
        try await write(storage, .empty, expected: nil, namespace: first)
    }

    func testFailedQueuedRereadRevokesAlreadyRegisteredWritePermission() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(), legacy = LegacyProbe(); defer { gate.release() }
        let storage = FavoritesFileJournal(rootDirectory: root,
            legacyRead: { namespace in if namespace == .guest { try legacy.read() }; return nil },
            replace: { try gate.replace($0, $1) }).storage
        _ = try await read(storage)
        let blocker = try XCTUnwrap(FavoritesContext.confirmed(userID: "blocker").namespace)
        _ = try await read(storage, blocker)
        storage.write(blocker, .empty, nil) { _ in }
        await waitForStart(gate)
        let readDone = expectation(description: "Failed re-read"), writeDone = expectation(description: "Revoked queued write")
        storage.read(.guest) { result in
            if case .success = result { XCTFail("Legacy read should fail") }; readDone.fulfill()
        }
        storage.write(.guest, .init(articles: [article()]), nil) { result in
            guard case .failure(let error) = result else { XCTFail("Revoked permission reused"); writeDone.fulfill(); return }
            XCTAssertEqual(error as? FavoritesJournalFailure, .readFailed); writeDone.fulfill()
        }
        gate.release(); await fulfillment(of: [readDone, writeDone], timeout: 5)
        XCTAssertEqual(gate.starts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root).path))
    }

    private final class LegacyProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func read() throws {
            lock.lock(); count += 1; let current = count; lock.unlock()
            if current > 1 { throw FavoritesJournalFailure.readFailed }
        }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var count = 0, main = false
        var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
        var wasMainThread: Bool { lock.lock(); defer { lock.unlock() }; return main }
        func release() { semaphore.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); count += 1; main = main || Thread.isMainThread; let first = count == 1; lock.unlock()
            if first, semaphore.wait(timeout: .now() + 5) != .success { throw FavoritesJournalFailure.writeFailed }
            try data.write(to: url, options: .atomic)
        }
    }
}
