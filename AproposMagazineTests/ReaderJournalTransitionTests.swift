import Foundation
import XCTest
@testable import Apropos

/// Real source/target journals and ownership coordinators, isolated temporary
/// files and injected physical callbacks. No Firebase or production store starts.
@MainActor
final class ReaderJournalTransitionTests: XCTestCase {
    private typealias Transition = ReaderJournalTransition
    private typealias Record = ReaderMutationJournalRecord
    private typealias Callback = ReaderWriterDrainCoordinator.Completion
    private enum InjectedFailure: Error { case read, replace }

    private final class PhysicalGate: @unchecked Sendable {
        let started: XCTestExpectation
        private let semaphore = DispatchSemaphore(value: 0)
        init(_ started: XCTestExpectation) { self.started = started }
        func wait() throws {
            started.fulfill()
            guard semaphore.wait(timeout: .now() + 5) == .success else { throw InjectedFailure.replace }
        }
        func release() { semaphore.signal() }
    }

    private final class DiskProbe: @unchecked Sendable {
        enum Mode: Equatable { case normal, failBefore, commitThenFail }
        private let lock = NSLock()
        private var storedLegacy: Data?
        private var storedMode = Mode.normal
        private var storedReplacements = 0
        private var storedGate: PhysicalGate?
        init(_ legacy: Data? = nil) { storedLegacy = legacy }
        var replacements: Int { lock.lock(); defer { lock.unlock() }; return storedReplacements }
        func legacy() -> Data? { lock.lock(); defer { lock.unlock() }; return storedLegacy }
        func setLegacy(_ data: Data?) { lock.lock(); storedLegacy = data; lock.unlock() }
        func setMode(_ mode: Mode) { lock.lock(); storedMode = mode; lock.unlock() }
        func setGate(_ gate: PhysicalGate?) { lock.lock(); storedGate = gate; lock.unlock() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); storedReplacements += 1; let mode = storedMode, gate = storedGate; lock.unlock()
            try gate?.wait()
            if mode == .failBefore { throw InjectedFailure.replace }
            try data.write(to: url, options: .atomic)
            if mode == .commitThenFail { throw InjectedFailure.replace }
        }
    }
    @MainActor private final class Pending {
        let finished: XCTestExpectation
        var result: Result<Transition.Receipt, Error>?
        var task: Task<Void, Never>?
        init(_ finished: XCTestExpectation) { self.finished = finished }
    }
    @MainActor private final class Fixture {
        let root: URL
        let sourceRoot: URL
        let targetRoot: URL
        let canonical = CanonicalSessionState()
        let membership: ReaderMembershipAuthority
        let namespace: FavoritesNamespace
        let rawV1: Data
        let rawV2: Data
        let sourceProbe: DiskProbe
        let targetProbe = DiskProbe()
        let source: FavoritesFileJournal
        let journal: ReaderMutationFileJournal
        var uid: String? = "reader-A"
        var identityHook: (() -> Void)?
        var identityReads = 0
        var drains: [Callback] = []
        var deadlines: [@MainActor () -> Void] = []
        var drainStarted: XCTestExpectation?
        lazy var writers = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [unowned self] in
            self.identityReads += 1; self.identityHook?(); return self.uid
        }, schedule: { [unowned self] action in
            self.deadlines.append(action); return {}
        }, makeDrain: { [unowned self] in
            .init(wait: { [unowned self] completion in
                self.drains.append(completion)
                let waiting = self.drainStarted; self.drainStarted = nil; waiting?.fulfill()
            })
        })
        lazy var model = Transition(canonical: canonical, membership: membership, writers: writers,
                                    source: source, journal: journal)
        var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
        var sourceFile: URL { sourceRoot.appendingPathComponent(namespace.recordBinding + ".json") }

        init(root: URL? = nil, seed: Bool = true) throws {
            let root = root ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("reader-transition-" + UUID().uuidString, isDirectory: true)
            self.root = root
            sourceRoot = root.appendingPathComponent("source", isDirectory: true)
            targetRoot = root.appendingPathComponent("target", isDirectory: true)
            namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-A").namespace)
            rawV1 = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
                "namespace": namespace.recordBinding, "entries": [["id": "legacy-v1", "pressAccreditation": false]]],
                options: [.prettyPrinted, .sortedKeys])
            let metadata = try JSONDecoder().decode(FavoritesRecord.Metadata.self,
                from: Data(#"{"id":"legacy-v2","pressAccreditation":false}"#.utf8))
            rawV2 = try FavoritesRecordCodec.encode(.init(base: [], pending: [
                .init(intentID: UUID(), payload: metadata, enabled: true, phase: .acknowledged, attemptID: UUID())
            ], requiresRecovery: true), namespace: namespace)
            sourceProbe = DiskProbe(rawV1)
            let sourceProbe = sourceProbe, targetProbe = targetProbe
            source = FavoritesFileJournal(rootDirectory: sourceRoot, legacyRead: { _ in sourceProbe.legacy() },
                                          replace: { try sourceProbe.replace($0, $1) })
            journal = ReaderMutationFileJournal(rootDirectory: targetRoot, replace: { try targetProbe.replace($0, $1) })
            membership = ReaderMembershipAuthority(canonical: canonical)
            select("reader-A")
            if seed {
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
                try rawV2.write(to: sourceFile)
            }
        }
        func select(_ uid: String?, force: Bool = false) {
            self.uid = uid
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: "reader@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: force)
        }
        @discardableResult func acceptMembership(_ epoch: Int64 = 7) throws -> ReaderMembershipContract.Binding {
            let uid = try XCTUnwrap(context.userID)
            let record = try ReaderMembershipContract.decode(data: JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "ownerUID": uid, "epoch": epoch, "state": "active"
            ]), expectedUID: uid)
            let read = try XCTUnwrap(membership.beginRead(for: context))
            XCTAssertTrue(membership.completeRead(read, record: record, isFromCache: false, hasPendingWrites: false))
            return record.binding
        }
        func begin(_ epoch: Int64 = 7) throws -> Transition.Operation {
            let binding = try acceptMembership(epoch)
            return try XCTUnwrap(model.begin(context: context, binding: binding))
        }
    }

    private func launch(_ f: Fixture, _ operation: Transition.Operation, retry: Bool = false) -> Pending {
        let pending = Pending(expectation(description: "Physical preparation returns"))
        pending.task = Task { @MainActor in
            do {
                let receipt: Transition.Receipt
                if retry { receipt = try await f.model.retryPreservation(operation) }
                else { receipt = try await f.model.prepare(operation) }
                pending.result = .success(receipt)
            }
            catch { pending.result = .failure(error) }
            pending.finished.fulfill()
        }
        return pending
    }
    private func awaitingDrain(_ f: Fixture, _ operation: Transition.Operation, retry: Bool = false) async -> Pending {
        let started = expectation(description: "Original SDK drain was actually invoked")
        f.drainStarted = started
        let pending = launch(f, operation, retry: retry)
        await fulfillment(of: [started], timeout: 5)
        return pending
    }
    private func finish(_ pending: Pending) async throws -> Transition.Receipt {
        await fulfillment(of: [pending.finished], timeout: 5)
        return try XCTUnwrap(pending.result).get()
    }
    private func failed(_ pending: Pending, file: StaticString = #filePath, line: UInt = #line) async {
        await fulfillment(of: [pending.finished], timeout: 5)
        guard case .failure = pending.result else { return XCTFail("Preparation must fail", file: file, line: line) }
    }
    private func read(_ journal: ReaderMutationFileJournal, owner: String = "reader-A") async throws -> Record? {
        let done = expectation(description: "Actual journal read returns")
        var result: Result<Record?, Error>?
        journal.read(ownerUID: owner) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        return try XCTUnwrap(result).get()
    }
    private func write(_ journal: ReaderMutationFileJournal, _ record: Record, expected: UUID?) async throws {
        let done = expectation(description: "Actual journal write returns")
        var result: Result<Void, Error>?
        journal.write(record, expectedRevision: expected) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        _ = try XCTUnwrap(result).get()
    }
    private func sourceRead(_ f: Fixture) async throws -> FavoritesRecord? {
        let done = expectation(description: "Source storage read returns")
        var result: Result<FavoritesRecord?, Error>?
        f.source.storage.read(f.namespace) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        return try XCTUnwrap(result).get()
    }
    private func assertBothOpen(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        let old = try await sourceRead(f)
        let next = FavoritesRecord(base: old?.base ?? [], pending: old?.pending ?? [], requiresRecovery: old?.requiresRecovery ?? false)
        let done = expectation(description: "Source write after explicit abort returns")
        var result: Result<Void, Error>?
        f.source.storage.write(f.namespace, next, old?.recordRevision) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        _ = try XCTUnwrap(result, file: file, line: line).get()
        var enqueued = false
        try await f.writers.performWrite(expectedUserID: "reader-A", stillCurrent: { true }) { permitted, complete in
            XCTAssertTrue(permitted(), file: file, line: line); enqueued = true; complete(nil)
        }
        XCTAssertTrue(enqueued, file: file, line: line)
    }
    private func assertBothClosed(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await sourceRead(f); XCTFail("Frozen source admitted read", file: file, line: line) }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen, file: file, line: line) }
        do {
            try await f.writers.performWrite(expectedUserID: "reader-A", stillCurrent: { true }) { _, completion in
                XCTFail("Stopped runtime enqueued write", file: file, line: line); completion(nil)
            }
            XCTFail("Stopped runtime returned success", file: file, line: line)
        } catch { XCTAssertEqual(error as? ReaderWriterDrainCoordinator.Failure, .stopped, file: file, line: line) }
    }
    private func abortAfterQueuedCallback(_ f: Fixture, _ operation: Transition.Operation) async {
        // Yield only to the manually delivered callback's actor hop. This is a
        // bounded observation of that event, not an arbitrary sleep/deadline.
        let done = expectation(description: "Abort succeeds after physical drain callback")
        var reopened = false
        Task { @MainActor in
            for _ in 0..<1_000 {
                if f.model.abort(operation) { reopened = true; break }
                await Task.yield()
            }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(reopened)
    }
    private func receipt(_ request: ReaderMutationContract.Request) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "scope": ReaderMutationContract.scope,
            "requestID": request.requestID, "status": "committed", "committedRevision": request.expectedRevision + 1,
            "request": try JSONSerialization.jsonObject(with: ReaderMutationContract.encode(request))], options: [.prettyPrinted, .sortedKeys])
    }

    func testConstructionAndBeginRequireExplicitOriginalServerMembership() throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let binding = try ReaderMembershipContract.Binding(ownerUID: "reader-A", epoch: 7)
        XCTAssertFalse(f.model.isBusy); XCTAssertFalse(f.model.isSealed)
        XCTAssertEqual(f.identityReads, 0); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertNil(f.model.begin(context: f.context, binding: binding))
        _ = try f.acceptMembership()
        let wrongEpoch = try ReaderMembershipContract.Binding(ownerUID: "reader-A", epoch: 8)
        let wrongOwner = try ReaderMembershipContract.Binding(ownerUID: "reader-B", epoch: 7)
        XCTAssertNil(f.model.begin(context: f.context, binding: wrongEpoch))
        XCTAssertNil(f.model.begin(context: f.context, binding: wrongOwner))
        XCTAssertNotNil(f.model.begin(context: f.context, binding: binding))
        XCTAssertTrue(f.drains.isEmpty); XCTAssertEqual(f.sourceProbe.replacements, 0)
        XCTAssertEqual(f.targetProbe.replacements, 0)
    }

    func testSuccessfulPreparationPreservesBothRawFormatsWithoutConvertingOrOverwritingSource() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let guestFile = f.sourceRoot.appendingPathComponent("guest.json"), guestBytes = Data("untouched guest".utf8)
        try guestBytes.write(to: guestFile)
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        XCTAssertTrue(f.model.isBusy); XCTAssertFalse(f.model.abort(operation))
        try XCTUnwrap(f.drains.first)(nil)
        let received = try await finish(pending)
        XCTAssertTrue(f.model.isCurrent(received)); XCTAssertTrue(f.model.isSealed)
        XCTAssertFalse(f.model.abort(operation)); XCTAssertEqual(received.operation.binding, operation.binding)
        let loaded = try await read(f.journal), stored = try XCTUnwrap(loaded)
        XCTAssertTrue(stored.entries.isEmpty); XCTAssertTrue(stored.unacknowledgedEntries.isEmpty)
        XCTAssertEqual(stored.legacySnapshots.map(\.kind), [.favoritesV1, .favoritesV2])
        XCTAssertEqual(stored.legacySnapshots.map(\.rawData), [f.rawV1, f.rawV2])
        XCTAssertEqual(received.journalRevision, stored.recordRevision)
        XCTAssertEqual(try Data(contentsOf: f.sourceFile), f.rawV2)
        XCTAssertEqual(f.sourceProbe.legacy(), f.rawV1)
        XCTAssertEqual(try Data(contentsOf: guestFile), guestBytes)
        XCTAssertEqual(f.sourceProbe.replacements, 0)
        await assertBothClosed(f)
    }

    func testExistingOriginalEpochRequestsAndHistoricalReceiptRemainByteExact() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let first = try ReaderMutationContract.Request(binding: .init(ownerUID: "reader-A", epoch: 2),
            mutationID: UUID().uuidString.lowercased(), expectedRevision: 9, payload: .favoriteRemove(articleID: "cafe\u{301}"))
        let second = try ReaderMutationContract.Request(binding: .init(ownerUID: "reader-A", epoch: 3),
            mutationID: UUID().uuidString.lowercased(), expectedRevision: 4, payload: .favoriteRemove(articleID: "café"))
        let oldReceipt = try receipt(first)
        let original = try Record(ownerUID: "reader-A").appending(first).appending(second)
            .acknowledging(requestID: first.requestID, receiptData: oldReceipt)
        _ = try await read(f.journal); try await write(f.journal, original, expected: nil)
        let foreign = try Record(ownerUID: "reader-B")
        _ = try await read(f.journal, owner: "reader-B"); try await write(f.journal, foreign, expected: nil)
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        f.drains[0](nil); _ = try await finish(pending)
        let loaded = try await read(f.journal), stored = try XCTUnwrap(loaded)
        XCTAssertEqual(stored.entries.map(\.request.membershipEpoch), [2, 3])
        XCTAssertEqual(stored.entries.map(\.request.expectedRevision), [9, 4])
        XCTAssertEqual(try stored.entries.map { try ReaderMutationContract.encode($0.request) },
                       try original.entries.map { try ReaderMutationContract.encode($0.request) })
        XCTAssertEqual(stored.entries[0].receiptData, oldReceipt); XCTAssertNil(stored.entries[1].receiptData)
        let stillForeign = try await read(f.journal, owner: "reader-B")
        XCTAssertEqual(stillForeign, foreign)
    }

    func testPrematureAbortAndPreWriteSnapshotFailureReopenBothOriginalGatesExplicitly() async throws {
        for invalidSnapshot in [false, true] {
            let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let operation = try f.begin()
            if invalidSnapshot {
                f.sourceProbe.setLegacy(Data("damaged original v1".utf8))
                let pending = launch(f, operation); await failed(pending)
                XCTAssertFalse(f.model.isSealed); XCTAssertTrue(f.drains.isEmpty)
                await assertBothClosed(f)
                f.sourceProbe.setLegacy(f.rawV1)
            }
            XCTAssertTrue(f.model.abort(operation)); XCTAssertFalse(f.model.abort(operation))
            XCTAssertEqual(f.targetProbe.replacements, 0)
            try await assertBothOpen(f)
        }
    }

    func testHeldDrainPreventsAbortAndTimeoutDoesNotAutomaticallyReopen() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        XCTAssertFalse(f.model.abort(operation)); XCTAssertTrue(f.model.isBusy)
        try XCTUnwrap(f.deadlines.first)(); await failed(pending)
        XCTAssertFalse(f.model.isBusy); XCTAssertFalse(f.model.isSealed)
        XCTAssertFalse(f.model.abort(operation)); await assertBothClosed(f)
        f.drains[0](nil)
        await abortAfterQueuedCallback(f, operation)
        XCTAssertEqual(f.targetProbe.replacements, 0)
        try await assertBothOpen(f)
    }

    func testCancelledPreparationCannotWriteTargetAndStillWaitsForPhysicalDrainBeforeAbort() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        pending.task?.cancel(); await failed(pending)
        XCTAssertFalse(f.model.abort(operation)); XCTAssertFalse(f.model.isSealed)
        XCTAssertEqual(f.targetProbe.replacements, 0)
        f.drains[0](nil); await abortAfterQueuedCallback(f, operation)
        XCTAssertEqual(f.targetProbe.replacements, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.targetRoot.path))
        try await assertBothOpen(f)
    }

    func testAccountRoundTripCannotContinueOldPreparationOrReuseItsPhysicalDrain() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try f.begin(), pending = await awaitingDrain(f, original)
        f.select("reader-B"); f.select("reader-A")
        await failed(pending)
        XCTAssertFalse(f.model.abort(original)); XCTAssertFalse(f.model.discardInvalidPreparation(original))
        let newBinding = try f.acceptMembership(8)
        XCTAssertNil(f.model.begin(context: f.context, binding: newBinding), "Old physical drain still occupies the shared slot")
        XCTAssertEqual(f.targetProbe.replacements, 0)
        f.drains[0](nil)
        let released = expectation(description: "Fresh operation waits for original physical callback")
        var fresh: Transition.Operation?
        Task { @MainActor in
            for _ in 0..<1_000 {
                if f.model.discardInvalidPreparation(original),
                   let value = f.model.begin(context: f.context, binding: newBinding) { fresh = value; break }
                await Task.yield()
            }
            released.fulfill()
        }
        await fulfillment(of: [released], timeout: 5)
        let current = try XCTUnwrap(fresh), retry = await awaitingDrain(f, current)
        XCTAssertNotEqual(current, original); XCTAssertEqual(f.drains.count, 2)
        f.drains[1](nil); let receipt = try await finish(retry)
        XCTAssertEqual(receipt.operation.binding.epoch, 8); XCTAssertTrue(f.model.isCurrent(receipt))
        let loaded = try await read(f.journal), stored = try XCTUnwrap(loaded)
        XCTAssertTrue(stored.entries.isEmpty, "Epochless legacy intents never become epoch-8 requests")
    }

    func testTargetFailureOrCommittedButUnknownOutcomeSealsAbortPermanently() async throws {
        for mode in [DiskProbe.Mode.failBefore, .commitThenFail] {
            let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            f.targetProbe.setMode(mode)
            let operation = try f.begin(), pending = await awaitingDrain(f, operation)
            f.drains[0](nil); await failed(pending)
            XCTAssertTrue(f.model.isSealed); XCTAssertFalse(f.model.isBusy)
            XCTAssertFalse(f.model.abort(operation)); XCTAssertFalse(f.model.discardInvalidPreparation(operation))
            XCTAssertEqual(f.targetProbe.replacements, 1); await assertBothClosed(f)
            let persisted = try await read(ReaderMutationFileJournal(rootDirectory: f.targetRoot))
            if mode == .commitThenFail {
                XCTAssertEqual(persisted?.legacySnapshots.map(\.rawData), [f.rawV1, f.rawV2])
            } else { XCTAssertNil(persisted) }
        }
    }

    func testMembershipInvalidationPreventsLaterTargetWriteAndRevokesCompletedReceipt() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        f.membership.invalidate(); f.drains[0](nil); await failed(pending)
        XCTAssertEqual(f.targetProbe.replacements, 0); XCTAssertFalse(f.model.abort(operation))
        XCTAssertTrue(f.model.discardInvalidPreparation(operation)); await assertBothClosed(f)
        let next = try f.begin(8), retry = await awaitingDrain(f, next)
        f.drains[1](nil); let receipt = try await finish(retry)
        XCTAssertTrue(f.model.isCurrent(receipt))
        _ = try XCTUnwrap(f.membership.beginRead(for: f.context))
        XCTAssertFalse(f.model.isCurrent(receipt), "Even pending server revalidation revokes the captured write lease")
    }

    func testRestartReadsOriginalFilesButRequiresNewMembershipSnapshotAndPhysicalDrain() async throws {
        let first = try Fixture(); defer { try? FileManager.default.removeItem(at: first.root) }
        let operation = try first.begin(), pending = await awaitingDrain(first, operation)
        first.drains[0](nil); let oldReceipt = try await finish(pending)
        let originalRead = try await read(first.journal), originalFile = try XCTUnwrap(originalRead)
        let restarted = try Fixture(root: first.root, seed: false)
        XCTAssertFalse(restarted.model.isCurrent(oldReceipt)); XCTAssertTrue(restarted.drains.isEmpty)
        XCTAssertNil(restarted.model.begin(context: restarted.context, binding: operation.binding))
        let fresh = try restarted.begin(), retry = await awaitingDrain(restarted, fresh)
        XCTAssertNil(retry.result); XCTAssertEqual(restarted.targetProbe.replacements, 0)
        restarted.drains[0](nil); let receipt = try await finish(retry)
        XCTAssertTrue(restarted.model.isCurrent(receipt)); XCTAssertFalse(restarted.model.isCurrent(oldReceipt))
        let restoredRead = try await read(restarted.journal), restored = try XCTUnwrap(restoredRead)
        XCTAssertEqual(try ReaderMutationJournalCodec.encode(restored), try ReaderMutationJournalCodec.encode(originalFile))
        XCTAssertEqual(restarted.targetProbe.replacements, 0, "Exact preservation retry must not replace the existing journal")
    }

    func testCompletedReceiptRechecksSourceAfterIdentityGetterReentersSnapshot() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        f.drains[0](nil); let receipt = try await finish(pending)
        let snapshotDone = expectation(description: "Reentrant source snapshot finishes")
        f.identityHook = { [unowned f] in
            f.identityHook = nil
            f.source.freezeForTransition(namespace: f.namespace) { _ in snapshotDone.fulfill() }
        }
        XCTAssertFalse(f.model.isCurrent(receipt), "The old source lease changed inside the runtime receipt check")
        await fulfillment(of: [snapshotDone], timeout: 5)
        XCTAssertFalse(f.model.isCurrent(receipt), "The replacement snapshot cannot revive an old receipt")
        XCTAssertEqual(f.targetProbe.replacements, 1)
    }

    func testReentrantSourceInvalidationAroundDrainReturnPreventsFutureTargetWrite() async throws {
        // Exercise each identity-check boundary between physical return and the
        // first model source recheck, rather than relying on one magic index.
        for boundary in 1...4 {
            let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let operation = try f.begin(), pending = await awaitingDrain(f, operation)
            let snapshotDone = expectation(description: "Reentrant snapshot boundary \(boundary)")
            var remaining = boundary, invalidated = false
            f.identityHook = { [unowned f] in
                remaining -= 1
                guard remaining == 0 else { return }
                f.identityHook = nil; invalidated = true
                f.source.freezeForTransition(namespace: f.namespace) { _ in snapshotDone.fulfill() }
            }
            f.drains[0](nil); await failed(pending)
            await fulfillment(of: [snapshotDone], timeout: 5)
            XCTAssertTrue(invalidated); XCTAssertEqual(f.targetProbe.replacements, 0)
            XCTAssertFalse(f.model.isSealed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.targetRoot.path))
        }
    }

    func testExplicitRetryAfterCommittedButLostAcknowledgementDrainsAgainAndPreservesExactBytes() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.targetProbe.setMode(.commitThenFail)
        let operation = try f.begin(), pending = await awaitingDrain(f, operation)
        f.drains[0](nil); await failed(pending)
        XCTAssertTrue(f.model.isSealed); XCTAssertFalse(f.model.abort(operation))
        let oldRead = try await read(f.journal), original = try XCTUnwrap(oldRead)
        let originalBytes = try ReaderMutationJournalCodec.encode(original)
        XCTAssertEqual(f.targetProbe.replacements, 1)
        f.targetProbe.setMode(.normal)
        let retry = await awaitingDrain(f, operation, retry: true)
        XCTAssertTrue(f.model.isSealed); XCTAssertNil(retry.result)
        XCTAssertEqual(f.drains.count, 2); XCTAssertEqual(f.targetProbe.replacements, 1)
        f.drains[1](nil); let receipt = try await finish(retry)
        XCTAssertTrue(f.model.isCurrent(receipt)); XCTAssertEqual(receipt.operation, operation)
        XCTAssertEqual(receipt.operation.binding.epoch, 7)
        let restoredRead = try await read(f.journal), restored = try XCTUnwrap(restoredRead)
        XCTAssertEqual(try ReaderMutationJournalCodec.encode(restored), originalBytes)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertEqual(f.targetProbe.replacements, 1, "Exact retry cannot replace the committed original journal")
        XCTAssertFalse(f.model.abort(operation)); await assertBothClosed(f)
    }

    func testSharedRuntimeExcludesSecondTransitionWhileOriginalTargetWriteIsPhysicallyPending() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let gate = PhysicalGate(expectation(description: "Original target replacement is physically held"))
        defer { gate.release() }
        f.targetProbe.setGate(gate)
        let original = try f.begin()
        let second = Transition(canonical: f.canonical, membership: f.membership, writers: f.writers,
                                source: f.source, journal: f.journal)
        XCTAssertNil(second.begin(context: f.context, binding: original.binding), "Shared ownership is reserved at begin")
        let pending = await awaitingDrain(f, original)
        f.drains[0](nil); await fulfillment(of: [gate.started], timeout: 5)
        XCTAssertTrue(f.model.isBusy); XCTAssertTrue(f.model.isSealed)
        XCTAssertNil(second.begin(context: f.context, binding: original.binding))
        XCTAssertFalse(second.abort(original)); XCTAssertFalse(f.model.abort(original))
        await assertBothClosed(f)
        gate.release(); let receipt = try await finish(pending)
        XCTAssertTrue(f.model.isCurrent(receipt)); XCTAssertFalse(second.isCurrent(receipt))
        XCTAssertNil(second.begin(context: f.context, binding: original.binding))
    }

    func testDiscardedSealedPreparationCannotBeReopenedThroughFreshTransitionOwner() async throws {
        let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.targetProbe.setMode(.commitThenFail)
        let original = try f.begin(), pending = await awaitingDrain(f, original)
        f.drains[0](nil); await failed(pending)
        XCTAssertTrue(f.model.isSealed)
        f.membership.invalidate()
        XCTAssertTrue(f.model.discardInvalidPreparation(original))
        let binding = try f.acceptMembership(8)
        let second = Transition(canonical: f.canonical, membership: f.membership, writers: f.writers,
                                source: f.source, journal: f.journal)
        let fresh = try XCTUnwrap(second.begin(context: f.context, binding: binding))
        XCTAssertNotEqual(fresh, original)
        XCTAssertFalse(second.abort(fresh), "Shared irreversible seal survives a new private action/epoch")
        await assertBothClosed(f)
        XCTAssertEqual(f.targetProbe.replacements, 1)
    }
}
