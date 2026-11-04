import Combine
import Foundation
import XCTest
@testable import Apropos

/// Actual reader controller/store, with local storage and recovery only. A
/// storage drain confirms physical return, not successful persistence or fsync.
@MainActor
final class ReaderResumeRecoveryDrainTests: XCTestCase {
    private let ownerA = "account_" + String(repeating: "a", count: 64)
    private let ownerB = "account_" + String(repeating: "b", count: 64)
    private func source(_ id: String = "article") -> ReaderResumeIdentity {
        ReaderResumeIdentity(articleID: id, sourceRevision: "v1", html: "<p>Original reading source.</p>")!
    }
    private func anchor(_ index: Int) -> ReaderResumeAnchor { .init(index: index, fingerprint: "1234abcd") }
    private func data(owner: String, index: Int) throws -> Data {
        try ReaderResumeRecord.encode(.init(entries: [.init(owner: owner, source: source(), anchor: anchor(index))]))
    }
    @discardableResult
    private func bind(_ controller: ReaderResumeController, owner: String? = nil,
                      current: @escaping @MainActor () -> Bool = { true }) -> String {
        let document = UUID().uuidString
        controller.bind(owner: owner ?? ownerA, source: source(), sessionID: UUID(), documentID: document, isCurrent: current)
        return document
    }

    func testClosedAdmissionRejectsBindCaptureAndCurrentHookWithoutStorage() async {
        let memory = RecoveryResumeMemory(), store = ReaderResumeStore(storage: memory.storage)
        let admission = ReaderLegacyWriteAdmission()
        let controller = ReaderResumeController(store: store, legacyAdmission: admission)
        var currentCalls = 0
        let document = bind(controller) { currentCalls += 1; return true }
        controller.record(anchor(5), completed: false, documentID: document)
        controller.resume { _, _, _, _ in XCTFail("Closed reader must not request a scroll") }
        await controller.waitForPendingWork()
        XCTAssertEqual(currentCalls, 0)
        XCTAssertEqual(memory.readCount, 0); XCTAssertEqual(memory.writeCount, 0)
        XCTAssertEqual(controller.snapshot, .init())
    }

    func testAdmissionClosingInsideBindHookPreventsFirstRead() async {
        let memory = RecoveryResumeMemory(), store = ReaderResumeStore(storage: memory.storage)
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let controller = ReaderResumeController(store: store, legacyAdmission: admission)
        var currentCalls = 0
        bind(controller) { currentCalls += 1; admission.setAllowed(false); return true }
        await controller.waitForPendingWork()
        XCTAssertEqual(currentCalls, 1)
        XCTAssertEqual(memory.readCount, 0); XCTAssertEqual(memory.writeCount, 0)
        XCTAssertEqual(controller.snapshot, .init())
    }

