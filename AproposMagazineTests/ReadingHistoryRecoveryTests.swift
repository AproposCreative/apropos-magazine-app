import Combine
import XCTest
@testable import Apropos

/// The real history runtime and disk-backed recovery use only local effects.
/// A KVS adapter's local return is never treated as an iCloud acknowledgement.
@MainActor
final class ReadingHistoryRecoveryTests: XCTestCase {
    @MainActor private final class Memory {
        var data: [String: Data] = [:]
        var timers: [@MainActor () -> Void] = []
        var callbacks: [@MainActor (ReadingHistoryRuntime.ExternalEvent) -> Void] = []
        var factories = 0
        var synchronizations = 0
        var reads = 0
        var writes = 0
        var timerCancellations = 0
        var observerCancellations = 0
        var profileWrites: [String] = []
        var onFactory: (@MainActor () -> Void)?
        var onRead: (@MainActor () -> Void)?
        var onWrite: (@MainActor () -> Void)?
        var onSchedule: (@MainActor () -> Void)?
        var onCancelTimer: (@MainActor () -> Void)?
        var onObserve: (@MainActor () -> Void)?
        var onCancelObserver: (@MainActor () -> Void)?
        var failsWrites = false
        private enum Failure: Error { case injected }

        func runtime(recovery: ReaderTransitionRecovery?, disabled: Bool = false) -> ReadingHistoryRuntime {
            ReadingHistoryRuntime(disabled: disabled, transportFactory: { [self] in
                factories += 1; onFactory?()
                return .init(storage: .init(read: { [self] namespace in
                    reads += 1; onRead?(); return data[namespace.storageKey]
                },
                    write: { [self] namespace, value in
                        writes += 1; onWrite?()
                        if failsWrites { throw Failure.injected }
                        data[namespace.storageKey] = value
                    }), observe: { [self] callback in
                        callbacks.append(callback); onObserve?()
                        return { [self] in observerCancellations += 1; onCancelObserver?() }
                    }, synchronize: { [self] in synchronizations += 1 })
            }, schedule: { [self] _, action in
                timers.append(action); onSchedule?()
                return { [self] in timerCancellations += 1; onCancelTimer?() }
            }, markProfileRead: { [self] _, uid in profileWrites.append(uid) }, recovery: recovery)
        }
    }

