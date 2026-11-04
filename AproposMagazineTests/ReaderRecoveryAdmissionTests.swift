import Foundation
import XCTest
@testable import Apropos

/// The optional recovery composition closes legacy admission without touching
/// SDKs. Actual isolated files and held callbacks prove the physical boundaries.
@MainActor
final class ReaderRecoveryAdmissionTests: XCTestCase {
    private typealias Runtime = ReaderWriterDrainRuntime
    private typealias WriterFailure = ReaderWriterDrainCoordinator.Failure

    private typealias Admission = ReaderLegacyWriteAdmission

    private final class IOProbe: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var readCounts: [FavoritesNamespace: Int] = [:]
        private var replaceCount = 0
        let legacyData: [FavoritesNamespace: Data]
        let firstReplaceStarted: XCTestExpectation?
        init(legacy: [FavoritesNamespace: Data] = [:], held: XCTestExpectation? = nil) {
            legacyData = legacy
            firstReplaceStarted = held
        }
        func read(_ namespace: FavoritesNamespace) -> Data? {
            lock.lock(); defer { lock.unlock() }
            readCounts[namespace, default: 0] += 1
            return legacyData[namespace]
        }
        func reads(_ namespace: FavoritesNamespace) -> Int {
            lock.lock(); defer { lock.unlock() }
            return readCounts[namespace, default: 0]
        }
        var replacements: Int {
            lock.lock(); defer { lock.unlock() }
            return replaceCount
        }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); replaceCount += 1; let first = replaceCount == 1; lock.unlock()
            if first, let firstReplaceStarted {
                firstReplaceStarted.fulfill()
                guard semaphore.wait(timeout: .now() + 5) == .success else { throw FavoritesJournalFailure.writeFailed }
            }
            try data.write(to: url, options: .atomic)
        }
        func release() { semaphore.signal() }
    }

    private func canonical(_ uid: String? = "reader-A") -> CanonicalSessionState {
        let value = CanonicalSessionState()
        value.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        return value
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("reader-recovery-admission-" + UUID().uuidString)
    }
    private func namespace(_ uid: String = "reader-A") throws -> FavoritesNamespace {
        try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
    }
    private func record(_ id: String) -> FavoritesRecord {
        FavoritesRecord(articles: [Article(id: id, name: "Lokal artikel", slug: id, content: "Lokal tekst", intro: "Intro", topicID: "culture")])
    }
    private func legacy(_ namespace: FavoritesNamespace) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": namespace.recordBinding,
            "entries": [["id": "legacy-story", "pressAccreditation": false]]], options: [.prettyPrinted, .sortedKeys])
    }
    private func read(_ storage: FavoritesModel.Storage, _ namespace: FavoritesNamespace) async throws -> FavoritesRecord? {
        try await withCheckedThrowingContinuation { continuation in
            storage.read(namespace) { continuation.resume(with: $0) }
        }
    }
    private func write(_ storage: FavoritesModel.Storage, _ namespace: FavoritesNamespace,
                       _ record: FavoritesRecord, expected: UUID?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.write(namespace, record, expected) { continuation.resume(with: $0) }
        }
    }
    private func assertFrozen(_ operation: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Closed legacy admission accepted work", file: file, line: line) }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen, file: file, line: line) }
    }

    func testConstructionDoesNotReadAdmissionIdentitySDKOrDisk() {
        let admission = Admission(), state = canonical(), root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var identities = 0, factories = 0
        let runtime = Runtime(canonical: state, actualUID: { identities += 1; return "reader-A" }, makeDrain: {
            factories += 1
            return .init(wait: { $0(nil) })
        }, legacyAdmission: admission)
        let journal = FavoritesFileJournal(rootDirectory: root, legacyAdmission: admission)
        _ = journal.storage
        XCTAssertTrue(runtime.isPhysicallyIdle)
        XCTAssertFalse(admission.isAllowed)
        XCTAssertEqual(identities, 0)
        XCTAssertEqual(factories, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testUnknownRuntimeAdmissionBlocksUntilExplicitlyAllowed() async throws {
        let admission = Admission(), state = canonical()
        var writes = 0
        let runtime = Runtime(canonical: state, actualUID: { "reader-A" }, makeDrain: { .init(wait: { $0(nil) }) },
            legacyAdmission: admission)
        let start: Runtime.Start = { permitted, complete in
            guard permitted() else { complete(CancellationError()); return }
            writes += 1
            complete(nil)
        }
        do {
            try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: start)
            XCTFail("Unknown startup state admitted a write")
        } catch { XCTAssertEqual(error as? WriterFailure, .stopped) }
        XCTAssertEqual(writes, 0)
        admission.setAllowed(true)
        try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: start)
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(runtime.isPhysicallyIdle)
    }

    func testClosedGateRejectsDelayedSDKEnqueueAndKeepsPhysicalCallbackOwned() async throws {
        let admission = Admission(), state = canonical()
        admission.setAllowed(true)
        let runtime = Runtime(canonical: state, actualUID: { "reader-A" }, makeDrain: { .init(wait: { $0(nil) }) },
            legacyAdmission: admission)
        let entered = expectation(description: "Adapter owns physical callback")
        var guardSDK: Runtime.Guard?, callback: Runtime.Completion?
        var finished = false
        let task = Task { @MainActor in
            defer { finished = true }
            do {
                try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { last, complete in
                    guardSDK = last; callback = complete; entered.fulfill()
                })
                XCTFail("Rejected delayed write reported success")
            } catch { }
        }
        await fulfillment(of: [entered], timeout: 3)
        admission.setAllowed(false)
        XCTAssertFalse(try XCTUnwrap(guardSDK)())
        XCTAssertFalse(finished)
        XCTAssertFalse(runtime.isPhysicallyIdle)
        admission.setAllowed(true)
        XCTAssertFalse(try XCTUnwrap(guardSDK)(), "An attempt that observed closure must not revive")
        try XCTUnwrap(callback)(CancellationError())
        await task.value
        XCTAssertTrue(finished)
        XCTAssertTrue(runtime.isPhysicallyIdle)
    }

    func testCallerReentryClosingAdmissionRejectsBeforeAdapterStarts() async {
        let admission = Admission(), state = canonical()
        admission.setAllowed(true)
        var starts = 0
        let runtime = Runtime(canonical: state, actualUID: { "reader-A" }, makeDrain: { .init(wait: { $0(nil) }) },
            legacyAdmission: admission)
        do {
            try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: {
                admission.setAllowed(false)
                return true
            }, start: { _, complete in starts += 1; complete(nil) })
            XCTFail("Caller hook closed recovery admission")
        } catch { }
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(runtime.isPhysicallyIdle)
    }

    func testLastIdentityHookCannotCloseAdmissionAndStillStartSDK() async {
        let admission = Admission(), state = canonical()
        admission.setAllowed(true)
        var closeOnIdentityRead = false, writes = 0
        let runtime = Runtime(canonical: state, actualUID: {
            if closeOnIdentityRead { admission.setAllowed(false) }
            return "reader-A"
        }, makeDrain: { .init(wait: { $0(nil) }) }, legacyAdmission: admission)
        do {
            try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { permitted, complete in
                closeOnIdentityRead = true
                guard permitted() else { complete(CancellationError()); return }
                writes += 1; complete(nil)
            })
            XCTFail("Identity getter closed admission at the final enqueue guard")
        } catch { }
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(runtime.isPhysicallyIdle)
    }

    func testCallerReentryCannotAdoptAnotherAccountForOriginalWrite() async {
        let admission = Admission(isAllowed: true), state = canonical()
        var starts = 0
        let runtime = Runtime(canonical: state, actualUID: { state.contextTicket().userID }, makeDrain: { .init(wait: { $0(nil) }) },
            legacyAdmission: admission)
        do {
            try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: {
                state.adopt(.init(uid: "reader-B", email: "b@example.invalid", isEmailVerified: true))
                return true
            }, start: { _, complete in
                starts += 1; complete(nil)
            })
            XCTFail("Original account changed inside caller guard")
        } catch { }
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(state.contextTicket().userID, "reader-B")
    }

    func testClosedAdmissionStillAllowsExplicitDrainButNeverGuestSDKWrites() async throws {
        let admission = Admission(), state = canonical()
        var drains = 0
        let runtime = Runtime(canonical: state, actualUID: { state.contextTicket().userID }, schedule: { _ in {} }, makeDrain: {
            .init(wait: { complete in drains += 1; complete(nil) })
        }, legacyAdmission: admission)
        let stop = try XCTUnwrap(runtime.stopWrites(context: state.contextTicket()))
        let receipt = try await runtime.drain(stop)
        XCTAssertTrue(runtime.isCurrent(receipt))
        XCTAssertEqual(drains, 1)
        XCTAssertFalse(admission.isAllowed, "Drain must remain available during closed startup recovery")
        state.adopt(nil)
        admission.setAllowed(true)
        do {
            try await runtime.performWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { _, complete in
                XCTFail("Guest must not enqueue account SDK writes"); complete(nil)
            })
            XCTFail("Guest adopted account write")
        } catch { }
    }

    func testClosedFileGateRejectsGuestAndAccountReadWriteWithoutMigrationThenAllowsExplicitOpen() async throws {
        let root = directory(), admission = Admission(), owner = try namespace()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IOProbe(legacy: [owner: try legacy(owner)])
        let journal = FavoritesFileJournal(rootDirectory: root, legacyRead: { probe.read($0) },
            replace: { try probe.replace($0, $1) }, legacyAdmission: admission)
        for current in [FavoritesNamespace.guest, owner] {
            await assertFrozen { _ = try await self.read(journal.storage, current) }
            await assertFrozen { try await self.write(journal.storage, current, self.record("new"), expected: nil) }
            XCTAssertEqual(probe.reads(current), 0)
        }
        XCTAssertEqual(probe.replacements, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        admission.setAllowed(true)
        let readResult = try await read(journal.storage, owner)
        let loaded = try XCTUnwrap(readResult)
        XCTAssertEqual(loaded.base.map(\.id), ["legacy-story"])
        let replacement = record("new")
        try await write(journal.storage, owner, replacement, expected: loaded.recordRevision)
        XCTAssertEqual(probe.replacements, 2)
        let persisted = try await read(journal.storage, owner)
        XCTAssertEqual(persisted, replacement)
    }

    func testGateClosingRejectsQueuedMigrationAndWriteAfterHeldPhysicalWriteReturns() async throws {
        let root = directory(), admission = Admission(), owner = try namespace(), other = try namespace("reader-B")
        defer { try? FileManager.default.removeItem(at: root) }
        admission.setAllowed(true)
        let started = expectation(description: "First actual file replacement held")
        let probe = IOProbe(legacy: [other: try legacy(other)], held: started)
        defer { probe.release() }
        let journal = FavoritesFileJournal(rootDirectory: root, legacyRead: { probe.read($0) },
            replace: { try probe.replace($0, $1) }, legacyAdmission: admission)
        _ = try await read(journal.storage, owner)
        let original = record("before-close"), later = record("must-not-write")
        let returned = expectation(description: "All original callbacks retain their queue order")
        returned.expectedFulfillmentCount = 3
        var order: [String] = []
        journal.storage.write(owner, original, nil) { result in
            if case .failure(let error) = result { XCTFail("Already physical write failed: \(error)") }
            order.append("physical"); returned.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        journal.storage.read(other) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen) }
            else { XCTFail("Queued legacy migration ran after closure") }
            order.append("read"); returned.fulfill()
        }
        journal.storage.write(owner, later, original.recordRevision) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen) }
            else { XCTFail("Queued legacy write ran after closure") }
            order.append("write"); returned.fulfill()
        }
        admission.setAllowed(false)
        XCTAssertTrue(order.isEmpty)
        probe.release()
        await fulfillment(of: [returned], timeout: 3)
        XCTAssertEqual(order, ["physical", "read", "write"])
        XCTAssertEqual(probe.reads(other), 0)
        XCTAssertEqual(probe.replacements, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(other.recordBinding + ".json").path))
        let bytes = try Data(contentsOf: root.appendingPathComponent(owner.recordBinding + ".json"))
        XCTAssertEqual(try FavoritesRecordCodec.decode(bytes, namespace: owner), original)
    }

    func testExplicitSnapshotPreservesBothRawFormatsWhileLegacyAdmissionIsClosed() async throws {
        let root = directory(), admission = Admission(), owner = try namespace()
        defer { try? FileManager.default.removeItem(at: root) }
        let rawV1 = try legacy(owner), rawV2 = try FavoritesRecordCodec.encode(record("v2-story"), namespace: owner)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(owner.recordBinding + ".json")
        try rawV2.write(to: file)
        let probe = IOProbe(legacy: [owner: rawV1])
        let journal = FavoritesFileJournal(rootDirectory: root, legacyRead: { probe.read($0) },
            replace: { try probe.replace($0, $1) }, legacyAdmission: admission)
        let snapshot: FavoritesFileJournal.SnapshotLease = try await withCheckedThrowingContinuation { continuation in
            journal.freezeForTransition(namespace: owner) { continuation.resume(with: $0) }
        }
        XCTAssertEqual(snapshot.rawV1, rawV1)
        XCTAssertEqual(snapshot.rawV2, rawV2)
        XCTAssertTrue(journal.isCurrent(snapshot))
        XCTAssertFalse(admission.isAllowed)
        XCTAssertEqual(probe.replacements, 0)
        XCTAssertEqual(try Data(contentsOf: file), rawV2)
    }

    func testDefaultAdmissionPreservesGuestFileBehaviorWithoutRecoveryComposition() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = FavoritesFileJournal(rootDirectory: root)
        let missing = try await read(journal.storage, .guest)
        XCTAssertNil(missing)
        let original = record("guest-story")
        try await write(journal.storage, .guest, original, expected: nil)
        let restored = try await read(journal.storage, .guest)
        XCTAssertEqual(restored, original)
    }
}