    func testRecordRechecksAdmissionAfterCurrentHookAndDeniedBindingCannotRevive() async throws {
        let memory = RecoveryResumeMemory(), store = ReaderResumeStore(storage: memory.storage)
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let controller = ReaderResumeController(store: store, legacyAdmission: admission)
        var closeInHook = false
        let original = bind(controller) { if closeInHook { admission.setAllowed(false) }; return true }
        await controller.waitForPendingWork()
        closeInHook = true
        controller.record(anchor(4), completed: false, documentID: original)
        XCTAssertEqual(memory.writeCount, 0)
        closeInHook = false; admission.setAllowed(true)
        controller.record(anchor(5), completed: false, documentID: original)
        await store.waitForPhysicalIdle()
        XCTAssertEqual(memory.writeCount, 0, "Reopening a local gate cannot resurrect the denied capture")
        let fresh = bind(controller)
        await controller.waitForPendingWork()
        controller.record(anchor(8), completed: false, documentID: fresh)
        await controller.waitForPendingWork()
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(8)); XCTAssertEqual(memory.writeCount, 1)
    }

    func testLateLoadCannotPublishAfterRecoveryClosesAdmission() async throws {
        let began = expectation(description: "Original read entered physical storage")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let memory = RecoveryResumeMemory(data: try data(owner: ownerA, index: 6),
            heldRead: 1, readGate: gate, readStarted: { began.fulfill() })
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let controller = ReaderResumeController(store: ReaderResumeStore(storage: memory.storage), legacyAdmission: admission)
        bind(controller)
        await fulfillment(of: [began], timeout: 2)
        admission.setAllowed(false); gate.signal()
        await controller.waitForPendingWork()
        XCTAssertEqual(controller.snapshot, .init())
        admission.setAllowed(true)
        XCTAssertEqual(controller.snapshot, .init(), "A rejected original read remains rejected")
        XCTAssertEqual(memory.readCount, 1); XCTAssertEqual(memory.writeCount, 0)
    }

    func testSynchronousPublicationSubscriberCanCloseGateBeforeOfferCommit() async throws {
        let memory = RecoveryResumeMemory(data: try data(owner: ownerA, index: 6))
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let controller = ReaderResumeController(store: ReaderResumeStore(storage: memory.storage), legacyAdmission: admission)
        var revoked = false
        let observation = controller.objectWillChange.sink {
            if memory.readCount > 0 { revoked = true; admission.setAllowed(false) }
        }
        bind(controller)
        await controller.waitForPendingWork()
        XCTAssertTrue(revoked)
        XCTAssertEqual(controller.snapshot, .init())
        XCTAssertEqual(memory.writeCount, 0)
        withExtendedLifetime(observation) { }
    }

    func testCapturedResumePermissionAndLateCompletionStayDeniedAfterGateCloses() async throws {
        let initial = try data(owner: ownerA, index: 6), memory = RecoveryResumeMemory(data: initial)
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let controller = ReaderResumeController(store: ReaderResumeStore(storage: memory.storage), legacyAdmission: admission)
        let document = bind(controller)
        await controller.waitForPendingWork()
        var permitted: (@MainActor () -> Bool)?, completion: (@MainActor (Bool) -> Void)?
        controller.resume { _, _, isCurrent, done in permitted = isCurrent; completion = done }
        XCTAssertTrue(try XCTUnwrap(permitted)())
        admission.setAllowed(false)
        XCTAssertFalse(try XCTUnwrap(permitted)())
        completion?(false)
        controller.record(anchor(9), completed: false, documentID: document)
        XCTAssertEqual(controller.snapshot, .init())
        admission.setAllowed(true)
        completion?(true)
        XCTAssertFalse(try XCTUnwrap(permitted)())
        XCTAssertEqual(memory.bytes, initial); XCTAssertEqual(memory.writeCount, 0)
    }

    func testOldCaptureAfterAToBToADoesNotBorrowFreshGateOrDocument() async throws {
        let memory = RecoveryResumeMemory(data: try data(owner: ownerA, index: 6))
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let store = ReaderResumeStore(storage: memory.storage)
        let controller = ReaderResumeController(store: store, legacyAdmission: admission)
        let oldA = bind(controller)
        await controller.waitForPendingWork()
        var originalPermission: (@MainActor () -> Bool)?, originalCompletion: (@MainActor (Bool) -> Void)?
        controller.resume { _, _, permitted, done in originalPermission = permitted; originalCompletion = done }
        admission.setAllowed(false)
        XCTAssertFalse(try XCTUnwrap(originalPermission)())
        admission.setAllowed(true)
        let b = bind(controller, owner: ownerB)
        await controller.waitForPendingWork()
        controller.record(anchor(7), completed: false, documentID: b)
        let freshA = bind(controller)
        await controller.waitForPendingWork()
        controller.record(anchor(8), completed: false, documentID: freshA)
        controller.record(anchor(11), completed: false, documentID: oldA)
        originalCompletion?(false)
        await controller.waitForPendingWork()
        XCTAssertFalse(try XCTUnwrap(originalPermission)())
        XCTAssertNil(controller.snapshot.message)
        let savedA = try await store.load(owner: ownerA, source: source())
        let savedB = try await store.load(owner: ownerB, source: source())
        XCTAssertEqual(savedA, anchor(8)); XCTAssertEqual(savedB, anchor(7))
    }

    func testAcceptedControllerWriteSurvivesDetachAndCancelledDrainWithoutTouchingGuestOrB() async throws {
        let began = expectation(description: "Accepted original write started")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let original = try ReaderResumeRecord.encode(.init(entries: [
            .init(owner: ownerB, source: source(), anchor: anchor(7)),
            .init(owner: "guest", source: source(), anchor: anchor(9))]))
        let memory = RecoveryResumeMemory(data: original, heldWrite: 1, writeGate: gate, writeStarted: { began.fulfill() })
        let store = ReaderResumeStore(storage: memory.storage), admission = ReaderLegacyWriteAdmission(isAllowed: true)
        let controller = ReaderResumeController(store: store, legacyAdmission: admission)
        let document = bind(controller)
        await controller.waitForPendingWork()
        controller.record(anchor(5), completed: false, documentID: document)
        await fulfillment(of: [began], timeout: 2)
        admission.setAllowed(false); controller.invalidate()
        controller.record(anchor(12), completed: false, documentID: document)
        let earlyReturn = expectation(description: "Cancelled drain cannot finish during physical write")
        earlyReturn.isInverted = true
        let observation = ResumeDrainObservation()
        let drain = Task { await store.waitForPhysicalIdle(); observation.returned = true; if observation.checkingEarly { earlyReturn.fulfill() } }
        drain.cancel()
        await fulfillment(of: [earlyReturn], timeout: 0.05)
        XCTAssertFalse(observation.returned)
        observation.checkingEarly = false; gate.signal(); await drain.value
        XCTAssertTrue(observation.returned); XCTAssertEqual(memory.writeCount, 1)
        let entries = try ReaderResumeRecord.decode(memory.bytes).entries
        XCTAssertEqual(entries.first { $0.owner == ownerA }?.anchor, anchor(5))
        XCTAssertEqual(entries.first { $0.owner == ownerB }?.anchor, anchor(7))
        XCTAssertEqual(entries.first { $0.owner == "guest" }?.anchor, anchor(9))
        XCTAssertEqual(controller.snapshot, .init())
    }

    func testDrainWaitsForActualReadbackEvenWhenReceiptAndDrainTasksAreCancelled() async throws {
        let began = expectation(description: "Write readback is physically held")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let memory = RecoveryResumeMemory(heldRead: 2, readGate: gate, readStarted: { began.fulfill() })
        let store = ReaderResumeStore(storage: memory.storage)
        let receipt = try store.accept(owner: ownerA, source: source(), anchor: anchor(5))
        await fulfillment(of: [began], timeout: 2)
        let waitingReceipt = Task { try await receipt.value() }
        let earlyReturn = expectation(description: "Readback owns the physical slot")
        earlyReturn.isInverted = true
        let observation = ResumeDrainObservation()
        let drain = Task { await store.waitForPhysicalIdle(); observation.returned = true; if observation.checkingEarly { earlyReturn.fulfill() } }
        waitingReceipt.cancel(); drain.cancel()
        await fulfillment(of: [earlyReturn], timeout: 0.05)
        XCTAssertFalse(observation.returned); XCTAssertEqual(memory.writeCount, 1)
        observation.checkingEarly = false; gate.signal()
        try await waitingReceipt.value; await drain.value
        XCTAssertTrue(observation.returned); XCTAssertEqual(memory.readCount, 2)
    }

    func testFullAdmissionQueueCannotRejectPhysicalDrain() async throws {
        let began = expectation(description: "Full queue's first physical write")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let memory = RecoveryResumeMemory(heldWrite: 1, writeGate: gate, writeStarted: { began.fulfill() })
        let store = ReaderResumeStore(storage: memory.storage)
        var receipts = [try store.accept(owner: ownerA, source: source("article-0"), anchor: anchor(1))]
        await fulfillment(of: [began], timeout: 2)
        for index in 1..<ReaderResumeStore.maximumPendingOperations {
            receipts.append(try store.accept(owner: ownerA, source: source("article-\(index)"), anchor: anchor(index + 1)))
        }
        XCTAssertThrowsError(try store.accept(owner: ownerA, source: source("overflow"), anchor: anchor(2))) {
            XCTAssertEqual($0 as? ReaderResumeStore.Failure, .capacityExceeded)
        }
        let drain = Task { await store.waitForPhysicalIdle() }
        drain.cancel(); gate.signal(); await drain.value
        XCTAssertEqual(memory.writeCount, ReaderResumeStore.maximumPendingOperations)
        for receipt in receipts { try await receipt.value() }
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).entries.count, ReaderResumeStore.maximumPendingOperations)
    }

    func testDrainWaitsForAcceptedReadFailureAndDoesNotTurnItIntoSuccess() async throws {
        let began = expectation(description: "Accepted read held before failure")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let memory = RecoveryResumeMemory(heldRead: 1, readGate: gate, readStarted: { began.fulfill() }, failingReads: [1])
        let store = ReaderResumeStore(storage: memory.storage), owner = ownerA, item = source()
        let load = Task { try await store.load(owner: owner, source: item) }
        await fulfillment(of: [began], timeout: 2)
        let earlyReturn = expectation(description: "A held failing read must still physically return")
        earlyReturn.isInverted = true
        let observation = ResumeDrainObservation()
        let drain = Task { await store.waitForPhysicalIdle(); observation.returned = true; if observation.checkingEarly { earlyReturn.fulfill() } }
        load.cancel(); drain.cancel()
        await fulfillment(of: [earlyReturn], timeout: 0.05)
        XCTAssertFalse(observation.returned)
        observation.checkingEarly = false; gate.signal(); await drain.value
        do { _ = try await load.value; XCTFail("Original read failure was replaced by success") }
        catch { XCTAssertEqual(error as? RecoveryResumeMemory.Failure, .read) }
        XCTAssertEqual(memory.writeCount, 0); XCTAssertNil(memory.bytes)
    }

    func testActualRecoverySealRevokesExistingControllerWhileOriginalWriteDrains() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-resume-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = ReaderTransitionRecovery(store: ReaderTransitionRecoveryStore(rootDirectory: root))
        try await recovery.bootstrap()
        let began = expectation(description: "Original reader write before actual recovery seal")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let memory = RecoveryResumeMemory(heldWrite: 1, writeGate: gate, writeStarted: { began.fulfill() })
        let store = ReaderResumeStore(storage: memory.storage)
        let controller = ReaderResumeController(store: store, legacyAdmission: recovery.admission)
        let document = bind(controller)
        await controller.waitForPendingWork()
        controller.record(anchor(5), completed: false, documentID: document)
        await fulfillment(of: [began], timeout: 2)
        let original = try ReaderMembershipContract.Binding(ownerUID: "original-reader", epoch: 7)
        _ = try await recovery.seal(binding: original)
        XCTAssertFalse(recovery.admission.isAllowed)
        controller.record(anchor(10), completed: false, documentID: document)
        bind(controller, owner: ownerB)
        let earlyReturn = expectation(description: "Actual sealed recovery cannot bypass the held original write")
        earlyReturn.isInverted = true
        let observation = ResumeDrainObservation()
        let drain = Task { await store.waitForPhysicalIdle(); if observation.checkingEarly { earlyReturn.fulfill() } }
        await fulfillment(of: [earlyReturn], timeout: 0.05)
        observation.checkingEarly = false; gate.signal(); await drain.value
        XCTAssertEqual(memory.writeCount, 1)
        XCTAssertEqual(try ReaderResumeRecord.decode(memory.bytes).entries.first?.anchor, anchor(5))
        XCTAssertEqual(controller.snapshot, .init())
    }
}

