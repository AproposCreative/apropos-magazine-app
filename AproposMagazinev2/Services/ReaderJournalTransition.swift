import Foundation

/// Explicit, inactive preparation of original legacy bytes in the new journal.
/// This is neither dispatch authority nor proof of server migration. No default
/// instance, startup task, SDK factory or production caller is installed here.
@MainActor
final class ReaderJournalTransition {
    typealias Context = CanonicalSessionState.ContextTicket
    typealias Binding = ReaderMembershipContract.Binding
    struct Operation: Equatable, Sendable {
        let context: Context
        let binding: Binding
        fileprivate let owner: UUID
        fileprivate let id: UUID
    }
    struct Receipt: Equatable, Sendable {
        let operation: Operation
        let journalRevision: UUID
        let preservedKinds: [ReaderMutationJournalRecord.LegacyKind]
    }
    enum Failure: Error { case unavailable, stale, busy, invalidState, snapshotUnavailable }
    private final class Held {
        let operation: Operation
        let membership: ReaderMembershipAuthority.WriteTicket
        let stop: ReaderWriterDrainCoordinator.StopTicket
        let reservation: UUID
        var sourceTicket: FavoritesFileJournal.TransitionTicket?
        var sourceLease: FavoritesFileJournal.SnapshotLease?
        var drainReceipt: ReaderWriterDrainCoordinator.Receipt?
        var busy = false
        var sealed = false
        var attempted = false
        var receipt: Receipt?
        init(_ operation: Operation, membership: ReaderMembershipAuthority.WriteTicket,
             stop: ReaderWriterDrainCoordinator.StopTicket, reservation: UUID) {
            self.operation = operation; self.membership = membership; self.stop = stop
            self.reservation = reservation
        }
    }
    private let id = UUID()
    private let canonical: CanonicalSessionState
    private let membership: ReaderMembershipAuthority
    private let writers: ReaderWriterDrainRuntime
    private let source: FavoritesFileJournal
    private let journal: ReaderMutationFileJournal
    private var held: Held?
    var isBusy: Bool { held?.busy == true }
    var isSealed: Bool { held?.sealed == true }

    /// Pure original-action validation for the durable wrapper before it starts
    /// its marker I/O. This grants no new account or persisted authority.
    func isPreparationCurrent(_ operation: Operation) -> Bool {
        guard let current = held, current.operation == operation, !current.busy else { return false }
        return owns(current)
    }

    init(canonical: CanonicalSessionState, membership: ReaderMembershipAuthority,
         writers: ReaderWriterDrainRuntime, source: FavoritesFileJournal,
         journal: ReaderMutationFileJournal) {
        self.canonical = canonical; self.membership = membership; self.writers = writers
        self.source = source; self.journal = journal
    }

    /// The binding is explicit original input. Neither login nor old journal
    /// contents may manufacture a new epoch for an existing untagged intent.
    func begin(context: Context, binding: Binding) -> Operation? {
        guard held == nil, canonical.isCurrent(context), context.userID == binding.ownerUID,
              let write = membership.captureWrite(for: context, binding: binding),
              let reservation = writers.reserveTransition(context: context) else { return nil }
        guard let stop = writers.stopWrites(context: context), membership.permits(write) else {
            _ = writers.releaseTransition(owner: reservation, stillIdle: { true })
            return nil
        }
        let operation = Operation(context: context, binding: binding, owner: id, id: UUID())
        held = Held(operation, membership: write, stop: stop, reservation: reservation)
        return operation
    }

    /// One attempt retains its physical slot through every callback, even when
    /// cancelled. Later stages never start with an expired account/epoch ticket.
    func prepare(_ operation: Operation) async throws -> Receipt {
        guard let current = held, current.operation == operation, owns(current) else { throw Failure.stale }
        guard !current.busy else { throw Failure.busy }
        guard !current.attempted else { throw Failure.invalidState }
        current.attempted = true; current.busy = true
        defer { current.busy = false }
        try check(current)
        let lease: FavoritesFileJournal.SnapshotLease = try await withCheckedThrowingContinuation { continuation in
            guard let namespace = FavoritesContext.confirmed(userID: operation.binding.ownerUID).namespace else {
                continuation.resume(throwing: Failure.unavailable); return
            }
            current.sourceTicket = source.freezeForTransition(namespace: namespace) { result in
                continuation.resume(with: result)
            }
        }
        current.sourceLease = lease
        try check(current)
        guard source.isCurrent(lease) else { throw Failure.stale }
        let drained = try await writers.drain(current.stop)
        current.drainReceipt = drained
        try checkPreparedSources(current)
        let old = try await readJournal(ownerUID: operation.binding.ownerUID)
        try checkPreparedSources(current)
        // Codec/hash work can touch 2 MiB. It runs off MainActor on immutable
        // originals; a late result cannot bypass the checks before file enqueue.
        let next = try await Task.detached(priority: .utility) {
            var record: ReaderMutationJournalRecord
            if let old { record = old }
            else { record = try ReaderMutationJournalRecord(ownerUID: operation.binding.ownerUID) }
            if let raw = lease.rawV1 { record = try record.preservingLegacy(kind: .favoritesV1, data: raw) }
            if let raw = lease.rawV2 { record = try record.preservingLegacy(kind: .favoritesV2, data: raw) }
            return record
        }.value
        try checkPreparedSources(current)
        // Monotonic seal precedes the first possible target write. A failed or
        // lost callback cannot make it safe to re-enable legacy mutation.
        current.sealed = true
        guard writers.sealStop(current.stop) else { throw Failure.stale }
        try checkPreparedSources(current)
        try await writeJournal(next, expectedRevision: old?.recordRevision)
        try checkPreparedSources(current)
        let verified = try await readJournal(ownerUID: operation.binding.ownerUID)
        try checkPreparedSources(current)
        let identical = await Task.detached(priority: .utility) { verified == next }.value
        try checkPreparedSources(current)
        guard identical else { throw Failure.snapshotUnavailable }
        let receipt = Receipt(operation: operation, journalRevision: next.recordRevision,
                              preservedKinds: next.legacySnapshots.map(\.kind))
        current.receipt = receipt
        return receipt
    }