    @MainActor private final class Fixture {
        let directory: URL
        let recovery: ReaderTransitionRecovery
        let memory = Memory()
        lazy var runtime = memory.runtime(recovery: recovery)
        init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        }
        func prepare(_ uid: String? = "reader-A") async throws {
            try await recovery.bootstrap()
            runtime.prepareIfNeeded()
            runtime.changeAccountContext(userID: uid)
        }
        func seal() async throws { _ = try await recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 1)) }
        /// Separately exercises the pure synchronous admission edge inside
        /// storage/factory hooks; it does not manufacture durable seal evidence.
        func closeAtSynchronousHook(notify: Bool = true) {
            recovery.admission.setAllowed(false)
            if notify { recovery.changes.send() }
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    func testOriginalScheduledHistoryWriteCannotStartAfterActualRecoverySeal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        try await recovery.bootstrap()
        let memory = Memory()
        // The unchanged behavioral assertion reproduced one post-seal write
        // before this existing runtime gained the shared recovery injection.
        let runtime = memory.runtime(recovery: recovery)
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "reader-A")
        let ticket = try XCTUnwrap(runtime.model.beginArticle(articleID: "article-A"))
        XCTAssertEqual(runtime.model.saveProgress(0.6, ticket: ticket), .scheduled)
        let originalTimer = try XCTUnwrap(memory.timers.first)
        XCTAssertEqual(memory.writes, 0)

        _ = try await recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 1))
        XCTAssertFalse(recovery.admission.isAllowed)
        originalTimer() // Deliver even though the repaired runtime cancels it.
        XCTAssertEqual(memory.writes, 0, "A scheduled history writer must not enter storage after the original recovery seal")
    }

    func testClosedStartupHasNoPlatformEffectsAndFreshMissingMarkerAllowsGuest() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.runtime.prepareIfNeeded()
        f.runtime.changeAccountContext(userID: "reader-A")
        f.runtime.model.changeContext(to: .guest)
        f.runtime.model.retryStorage()
        f.runtime.flushAcceptedEdits()
        XCTAssertEqual(f.memory.factories, 0)
        XCTAssertEqual(f.memory.reads, 0)
        XCTAssertNil(f.runtime.model.beginArticle(articleID: "article"))
        try await f.prepare(nil)
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        f.runtime.markRead(ticket)
        XCTAssertEqual(f.memory.factories, 1)
        XCTAssertEqual(f.memory.synchronizations, 1)
        XCTAssertEqual(f.memory.writes, 1)
        XCTAssertTrue(f.memory.profileWrites.isEmpty)
        XCTAssertNotNil(f.memory.data[ReadingHistoryNamespace.guest.storageKey])
    }

    func testColdSealedRecoveryCannotConstructHistoryForAnotherAccountOrGuest() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap()
        try await f.seal()
        let restarted = ReaderTransitionRecovery(store: .init(rootDirectory: f.directory))
        try await restarted.bootstrap()
        let memory = Memory()
        let cold = memory.runtime(recovery: restarted)
        cold.prepareIfNeeded(); cold.changeAccountContext(userID: "reader-B")
        cold.changeAccountContext(userID: nil)
        XCTAssertEqual(memory.factories, 0)
        XCTAssertEqual(memory.reads, 0)
        XCTAssertNil(cold.model.beginArticle(articleID: "article"))
    }

    func testPureModelAdmissionRejectsDirectRendererCallsBeforeObserverRuns() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let model = f.runtime.model
        let ticket = try XCTUnwrap(model.beginArticle(articleID: "article"))
        let external = try XCTUnwrap(model.externalTicket())
        XCTAssertEqual(model.saveProgress(0.4, ticket: ticket), .scheduled)
        let reads = f.memory.reads
        f.closeAtSynchronousHook(notify: false)
        XCTAssertFalse(model.isCurrent(ticket))
        XCTAssertNil(model.beginArticle(articleID: "new"))
        XCTAssertEqual(model.markRead(ticket), .stale)
        XCTAssertEqual(model.saveProgress(0.8, ticket: ticket), .stale)
        XCTAssertEqual(model.reloadExternal(ticket: external), .stale)
        model.reportQuotaViolation(ticket: external)
        model.flushPending(); model.retryStorage(); model.storageIdentityChanged()
        f.memory.timers.forEach { $0() }
        XCTAssertEqual(f.memory.writes, 0)
        XCTAssertEqual(f.memory.reads, reads)
    }

    func testSealRevokesActualHistoryBindingAndEveryOldObserverEvent() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let binding = ReaderHistoryBinding(model: f.runtime.model, markRead: { _ in })
        var delivered = 0
        let session = try XCTUnwrap(binding.beginArticle(articleID: "article", onOpen: {}, onProgress: { _ in delivered += 1 }))
        let document = try XCTUnwrap(binding.beginDocument(session, documentID: UUID().uuidString))
        binding.markDocumentReady(document)
        let original = binding.progressHandler(for: document)
        original(0.4)
        let observer = try XCTUnwrap(f.memory.callbacks.first)
        let key = try XCTUnwrap(f.runtime.model.context.namespace?.storageKey)
        let reads = f.memory.reads
        try await f.seal()
        original(0.9)
        observer(.changed(keys: [key])); observer(.accountChanged); observer(.quotaViolation)
        f.memory.timers.forEach { $0() }
        XCTAssertFalse(binding.isCurrent(session))
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(f.memory.reads, reads)
        XCTAssertEqual(f.memory.writes, 0)
        XCTAssertEqual(f.memory.observerCancellations, 1)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        XCTAssertNil(f.runtime.model.snapshot.issueMessage)
    }

    func testClosureDuringScheduleCancelsReturnedHandleAndCannotAdoptAnotherAccount() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        f.memory.onSchedule = { [unowned f] in f.closeAtSynchronousHook() }
        f.memory.onCancelTimer = { [unowned f] in f.runtime.changeAccountContext(userID: "reader-B") }
        _ = f.runtime.model.saveProgress(0.4, ticket: ticket)
        f.memory.timers.forEach { $0() }
        XCTAssertEqual(f.memory.timerCancellations, 1)
        XCTAssertEqual(f.memory.writes, 0)
        XCTAssertEqual(f.runtime.model.context, .unresolved)
    }

    func testClosureDuringPendingCancellationPreventsReplacementWriteAndProfileEffect() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        XCTAssertEqual(f.runtime.model.saveProgress(0.4, ticket: ticket), .scheduled)
        f.memory.onCancelTimer = { [unowned f] in f.closeAtSynchronousHook() }
        f.runtime.markRead(ticket)
        f.memory.timers.forEach { $0() }
        XCTAssertEqual(f.memory.writes, 0)
        XCTAssertTrue(f.memory.profileWrites.isEmpty)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
    }

    func testAlreadyEnteredWriteKeepsOriginalBytesWithoutOldAcknowledgementOrProfileWrite() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let ownerA = try XCTUnwrap(ReadingHistoryContext.confirmed(userID: "reader-A").namespace)
        let ownerB = try XCTUnwrap(ReadingHistoryContext.confirmed(userID: "reader-B").namespace)
        let protected = Data("other-owner-bytes".utf8)
        f.memory.data[ownerB.storageKey] = protected
        f.memory.data[ReadingHistoryNamespace.guest.storageKey] = protected
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        var readyAcknowledgements = 0
        let observation = f.runtime.model.changes.sink { snapshot in
            if snapshot.state == .ready { readyAcknowledgements += 1 }
        }
        f.memory.onWrite = { [unowned f] in f.closeAtSynchronousHook() }
        f.runtime.markRead(ticket)
        let written = try XCTUnwrap(f.memory.data[ownerA.storageKey])
        let decoded = try ReadingHistoryRecordCodec.decode(written, namespace: ownerA)
        XCTAssertEqual(decoded.entries.map(\.articleID), ["article"])
        XCTAssertEqual(f.memory.writes, 1)
        XCTAssertEqual(readyAcknowledgements, 0)
        XCTAssertTrue(f.memory.profileWrites.isEmpty)
        XCTAssertEqual(f.memory.data[ownerB.storageKey], protected)
        XCTAssertEqual(f.memory.data[ReadingHistoryNamespace.guest.storageKey], protected)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        withExtendedLifetime(observation) {}
    }

    func testClosureDuringReadCannotPublishLoadedRecordOrStartObserver() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap()
        f.memory.onRead = { [unowned f] in f.closeAtSynchronousHook() }
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        XCTAssertEqual(f.memory.reads, 1)
        XCTAssertTrue(f.memory.callbacks.isEmpty)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        XCTAssertNil(f.runtime.model.beginArticle(articleID: "article"))
    }

    func testClosureDuringObserverStartCancelsExactReturnedObservation() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap()
        f.memory.onObserve = { [unowned f] in f.closeAtSynchronousHook() }
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        let reads = f.memory.reads
        f.memory.callbacks.forEach { $0(.accountChanged) }
        XCTAssertEqual(f.memory.callbacks.count, 1)
        XCTAssertEqual(f.memory.observerCancellations, 1)
        XCTAssertEqual(f.memory.reads, reads)
        XCTAssertEqual(f.runtime.model.context, .unresolved)
    }

    func testClosureInsideFactoryNeverSynchronizesOrPublishesStorage() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try await f.recovery.bootstrap()
        f.memory.onFactory = { [unowned f] in f.closeAtSynchronousHook() }
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        XCTAssertEqual(f.memory.factories, 1)
        XCTAssertEqual(f.memory.synchronizations, 0)
        XCTAssertEqual(f.memory.reads, 0)
        XCTAssertTrue(f.memory.callbacks.isEmpty)
    }

    func testClosureDuringPublicationCannotEnqueuePendingWrite() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        let observation = f.runtime.model.objectWillChange.sink { [unowned f] in f.closeAtSynchronousHook() }
        XCTAssertEqual(f.runtime.model.saveProgress(0.4, ticket: ticket), .stale)
        XCTAssertTrue(f.memory.timers.isEmpty)
        XCTAssertEqual(f.memory.writes, 0)
        XCTAssertEqual(f.runtime.model.snapshot.state, .unresolved)
        withExtendedLifetime(observation) {}
    }

    func testLaterMissingReadCannotReviveAnAlreadyRevokedRuntimeOrOriginalTimer() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        _ = f.runtime.model.saveProgress(0.4, ticket: ticket)
        // An explicit recovery read closes admission while physically reading.
        // A missing result may reopen legacy startup, not this old reader epoch.
        try await f.recovery.bootstrap()
        XCTAssertTrue(f.recovery.admission.isAllowed)
        f.runtime.prepareIfNeeded(); f.runtime.changeAccountContext(userID: "reader-A")
        f.runtime.changeAccountContext(userID: "reader-B"); f.runtime.changeAccountContext(userID: nil)
        f.runtime.model.changeContext(to: .confirmed(userID: "reader-A"))
        f.memory.timers.forEach { $0() }
        XCTAssertEqual(f.runtime.model.context, .unresolved)
        XCTAssertFalse(f.runtime.model.isCurrent(ticket))
        XCTAssertNil(f.runtime.model.beginArticle(articleID: "new"))
        XCTAssertEqual(f.memory.writes, 0)
        XCTAssertEqual(f.memory.factories, 1)
    }

    func testAccountRoundTripRetainsOtherOwnerBytesAndRejectsOldTimerBeforeSeal() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let a = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "A"))
        _ = f.runtime.model.saveProgress(0.4, ticket: a)
        let old = try XCTUnwrap(f.memory.timers.first)
        f.runtime.changeAccountContext(userID: "reader-B")
        let b = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "B"))
        f.runtime.markRead(b)
        let bKey = try XCTUnwrap(f.runtime.model.context.namespace?.storageKey)
        let preserved = try XCTUnwrap(f.memory.data[bKey])
        f.runtime.changeAccountContext(userID: nil)
        let guest = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "guest"))
        f.runtime.markRead(guest)
        let guestBytes = try XCTUnwrap(f.memory.data[ReadingHistoryNamespace.guest.storageKey])
        f.runtime.changeAccountContext(userID: "reader-A")
        old()
        XCTAssertFalse(f.runtime.model.isCurrent(a))
        try await f.seal()
        XCTAssertEqual(f.memory.writes, 2)
        XCTAssertEqual(f.memory.data[bKey], preserved)
        XCTAssertEqual(f.memory.data[ReadingHistoryNamespace.guest.storageKey], guestBytes)
    }

    func testRecoveryClosureAfterWriteFailurePreventsRetryAndPreservesStoredBytes() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.prepare()
        let ticket = try XCTUnwrap(f.runtime.model.beginArticle(articleID: "article"))
        f.memory.failsWrites = true
        XCTAssertEqual(f.runtime.model.markRead(ticket), .unavailable)
        XCTAssertTrue(f.runtime.model.snapshot.canRetry)
        try await f.seal()
        f.memory.failsWrites = false
        f.runtime.model.retryStorage(); f.runtime.flushAcceptedEdits()
        XCTAssertEqual(f.memory.writes, 1)
        XCTAssertTrue(f.memory.data.isEmpty)
        XCTAssertFalse(f.runtime.model.snapshot.canRetry)
    }
}
