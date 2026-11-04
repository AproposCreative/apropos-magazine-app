import Combine
import Foundation

/// Inactive projection of an explicitly read server membership. Login, cached
/// documents and persisted account data never grant reader-write authority.
@MainActor
final class ReaderMembershipAuthority: ObservableObject {
    typealias Binding = ReaderMembershipContract.Binding
    typealias Record = ReaderMembershipContract.Record
    typealias ContextTicket = CanonicalSessionState.ContextTicket

    enum Status: Equatable {
        case unresolved, loading, unavailable, missing
        case active(Binding)
        case deletionFrozen(Binding, requestID: String)
    }
    struct Snapshot: Equatable {
        let context: ContextTicket
        let status: Status
        let revision: UUID
    }
    struct ReadTicket: Equatable {
        let context: ContextTicket
        fileprivate let modelID: UUID
        fileprivate let revision: UUID
    }
    struct WriteTicket: Equatable {
        let context: ContextTicket
        let binding: Binding
        fileprivate let modelID: UUID
        fileprivate let revision: UUID
    }
    private struct KnownMembership {
        let epoch: Int64
        let frozen: Bool
    }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let subject = PassthroughSubject<Snapshot, Never>()
    var changes: AnyPublisher<Snapshot, Never> {
        subject.filter { [weak self] value in self?.snapshot.revision == value.revision }.eraseToAnyPublisher()
    }
    private(set) var snapshot: Snapshot
    var status: Status { snapshot.status }

    private let canonical: CanonicalSessionState
    private let modelID = UUID()
    private var context: ContextTicket
    private var revision: UUID
    private var read: ReadTicket?
    private var known: KnownMembership?
    private var confirmedDeletionBinding: Binding?
    private var notifying = false
    private var observation: AnyCancellable?

    init(canonical: CanonicalSessionState) {
        self.canonical = canonical
        let context = canonical.contextTicket(), revision = UUID()
        self.context = context
        self.revision = revision
        snapshot = Snapshot(context: context, status: .unresolved, revision: revision)
        observation = canonical.changes.sink { [weak self] _ in self?.accountChanged() }
    }

    /// No fetch is started. The adapter must request the original account's
    /// membership and deliver exactly one response with explicit provenance.
    func beginRead(for original: ContextTicket) -> ReadTicket? {
        guard original == context, canonical.isCurrent(original), let uid = original.userID,
              (try? Binding(ownerUID: uid, epoch: 1)) != nil else { return nil }
        let next = reserve()
        let ticket = ReadTicket(context: original, modelID: modelID, revision: next)
        read = ticket
        guard publish(.loading, revision: next), owns(ticket) else { return nil }
        return ticket
    }

    /// A nil record means server-confirmed absence, not implicit enrollment.
    /// Cached/pending-write responses consume this read without granting rights;
    /// the adapter must explicitly begin a new read for a later server response.
    @discardableResult
    func completeRead(_ ticket: ReadTicket, record: Record?, isFromCache: Bool, hasPendingWrites: Bool) -> Bool {
        guard owns(ticket) else { return false }
        read = nil
        confirmedDeletionBinding = nil
        let next = reserve()
        guard !isFromCache, !hasPendingWrites else {
            _ = publish(.unavailable, revision: next)
            return false
        }
        guard let record else { return publish(.missing, revision: next) }
        guard record.binding.ownerUID == ticket.context.userID else {
            _ = publish(.unavailable, revision: next)
            return false
        }
        if let known, record.binding.epoch < known.epoch
            || (record.binding.epoch == known.epoch && known.frozen && record.state == .active) {
            _ = publish(.unavailable, revision: next)
            return false
        }
        // Remember a trusted denial/higher epoch before observer callbacks.
        // A nested read cannot thaw it while this publication is interrupted.
        known = KnownMembership(epoch: record.binding.epoch, frozen: record.state == .deletionFrozen)
        switch record.state {
        case .active:
            return publish(.active(record.binding), revision: next)
        case .deletionFrozen:
            // The contract decoder requires the exact deterministic ID.
            guard let requestID = record.deletionRequestID else {
                _ = publish(.unavailable, revision: next)
                return false
            }
            return publish(.deletionFrozen(record.binding, requestID: requestID), revision: next)
        }
    }

