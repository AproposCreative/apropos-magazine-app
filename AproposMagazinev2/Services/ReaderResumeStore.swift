import Foundation

/// One bounded device-local record. Synchronous admission orders all controllers
/// before returning; complete storage transactions run on a private serial queue.
/// Cancellation of a UI waiter cannot withdraw an already accepted write.
final class ReaderResumeStore: @unchecked Sendable {
    struct Storage: Sendable {
        let read: @Sendable () throws -> Data?
        let write: @Sendable (Data) throws -> Void
    }
    enum Failure: Error, Equatable { case capacityExceeded }
    static let maximumPendingOperations = 64

    /// A receipt belongs to one admitted immutable write, even if its controller
    /// closes or is released. Completion is storage readback, not disk fsync.
    final class Receipt: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Void, Error>?
        private var waiters: [CheckedContinuation<Void, Error>] = []
        fileprivate init() { }
        func value() async throws {
            try await withCheckedThrowingContinuation { continuation in
                let completed: Result<Void, Error>? = lock.withLock {
                    if let result { return result }
                    waiters.append(continuation)
                    return nil
                }
                if let completed { continuation.resume(with: completed) }
            }
        }
        fileprivate func finish(_ completed: Result<Void, Error>) {
            let pending: [CheckedContinuation<Void, Error>] = lock.withLock {
                guard result == nil else { return [] }
                result = completed
                let pending = waiters; waiters = []
                return pending
            }
            pending.forEach { $0.resume(with: completed) }
        }
    }

    typealias CleanupFailure = ReaderResumeLocalCleanupRecord.Failure
    struct CleanupLease: Sendable {
        fileprivate let storeID: UUID
        fileprivate let raw: Data?
        fileprivate let record: ReaderResumeLocalCleanupRecord
        fileprivate let use: LeaseUse
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
    }
    struct CleanupReceipt: Equatable, Sendable {
        fileprivate let record: ReaderResumeLocalCleanupRecord
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
        var isComplete: Bool { record.phase == .complete }
        func belongs(to checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
            record.belongs(to: checkpoint)
        }
    }
    fileprivate final class LeaseUse: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func consume() throws {
            try lock.withLock {
                guard !used else { throw CleanupFailure.invalidLease }
                used = true
            }
        }
    }
    private final class CleanupOperation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        func check() throws {
            try lock.withLock { if cancelled { throw CancellationError() } }
        }
    }
    private typealias Completion = @Sendable () -> Void
    private typealias Finish = @Sendable (@escaping Completion) -> Void
    private typealias Work = @Sendable (@escaping Finish) -> Void
    private struct Job: Sendable { let countsCapacity: Bool; let work: Work }

    private let storage: Storage
    private let storeID = UUID()
    private let ioQueue = DispatchQueue(label: "com.apropos.reader-resume", qos: .utility)
    private let admissionLock = NSLock()
    private var pendingOperations = 0
    private var jobs: [Job] = []
    private var running = false
    private struct Confirmation { var record: ReaderResumeLocalCleanupRecord; var observed: Bool }
    private var confirmations: [String: Confirmation] = [:]
    init(storage: Storage) { self.storage = storage }

    func load(owner: String, source: ReaderResumeIdentity) async throws -> ReaderResumeAnchor? {
        try Task.checkCancellation()
        guard ReaderResumeRecord.validOwner(owner), source.isValid else { throw ReaderResumeRecord.Failure.invalid }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try enqueue { [self] in
                    let result = Result {
                        let record = try ReaderResumeRecord.decode(storage.read())
                        guard !admissionLock.withLock({ confirmations[owner] != nil }),
                              !record.cleanups.contains(where: { $0.owner == owner }) else { throw CleanupFailure.ownerClosed }
                        return record.entries.first { $0.owner == owner && $0.source == source }?.anchor
                    }
                    return { continuation.resume(with: result) }
                }
            } catch { continuation.resume(throwing: error) }
        }
    }

    func save(owner: String, source: ReaderResumeIdentity, anchor: ReaderResumeAnchor?) async throws {
        try Task.checkCancellation()
        let receipt = try accept(owner: owner, source: source, anchor: anchor)
        try await receipt.value()
    }

    /// Validation/capacity failure rejects admission without touching stored
    /// data. Once returned, this receipt will settle independently of UI tasks.
    func accept(owner: String, source: ReaderResumeIdentity, anchor: ReaderResumeAnchor?) throws -> Receipt {
        guard ReaderResumeRecord.validOwner(owner), source.isValid,
              anchor.map(\.isValid) ?? true else { throw ReaderResumeRecord.Failure.invalid }
        let receipt = Receipt()
        try enqueue { [self] in
            let result = Result { try persist(owner: owner, source: source, anchor: anchor) }
            return { receipt.finish(result) }
        }
        return receipt
    }

    /// Queue barrier for the original application store after admission has
    /// closed. It cannot be rejected by a full work queue or released by the
    /// waiter's cancellation. All previously accepted storage transactions,
    /// including their readback and receipt completion, physically finish
    /// first. This is neither a write-success receipt nor a filesystem fsync.
    func waitForPhysicalIdle() async {
        await withCheckedContinuation { continuation in
            // A raw DispatchQueue barrier could overtake a cleanup awaiting its
            // MainActor gate. Join the same physical-job sequencer instead.
            try? enqueueOperation(countsCapacity: false) { finish in
                finish { continuation.resume() }
            }
        }
    }

    /// Read-only original-owner snapshot. It neither closes normal admission nor
    /// removes data. A fresh explicit confirmation must consume the returned lease.
    func prepareLocalCleanup(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                             stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupLease {
        try await cleanupOperation { [self] operation in
            try await authorize(operation, stillCurrent)
            let snapshot: (Data?, ReaderResumeLocalCleanupRecord) = try await onIO { [self] in
                try operation.check()
                let raw = try storage.read()
                try operation.check()
                let envelope = try decodeCleanupSnapshot(raw)
                let proposed = try ReaderResumeLocalCleanupRecord(checkpoint: checkpoint, entries: envelope.entries)
                let record: ReaderResumeLocalCleanupRecord
                let confirmed = admissionLock.withLock { confirmations[proposed.owner] }
                if let existing = envelope.cleanups.first(where: { $0.owner == proposed.owner }) {
                    guard existing.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
                    if let confirmed, !confirmed.record.sameOriginal(as: existing) { throw CleanupFailure.changedSource }
                    try existing.validateRemaining(envelope.entries)
                    record = existing
                } else if let confirmed {
                    guard !confirmed.observed else { throw CleanupFailure.unconfirmed }
                    guard confirmed.record.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
                    try confirmed.record.validateRemaining(envelope.entries)
                    record = confirmed.record
                } else {
                    guard envelope.cleanups.count < ReaderResumeRecord.maximumCleanups else { throw Failure.capacityExceeded }
                    record = proposed
                }
                return (raw, record)
            }
            try await authorize(operation, stillCurrent)
            try await onIO { [self] in
                try operation.check()
                guard try storage.read() == snapshot.0 else { throw CleanupFailure.changedSource }
                try operation.check()
            }
            return CleanupLease(storeID: storeID, raw: snapshot.0, record: snapshot.1, use: LeaseUse())
        }
    }

    /// Explicit confirmation, pending seal, owner-only removal, then exact
    /// readback. Cancellation cannot retire its physical slot early. A lost
    /// readback requires a fresh prepare/confirmation, never replay of this lease.
    func commitLocalCleanup(_ lease: CleanupLease,
                            stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupReceipt {
        guard lease.storeID == storeID else { throw CleanupFailure.invalidLease }
        return try await cleanupOperation(onAdmit: { try lease.use.consume() }) { [self] operation in
            try await authorize(operation, stillCurrent)
            var expected = try await onIO { [self] in
                try operation.check()
                guard try storage.read() == lease.raw else { throw CleanupFailure.changedSource }
                try operation.check()
                var envelope = try decodeCleanupSnapshot(lease.raw)
                try admissionLock.withLock {
                    if let confirmed = confirmations[lease.owner] {
                        guard confirmed.record.sameOriginal(as: lease.record) else { throw CleanupFailure.changedSource }
                    } else {
                        guard confirmations.count < ReaderResumeRecord.maximumCleanups else { throw Failure.capacityExceeded }
                        confirmations[lease.owner] = Confirmation(record: lease.record, observed: false)
                    }
                }
                if let existing = envelope.cleanups.first(where: { $0.owner == lease.owner }) {
                    guard existing == lease.record else { throw CleanupFailure.changedSource }
                    admissionLock.withLock { confirmations[lease.owner] = Confirmation(record: existing, observed: true) }
                    return lease.raw
                }
                guard lease.record.phase == .pending,
                      envelope.cleanups.count < ReaderResumeRecord.maximumCleanups else { throw CleanupFailure.invalidLease }
                try lease.record.validateRemaining(envelope.entries)
                envelope.cleanups.append(lease.record)
                let pending = try ReaderResumeRecord.encode(envelope)
                try operation.check()
                try storage.write(pending)
                guard try storage.read() == pending else { throw CleanupFailure.unconfirmed }
                admissionLock.withLock { confirmations[lease.owner] = Confirmation(record: lease.record, observed: true) }
                return Optional(pending)
            }
            try await authorize(operation, stillCurrent)
            let pending = expected
            expected = try await onIO { [self] in
                try operation.check()
                guard try storage.read() == pending else { throw CleanupFailure.changedSource }
                try operation.check()
                var envelope = try decodeCleanupSnapshot(pending)
                guard let index = envelope.cleanups.firstIndex(where: { $0.owner == lease.owner }),
                      envelope.cleanups[index] == lease.record else { throw CleanupFailure.changedSource }
                if envelope.cleanups[index].phase == .complete { return pending }
                envelope.entries.removeAll { $0.owner == lease.owner }
                envelope.cleanups[index].phase = .complete
                let complete = try ReaderResumeRecord.encode(envelope)
                try operation.check()
                try storage.write(complete)
                guard try storage.read() == complete else { throw CleanupFailure.unconfirmed }
                admissionLock.withLock { confirmations[lease.owner] = Confirmation(record: envelope.cleanups[index], observed: true) }
                return Optional(complete)
            }
            try await authorize(operation, stillCurrent)
            let complete = expected
            return try await onIO { [self] in
                // Final readback follows the last external permission hook.
                // The caller separately guards publication against its context.
                try operation.check()
                guard try storage.read() == complete else { throw CleanupFailure.unconfirmed }
                try operation.check()
                let envelope = try decodeCleanupSnapshot(complete)
                var target = lease.record; target.phase = .complete
                guard envelope.cleanups.contains(target), !envelope.entries.contains(where: { $0.owner == lease.owner }) else {
                    throw CleanupFailure.unconfirmed
                }
                return CleanupReceipt(record: target)
            }
        }
    }

    private func decodeCleanupSnapshot(_ raw: Data?) throws -> ReaderResumeRecord.Envelope {
        let envelope = try ReaderResumeRecord.decode(raw)
        // Legacy reads tolerate old JSON. Destructive cleanup does not erase
        // unknown/repeated fields in other owners' data by decoding/re-encoding.
        if let raw, try ReaderResumeRecord.encode(envelope) != raw { throw CleanupFailure.invalidRecord }
        return envelope
    }

    @MainActor private func authorize(_ operation: CleanupOperation,
                                     _ stillCurrent: @MainActor () -> Bool) throws {
        try operation.check()
        guard stillCurrent() else { throw CleanupFailure.denied }
        try operation.check()
    }

    private func cleanupOperation<Value: Sendable>(onAdmit: (@Sendable () throws -> Void)? = nil,
                                                   _ work: @escaping @Sendable (CleanupOperation) async throws -> Value) async throws -> Value {
        let operation = CleanupOperation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    try enqueueOperation(onAdmit: onAdmit) { finish in
                        Task {
                            do {
                                let value = try await work(operation)
                                finish { continuation.resume(returning: value) }
                            } catch { finish { continuation.resume(throwing: error) } }
                        }
                    }
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { operation.cancel() }
    }

    private func onIO<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { continuation.resume(with: Result(catching: work)) }
        }
    }

    private func enqueue(_ work: @escaping @Sendable () -> Completion) throws {
        try enqueueOperation { finish in finish(work()) }
    }

    private func enqueueOperation(countsCapacity: Bool = true, onAdmit: (@Sendable () throws -> Void)? = nil,
                                  _ work: @escaping Work) throws {
        let start: Bool = try admissionLock.withLock {
            guard !countsCapacity || pendingOperations < Self.maximumPendingOperations else { throw Failure.capacityExceeded }
            try onAdmit?()
            if countsCapacity { pendingOperations += 1 }
            jobs.append(Job(countsCapacity: countsCapacity, work: work))
            guard !running else { return false }
            running = true
            return true
        }
        if start { startNext() }
    }

    private func startNext() {
        let job: Job? = admissionLock.withLock {
            guard !jobs.isEmpty else { running = false; return nil }
            return jobs.removeFirst()
        }
        guard let job else { return }
        ioQueue.async { [self] in
            job.work { [self] complete in
                ioQueue.async { [self] in
                    if job.countsCapacity { admissionLock.withLock { pendingOperations -= 1 } }
                    complete()
                    startNext()
                }
            }
        }
    }

    private func persist(owner: String, source: ReaderResumeIdentity, anchor: ReaderResumeAnchor?) throws {
        var record = try ReaderResumeRecord.decode(storage.read())
        guard !admissionLock.withLock({ confirmations[owner] != nil }),
              !record.cleanups.contains(where: { $0.owner == owner }) else { throw CleanupFailure.ownerClosed }
        let old = record
        record.entries.removeAll { $0.owner == owner && $0.source.articleID == source.articleID }
        if let anchor { record.entries.append(.init(owner: owner, source: source, anchor: anchor)) }
        if record.entries.count > ReaderResumeRecord.maximumEntries {
            record.entries.removeFirst(record.entries.count - ReaderResumeRecord.maximumEntries)
        }
        guard record != old else { return }
        let data = try ReaderResumeRecord.encode(record)
        try storage.write(data)
        guard try storage.read() == data else { throw ReaderResumeRecord.Failure.unconfirmed }
    }
}