    /// A caller-requested retry rolls forward with the same original action.
    /// Unknown target-write outcomes keep their seal. Fresh snapshot, drain,
    /// disk read and CAS are required; no saved receipt is replayed as authority.
    func retryPreservation(_ operation: Operation) async throws -> Receipt {
        guard let current = held, current.operation == operation, owns(current) else { throw Failure.stale }
        guard !current.busy else { throw Failure.busy }
        guard current.attempted else { throw Failure.invalidState }
        current.receipt = nil
        current.attempted = false
        return try await prepare(operation)
    }

    /// Explicit pre-write rollback only. Both gates change synchronously on the
    /// main actor. SDK abort has no callbacks after its final pure guard; source
    /// resume is a pure original-ticket/idle check with no arbitrary hooks.
    @discardableResult
    func abort(_ operation: Operation) -> Bool {
        guard let current = held, current.operation == operation,
              canAbort(current), sourceCanResume(current) else { return false }
        guard writers.abortStop(current.stop, stillBeforeTransition: { [weak self, weak current] in
            guard let self, let current else { return false }
            return self.canAbort(current) && self.sourceCanResume(current)
        }) else { return false }
        if let ticket = current.sourceTicket {
            guard source.resumeAfterAbortedTransition(ticket) else { return false }
        }
        guard writers.releaseTransition(owner: current.reservation, stillIdle: { !current.busy }) else { return false }
        held = nil
        return true
    }

    /// Account/authority invalidation may discard only this process's action.
    /// Both old gates stay closed. A later explicit begin must capture its own
    /// current binding and drain/snapshot again; it cannot reuse old receipts.
    @discardableResult
    func discardInvalidPreparation(_ operation: Operation) -> Bool {
        guard let current = held, current.operation == operation,
              !current.busy, !owns(current), writers.isPhysicallyIdle else { return false }
        guard writers.releaseTransition(owner: current.reservation, stillIdle: {
            !current.busy && self.writers.isPhysicallyIdle
        }) else { return false }
        held = nil
        return true
    }

    /// Historical file preservation only; never expose this as membership,
    /// current resource state or a server migration/writer-fence certificate.
    func isCurrent(_ receipt: Receipt) -> Bool {
        guard let current = held, current.receipt == receipt, !current.busy,
              current.sealed, owns(current), let sourceLease = current.sourceLease,
              let drain = current.drainReceipt else { return false }
        return source.isCurrent(sourceLease) && writers.isCurrent(drain)
            && owns(current) && source.isCurrent(sourceLease)
    }
    private func owns(_ current: Held) -> Bool {
        held === current && current.operation.owner == id && canonical.isCurrent(current.operation.context)
            && writers.ownsTransition(current.reservation) && membership.permits(current.membership)
    }
    private func canAbort(_ current: Held) -> Bool { owns(current) && !current.busy && !current.sealed }
    private func sourceCanResume(_ current: Held) -> Bool {
        guard let ticket = current.sourceTicket else { return true }
        return source.canResumeAfterAbortedTransition(ticket)
    }
    private func check(_ current: Held) throws {
        try Task.checkCancellation()
        guard owns(current) else { throw Failure.stale }
    }
    private func checkPreparedSources(_ current: Held) throws {
        try check(current)
        guard let sourceLease = current.sourceLease, source.isCurrent(sourceLease),
              let drain = current.drainReceipt, writers.isCurrent(drain), owns(current),
              source.isCurrent(sourceLease) else { throw Failure.stale }
    }
    private func readJournal(ownerUID: String) async throws -> ReaderMutationJournalRecord? {
        try await withCheckedThrowingContinuation { completion in
            journal.read(ownerUID: ownerUID) { completion.resume(with: $0) }
        }
    }
    private func writeJournal(_ record: ReaderMutationJournalRecord, expectedRevision: UUID?) async throws {
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            journal.write(record, expectedRevision: expectedRevision) { completion.resume(with: $0) }
        }
    }
}