@MainActor
private final class ResumeDrainObservation {
    var checkingEarly = true
    var returned = false
}

private final class RecoveryResumeMemory: @unchecked Sendable {
    enum Failure: Error, Equatable { case read }
    private let lock = NSLock()
    private var data: Data?
    private var reads = 0, writes = 0
    private let heldRead: Int?, heldWrite: Int?
    private let readGate: DispatchSemaphore?, writeGate: DispatchSemaphore?
    private let readStarted: (@Sendable () -> Void)?, writeStarted: (@Sendable () -> Void)?
    private let failingReads: Set<Int>
    init(data: Data? = nil, heldRead: Int? = nil, readGate: DispatchSemaphore? = nil,
         readStarted: (@Sendable () -> Void)? = nil, heldWrite: Int? = nil,
         writeGate: DispatchSemaphore? = nil, writeStarted: (@Sendable () -> Void)? = nil,
         failingReads: Set<Int> = []) {
        self.data = data; self.heldRead = heldRead; self.readGate = readGate; self.readStarted = readStarted
        self.heldWrite = heldWrite; self.writeGate = writeGate; self.writeStarted = writeStarted
        self.failingReads = failingReads
    }
    var readCount: Int { lock.withLock { reads } }
    var writeCount: Int { lock.withLock { writes } }
    var bytes: Data? { lock.withLock { data } }
    var storage: ReaderResumeStore.Storage {
        .init(read: { [self] in
            let index = lock.withLock { reads += 1; return reads }
            if index == heldRead { readStarted?(); readGate?.wait() }
            if failingReads.contains(index) { throw Failure.read }
            return lock.withLock { data }
        }, write: { [self] value in
            let index = lock.withLock { writes += 1; return writes }
            if index == heldWrite { writeStarted?(); writeGate?.wait() }
            lock.withLock { data = value }
        })
    }
}
