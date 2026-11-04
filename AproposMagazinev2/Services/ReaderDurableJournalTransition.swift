import Foundation

/// Staged durable composition around the already tested source/drain/target
/// transition. The marker is verified before that transition can touch its
/// target. Persisted identity is history, never live account/epoch authority.
@MainActor
final class ReaderDurableJournalTransition {
    typealias Context = CanonicalSessionState.ContextTicket
    typealias Binding = ReaderMembershipContract.Binding
    typealias Operation = ReaderJournalTransition.Operation
    typealias Receipt = ReaderJournalTransition.Receipt
    enum Failure: Error { case stale, busy }
    private let transition: ReaderJournalTransition
    private let recovery: ReaderTransitionRecovery
    private var operation: Operation?
    private var innerAttempted = false
    private(set) var isBusy = false

    /// The supplied runtime and source must use this recovery's admission
    /// snapshot. This explicit composition is inactive in the app; production
    /// wiring, other writers and server migration remain separate gates.
    init(canonical: CanonicalSessionState, membership: ReaderMembershipAuthority,
         recovery: ReaderTransitionRecovery, writers: ReaderWriterDrainRuntime,
         source: FavoritesFileJournal, journal: ReaderMutationFileJournal) {
        self.recovery = recovery
        transition = ReaderJournalTransition(canonical: canonical, membership: membership,
                                             writers: writers, source: source, journal: journal)
    }

    func begin(context: Context, binding: Binding) -> Operation? {
        guard operation == nil, !isBusy, recovery.canPrepare(binding: binding),
              let next = transition.begin(context: context, binding: binding) else { return nil }
        // begin rechecks canonical membership itself. Disk identity alone can
        // never construct a current write ticket after restart or A -> B -> A.
        operation = next; innerAttempted = false
        return next
    }

    func prepare(_ original: Operation) async throws -> Receipt {
        guard operation == original else { throw Failure.stale }
        guard !isBusy else { throw Failure.busy }
        guard transition.isPreparationCurrent(original) else { throw Failure.stale }
        isBusy = true
        defer { isBusy = false }
        _ = try await recovery.seal(binding: original.binding)
        try Task.checkCancellation()
        guard operation == original else { throw Failure.stale }
        if innerAttempted { return try await transition.retryPreservation(original) }
        innerAttempted = true
        return try await transition.prepare(original)
    }

    @discardableResult
    func abort(_ original: Operation) -> Bool {
        guard operation == original, !isBusy, !recovery.hasSealAttempt,
              transition.abort(original) else { return false }
        operation = nil
        return true
    }

    @discardableResult
    func discardInvalidPreparation(_ original: Operation) -> Bool {
        guard operation == original, !isBusy,
              transition.discardInvalidPreparation(original) else { return false }
        operation = nil
        return true
    }

    func isCurrent(_ receipt: Receipt) -> Bool {
        !isBusy && operation == receipt.operation && recovery.hasVerifiedSeal(binding: receipt.operation.binding)
            && transition.isCurrent(receipt)
    }
}