    @discardableResult
    func failRead(_ ticket: ReadTicket) -> Bool {
        guard owns(ticket) else { return false }
        read = nil
        confirmedDeletionBinding = nil
        return publish(.unavailable, revision: reserve())
    }

    /// Revokes leases/read callbacks without forgetting an observed freeze or
    /// high epoch for this canonical context. No transport is cancelled here.
    func invalidate() {
        read = nil
        confirmedDeletionBinding = nil
        _ = publish(.unresolved, revision: reserve())
    }

    /// The supplied binding belongs to the original intent/outbox record.
    /// Never replace a missing legacy binding with the current active epoch.
    func captureWrite(for original: ContextTicket, binding: Binding?) -> WriteTicket? {
        guard let binding, original == context, canonical.isCurrent(original),
              revision == snapshot.revision, read == nil,
              case .active(let current) = snapshot.status, current == binding,
              current.ownerUID == original.userID else { return nil }
        return WriteTicket(context: original, binding: binding, modelID: modelID, revision: revision)
    }

    func permits(_ ticket: WriteTicket) -> Bool {
        guard ticket.modelID == modelID, ticket.revision == revision, revision == snapshot.revision,
              ticket.context == context, canonical.isCurrent(ticket.context), read == nil,
              case .active(let current) = snapshot.status else { return false }
        return ticket.binding == current && current.ownerUID == ticket.context.userID
    }

    /// A worker atomically freezes the membership before returning its receipt.
    /// Frozen memberships remain eligible for that same deletion request/retry,
    /// while captureWrite deliberately denies them. During a pending explicit
    /// read, retain only the previously committed deletion binding so that
    /// revalidation does not cancel the job that discovers its own freeze.
    /// This is job ownership, not proof of current server state; the server
    /// still validates the original epoch atomically. A failed/current cached
    /// response, absence or explicit invalidation clears that retained binding.
    func deletionEpoch(for original: ContextTicket) -> Int64? {
        guard original == context, canonical.isCurrent(original), revision == snapshot.revision else { return nil }
        switch snapshot.status {
        case .active(let binding), .deletionFrozen(let binding, _):
            return binding.ownerUID == original.userID ? binding.epoch : nil
        case .loading:
            guard read != nil, let binding = confirmedDeletionBinding, binding.ownerUID == original.userID else { return nil }
            return binding.epoch
        case .unresolved, .unavailable, .missing: return nil
        }
    }

    private func owns(_ ticket: ReadTicket) -> Bool {
        ticket.modelID == modelID && read == ticket && ticket.revision == revision
            && ticket.context == context && canonical.isCurrent(ticket.context)
    }
    private func accountChanged() {
        let nextContext = canonical.contextTicket()
        guard nextContext != context else { return }
        context = nextContext
        read = nil
        known = nil
        confirmedDeletionBinding = nil
        _ = publish(.unresolved, revision: reserve())
    }
    private func reserve() -> UUID {
        let next = UUID()
        revision = next
        return next
    }
    @discardableResult
    private func publish(_ status: Status, revision original: UUID) -> Bool {
        guard revision == original, canonical.isCurrent(context) else { return false }
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard revision == original, canonical.isCurrent(context) else { return false }
        snapshot = Snapshot(context: context, status: status, revision: original)
        switch status {
        case .active(let binding), .deletionFrozen(let binding, _): confirmedDeletionBinding = binding
        case .loading: break
        case .unresolved, .unavailable, .missing: confirmedDeletionBinding = nil
        }
        subject.send(snapshot)
        return revision == original && snapshot.revision == original && canonical.isCurrent(context)
    }
}
