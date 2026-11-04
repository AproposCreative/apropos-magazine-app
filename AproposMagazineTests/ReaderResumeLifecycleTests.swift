import Foundation
import SwiftUI
import XCTest
@testable import Apropos

@MainActor
final class ReaderResumeLifecycleTests: XCTestCase {
    private let ownerA = "account_" + String(repeating: "a", count: 64)
    private let ownerB = "account_" + String(repeating: "b", count: 64)
    private func source(_ id: String = "article", revision: String = "v1") -> ReaderResumeIdentity {
        ReaderResumeIdentity(articleID: id, sourceRevision: revision, html: "<p>Exact paragraph source.</p>")!
    }
    private func anchor(_ index: Int) -> ReaderResumeAnchor { .init(index: index, fingerprint: "1234abcd") }
    private func bind(_ model: ReaderResumeController, owner: String, source: ReaderResumeIdentity,
                      document: String = UUID().uuidString) -> String {
        model.bind(owner: owner, source: source, sessionID: UUID(), documentID: document, isCurrent: { true })
        return document
    }

    func testAcceptedRecordSurvivesImmediateInvalidateWithoutYield() async throws {
        let memory = ResumeLifecycleMemory(), store = ReaderResumeStore(storage: memory.storage)
        let model = ReaderResumeController(store: store)
        let document = bind(model, owner: ownerA, source: source())
        await model.waitForPendingWork()
        model.record(anchor(5), completed: false, documentID: document)
        model.invalidate()
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(5))
        XCTAssertNil(model.snapshot.offer)
        XCTAssertNil(model.snapshot.message)
    }

    func testActualHTMLCoordinatorReloadPreservesAcceptedWriteAndReadsItBack() async throws {
        let memory = ResumeLifecycleMemory(), store = ReaderResumeStore(storage: memory.storage)
        let resume = ReaderResumeController(store: store)
        let history = ReadingHistoryModel(storage: .init(read: { _ in nil }, write: { _, _ in }),
                                          schedule: { _, _ in {} })
        history.changeContext(to: .guest)
        let historyBinding = ReaderHistoryBinding(model: history, markRead: { _ in })
        let session = try XCTUnwrap(historyBinding.beginArticle(articleID: "article", onOpen: {}, onProgress: { _ in }))
        let renderer = HTMLTextView(html: "<p>Exact paragraph source.</p>", articleId: "article", articleRevision: "v1",
            dynamicHeight: .constant(240), historyBinding: historyBinding, historySession: session,
            resumeController: resume, resumeOwner: "guest", prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
        let coordinator = renderer.makeCoordinator(), oldDocument = UUID().uuidString
        coordinator.acceptDocument(oldDocument)
        await resume.waitForPendingWork()
        XCTAssertNil(resume.snapshot.offer, "Accepted HTML is not yet an actionable document")
        coordinator.documentBecameReady(oldDocument)
        await resume.waitForPendingWork()
        resume.record(anchor(6), completed: false, documentID: oldDocument)
        // Font-driven reload uses this exact invalidate -> accept sequence.
        let replacementDocument = UUID().uuidString
        coordinator.acceptDocument(replacementDocument)
        coordinator.documentBecameReady(oldDocument)
        XCTAssertNil(resume.snapshot.offer, "A stale layout callback cannot bind the replacement")
        coordinator.documentBecameReady(replacementDocument)
        await resume.waitForPendingWork()
        XCTAssertEqual(resume.snapshot.offer, anchor(6))
        let writes = memory.writeCount
        resume.record(anchor(9), completed: false, documentID: oldDocument)
        await resume.waitForPendingWork()
        XCTAssertEqual(memory.writeCount, writes, "A late old-document sample is not newly admitted")
        coordinator.invalidateDocument()
    }

    func testAToBToAKeepsOriginalOwnersAndLatestAcceptedAValue() async throws {
        let store = ReaderResumeStore(storage: ResumeLifecycleMemory().storage)
        let model = ReaderResumeController(store: store)
        let a = bind(model, owner: ownerA, source: source())
        await model.waitForPendingWork()
        model.record(anchor(3), completed: false, documentID: a)
        let b = bind(model, owner: ownerB, source: source())
        model.record(anchor(7), completed: false, documentID: b)
        let freshA = bind(model, owner: ownerA, source: source())
        model.record(anchor(10), completed: false, documentID: freshA)
        model.record(anchor(11), completed: false, documentID: a)
        model.invalidate()
        let savedA = try await store.load(owner: ownerA, source: source())
        let savedB = try await store.load(owner: ownerB, source: source())
        XCTAssertEqual(savedA, anchor(10)); XCTAssertEqual(savedB, anchor(7))
    }

    func testSeparateControllersShareActualAdmissionOrder() async throws {
        let store = ReaderResumeStore(storage: ResumeLifecycleMemory().storage)
        let older = ReaderResumeController(store: store), newer = ReaderResumeController(store: store)
        let first = bind(older, owner: ownerA, source: source())
        await older.waitForPendingWork()
        older.record(anchor(4), completed: false, documentID: first)
        older.invalidate()
        let next = bind(newer, owner: ownerA, source: source())
        newer.record(anchor(12), completed: false, documentID: next)
        newer.invalidate()
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(12))
    }

    func testNewSourceCannotBeOvertakenByAcceptedOldSourceWrite() async throws {
        let store = ReaderResumeStore(storage: ResumeLifecycleMemory().storage)
        let old = ReaderResumeController(store: store), new = ReaderResumeController(store: store)
        let first = bind(old, owner: ownerA, source: source(revision: "v1"))
        await old.waitForPendingWork()
        old.record(anchor(3), completed: false, documentID: first)
        old.invalidate()
        let next = bind(new, owner: ownerA, source: source(revision: "v2"))
        new.record(anchor(8), completed: false, documentID: next)
        new.invalidate()
        let previous = try await store.load(owner: ownerA, source: source(revision: "v1"))
        let latest = try await store.load(owner: ownerA, source: source(revision: "v2"))
        XCTAssertNil(previous); XCTAssertEqual(latest, anchor(8))
    }

    func testMultipleAcceptedSamplesAndCompletionDrainInOrderWithoutYield() async throws {
        let store = ReaderResumeStore(storage: ResumeLifecycleMemory().storage)
        let model = ReaderResumeController(store: store)
        let document = bind(model, owner: ownerA, source: source())
        await model.waitForPendingWork()
        for index in 1...16 { model.record(anchor(index), completed: false, documentID: document) }
        model.record(anchor(16), completed: true, documentID: document)
        model.invalidate()
        let completed = try await store.load(owner: ownerA, source: source())
        XCTAssertNil(completed, "Earlier queued samples cannot resurrect completed reading")
    }

    func testControllerDeallocationDoesNotCancelAcceptedStorageWork() async throws {
        let store = ReaderResumeStore(storage: ResumeLifecycleMemory().storage)
        var model: ReaderResumeController? = ReaderResumeController(store: store)
        weak var released = model
        let document = bind(model!, owner: ownerA, source: source())
        await model?.waitForPendingWork()
        model?.record(anchor(5), completed: false, documentID: document)
        model = nil
        XCTAssertNil(released)
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(5))
    }

    func testOldAcceptedWriteFailureCannotPublishIntoNewOwner() async throws {
        let began = expectation(description: "First storage write started")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let memory = ResumeLifecycleMemory(firstWriteGate: gate, firstWriteStarted: { began.fulfill() }, failingWrites: [1])
        let store = ReaderResumeStore(storage: memory.storage)
        let actual = ReaderResumeController(store: store)
        let a = bind(actual, owner: ownerA, source: source())
        await actual.waitForPendingWork()
        actual.record(anchor(4), completed: false, documentID: a)
        await fulfillment(of: [began], timeout: 2)
        let b = bind(actual, owner: ownerB, source: source())
        actual.record(anchor(9), completed: false, documentID: b)
        gate.signal()
        await actual.waitForPendingWork()
        let savedA = try await store.load(owner: ownerA, source: source())
        let savedB = try await store.load(owner: ownerB, source: source())
        XCTAssertNil(savedA); XCTAssertEqual(savedB, anchor(9))
        XCTAssertNil(actual.snapshot.message)
    }

    func testCurrentFailureIsVisibleAndNextAcceptedSampleCanRetry() async throws {
        let memory = ResumeLifecycleMemory(failingWrites: [1]), store = ReaderResumeStore(storage: memory.storage)
        let model = ReaderResumeController(store: store)
        let document = bind(model, owner: ownerA, source: source())
        await model.waitForPendingWork()
        model.record(anchor(4), completed: false, documentID: document)
        await model.waitForPendingWork()
        XCTAssertNotNil(model.snapshot.message)
        model.record(anchor(4), completed: false, documentID: document)
        await model.waitForPendingWork()
        XCTAssertNil(model.snapshot.message)
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(4))
    }

    func testAdmissionCapRejectsBeforeStorageAndRestoresCapacityAfterFailureAndSuccess() async throws {
        let began = expectation(description: "Bounded queue write started")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let memory = ResumeLifecycleMemory(firstWriteGate: gate, firstWriteStarted: { began.fulfill() }, failingWrites: [1])
        let store = ReaderResumeStore(storage: memory.storage)
        let first = try store.accept(owner: ownerA, source: source("article-0"), anchor: anchor(2))
        await fulfillment(of: [began], timeout: 2)
        var receipts: [ReaderResumeStore.Receipt] = []
        for index in 1..<ReaderResumeStore.maximumPendingOperations {
            receipts.append(try store.accept(owner: ownerA, source: source("article-\(index)"), anchor: anchor(index)))
        }
        XCTAssertThrowsError(try store.accept(owner: ownerA, source: source("overflow"), anchor: anchor(3))) {
            XCTAssertEqual($0 as? ReaderResumeStore.Failure, .capacityExceeded)
        }
        do { _ = try await store.load(owner: ownerA, source: source()); XCTFail("Full queue admitted a read") }
        catch { XCTAssertEqual(error as? ReaderResumeStore.Failure, .capacityExceeded) }
        XCTAssertEqual(memory.writeCount, 1)
        gate.signal()
        do { try await first.value(); XCTFail("Fixture's first write must fail") } catch { }
        for receipt in receipts { try await receipt.value() }
        let next = try store.accept(owner: ownerA, source: source("after-drain"), anchor: anchor(8))
        try await next.value()
        let saved = try await store.load(owner: ownerA, source: source("after-drain"))
        XCTAssertEqual(saved, anchor(8))
        let rejected = try await store.load(owner: ownerA, source: source("overflow"))
        XCTAssertNil(rejected)
    }

    func testOlderSuccessCannotClearLatestAdmissionFailureAndRetryCanSave() async throws {
        let began = expectation(description: "Older controller write started")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let memory = ResumeLifecycleMemory(firstWriteGate: gate, firstWriteStarted: { began.fulfill() })
        let store = ReaderResumeStore(storage: memory.storage)
        let model = ReaderResumeController(store: store)
        let document = bind(model, owner: ownerA, source: source())
        await model.waitForPendingWork()
        model.record(anchor(4), completed: false, documentID: document)
        await fulfillment(of: [began], timeout: 2)
        var receipts: [ReaderResumeStore.Receipt] = []
        for index in 1..<ReaderResumeStore.maximumPendingOperations {
            receipts.append(try store.accept(owner: ownerB, source: source("capacity-\(index)"), anchor: anchor(index)))
        }
        model.record(anchor(9), completed: false, documentID: document)
        let admissionFailure = try XCTUnwrap(model.snapshot.message)
        gate.signal()
        await model.waitForPendingWork()
        for receipt in receipts { try await receipt.value() }
        XCTAssertEqual(model.snapshot.message, admissionFailure, "The latest position was rejected, despite the older write succeeding")
        let previous = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(previous, anchor(4))
        model.record(anchor(9), completed: false, documentID: document)
        await model.waitForPendingWork()
        XCTAssertNil(model.snapshot.message)
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(9))
    }

    func testCancellingReceiptWaiterDoesNotWithdrawAcceptedWrite() async throws {
        let began = expectation(description: "Receipt write started")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let memory = ResumeLifecycleMemory(firstWriteGate: gate, firstWriteStarted: { began.fulfill() })
        let store = ReaderResumeStore(storage: memory.storage)
        let receipt = try store.accept(owner: ownerA, source: source(), anchor: anchor(8))
        let waiting = Task { try await receipt.value() }
        await fulfillment(of: [began], timeout: 2)
        waiting.cancel()
        gate.signal()
        try await waiting.value
        let saved = try await store.load(owner: ownerA, source: source())
        XCTAssertEqual(saved, anchor(8))
    }
}

/// Storage is synchronous like UserDefaults; the test gate holds an actual
/// operation off-main so ordering/backpressure do not rely on scheduler timing.
private final class ResumeLifecycleMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var writes = 0
    private let firstWriteGate: DispatchSemaphore?
    private let firstWriteStarted: (@Sendable () -> Void)?
    private let failingWrites: Set<Int>
    enum Failure: Error { case fixtureWrite }
    init(firstWriteGate: DispatchSemaphore? = nil, firstWriteStarted: (@Sendable () -> Void)? = nil,
         failingWrites: Set<Int> = []) {
        self.firstWriteGate = firstWriteGate; self.firstWriteStarted = firstWriteStarted
        self.failingWrites = failingWrites
    }
    var writeCount: Int { lock.withLock { writes } }
    var storage: ReaderResumeStore.Storage {
        .init(read: { [self] in lock.withLock { data } }, write: { [self] next in
            let index = lock.withLock { writes += 1; return writes }
            if index == 1 { firstWriteStarted?(); firstWriteGate?.wait() }
            if failingWrites.contains(index) { throw Failure.fixtureWrite }
            lock.withLock { data = next }
        })
    }
}
