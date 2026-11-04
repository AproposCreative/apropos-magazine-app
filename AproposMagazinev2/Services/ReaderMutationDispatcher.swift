import Combine
import Foundation

/// Inactive sender for immutable, already-persisted intents. It never creates
/// membership, rewrites requests or exposes a receipt as current resource state.
/// UI expiry and physical completion have separate lifetimes.
@MainActor
final class ReaderMutationDispatcher {
    typealias Request = ReaderMutationContract.Request
    typealias Acknowledgement = ReaderMutationDispatchStore.Acknowledgement
    typealias Context = CanonicalSessionState.ContextTicket
    typealias Guard = @MainActor () -> Bool
    typealias Sender = @MainActor (Request, @escaping Guard) async throws -> Data
    typealias Schedule = @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void)
    enum Failure: Error, Equatable { case unavailable, stale, busy, timedOut, cancelled, pendingHistory, wrongRequest }

    private final class History {
        let lease: ReaderMutationDispatchStore.Lease
        let data: Data
        init(lease: ReaderMutationDispatchStore.Lease, data: Data) { self.lease = lease; self.data = data }
    }
    private final class Flight {
        enum Mode { case dispatch(Context, ReaderMembershipAuthority.WriteTicket), history }
        let id: UUID
        let lease: ReaderMutationDispatchStore.Lease
        let mode: Mode
        let cancellation: ReaderMutationCancellationFlag
        var continuation: CheckedContinuation<Acknowledgement, Error>?
        var cancelDeadline: (@MainActor () -> Void)?
        var revoked: Failure?
        var sending = false
        init(id: UUID, lease: ReaderMutationDispatchStore.Lease, mode: Mode,
             cancellation: ReaderMutationCancellationFlag, continuation: CheckedContinuation<Acknowledgement, Error>) {
            self.id = id; self.lease = lease; self.mode = mode; self.cancellation = cancellation
            self.continuation = continuation
        }
    }

    private let canonical: CanonicalSessionState
    private let membership: ReaderMembershipAuthority
    private let store: ReaderMutationDispatchStore
    private let send: Sender
    private let schedule: Schedule
    private var flight: Flight?
    // At most one validated, bounded receipt is retained, with its shared store
    // reservation. An ACK failure cannot allow another runner to resend it.
    private var history: History?
    private var observations: [AnyCancellable] = []
    var isBusy: Bool { flight != nil }
    var hasPendingHistory: Bool { history != nil }

    init(canonical: CanonicalSessionState, membership: ReaderMembershipAuthority,
         store: ReaderMutationDispatchStore, send: @escaping Sender, schedule: Schedule? = nil) {
        self.canonical = canonical; self.membership = membership; self.store = store; self.send = send
        self.schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                action()
            }
            return { task.cancel() }
        }
        observations = [canonical.changes.sink { [weak self] _ in self?.authorityChanged() },
                        membership.changes.sink { [weak self] _ in self?.authorityChanged() }]
    }

    func dispatch(context: Context, request: Request) async throws -> Acknowledgement {
        let cancellation = ReaderMutationCancellationFlag(), id = UUID()
        var original: Flight?
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Acknowledgement, Error>) in
                guard !cancellation.isCancelled, !Task.isCancelled else { continuation.resume(throwing: Failure.cancelled); return }
                guard flight == nil else { continuation.resume(throwing: Failure.busy); return }
                guard history == nil else { continuation.resume(throwing: Failure.pendingHistory); return }
                guard canonical.isCurrent(context), context.userID == request.expectedUID,
                      let member = membership.captureWrite(for: context, binding: request.binding) else {
                    continuation.resume(throwing: Failure.unavailable); return
                }
                guard let lease = store.reserve(request: request) else { continuation.resume(throwing: Failure.busy); return }
                let held = Flight(id: id, lease: lease, mode: .dispatch(context, member),
                                  cancellation: cancellation, continuation: continuation)
                flight = held; original = held // Reserve before any injected schedule hook.
                installDeadline(held)
                // An independent task keeps every physical callback/file step
                // alive after the caller's cancellation. Never cancel this task.
                Task { @MainActor [self] in await self.perform(held) }
            }
        } onCancel: { [self] in
            cancellation.cancel()
            Task { @MainActor in self.cancel(id) }
        }
        guard !cancellation.isCancelled, !Task.isCancelled else { throw Failure.cancelled }
        guard let original, original.revoked == nil, authorityMatches(original) else { throw Failure.stale }
        return result
    }

    /// Explicit history-only recovery. The already validated original receipt
    /// may be persisted for A while B is current; this grants B no authority.
    /// A new dispatch is never a substitute for saving this known receipt.
    func retryPersistence(request: Request) async throws -> Acknowledgement {
        let cancellation = ReaderMutationCancellationFlag(), id = UUID()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Acknowledgement, Error>) in
                guard !cancellation.isCancelled, !Task.isCancelled else { continuation.resume(throwing: Failure.cancelled); return }
                guard flight == nil else { continuation.resume(throwing: Failure.busy); return }
                guard let history, store.owns(history.lease) else { continuation.resume(throwing: Failure.unavailable); return }
                let held = Flight(id: id, lease: history.lease, mode: .history,
                                  cancellation: cancellation, continuation: continuation)
                flight = held
                installDeadline(held)
                Task { @MainActor [self] in await self.persistHistory(held, history: history, requested: request) }
            }
        } onCancel: { [self] in
            cancellation.cancel()
            Task { @MainActor in self.cancel(id) }
        }
        guard !cancellation.isCancelled, !Task.isCancelled else { throw Failure.cancelled }
        return result
    }

    private func installDeadline(_ held: Flight) {
        let cancel = schedule { [weak self, weak held] in
            guard let self, let held, self.flight === held else { return }
            self.revoke(held, reason: .timedOut)
        }
        if held.continuation == nil { cancel() } else { held.cancelDeadline = cancel }
    }
    private func authorityMatches(_ held: Flight) -> Bool {
        switch held.mode {
        case .history: return true
        case .dispatch(let context, let member):
            return canonical.isCurrent(context) && membership.permits(member)
        }
    }
    private func permitted(_ held: Flight) -> Bool {
        flight === held && held.revoked == nil && !held.cancellation.isCancelled
            && store.owns(held.lease) && authorityMatches(held)
    }
    private func check(_ held: Flight) throws {
        guard permitted(held) else { throw held.revoked ?? (held.cancellation.isCancelled ? Failure.cancelled : Failure.stale) }
    }

    private func perform(_ held: Flight) async {
        do {
            try check(held)
            let entry = try await store.load(held.lease)
            try check(held)
            let data: Data
            if let saved = entry.receiptData { data = saved }
            else {
                held.sending = true
                data = try await send(held.lease.request, { [weak self, weak held] in
                    guard let self, let held else { return false }
                    return held.sending && self.permitted(held)
                })
                held.sending = false
            }
            // A returned valid receipt is original-owner history even when the
            // caller has expired or the account changed during physical send.
            let original = held.lease.request
            _ = try await Task.detached(priority: .utility) {
                try ReaderMutationContract.decodeReceipt(data: data, for: original)
            }.value
            let known = History(lease: held.lease, data: data)
            history = known
            let acknowledged = try await store.acknowledge(held.lease, receiptData: data)
            if history === known { history = nil }
            finish(held, result: .success(acknowledged))
        } catch {
            held.sending = false
            finish(held, result: .failure(error))
        }
    }
    private func persistHistory(_ held: Flight, history original: History, requested: Request) async {
        do {
            try check(held)
            let stored = original.lease.request
            let matches = await Task.detached(priority: .utility) { stored == requested }.value
            try check(held)
            guard matches, history === original else { throw Failure.wrongRequest }
            let acknowledged = try await store.acknowledge(held.lease, receiptData: original.data)
            if history === original { history = nil }
            finish(held, result: .success(acknowledged))
        } catch { finish(held, result: .failure(error)) }
    }
    private func finish(_ held: Flight, result: Result<Acknowledgement, Error>) {
        guard flight === held else { return }
        held.sending = false
        finishUI(held, result: result)
        // Both async journal methods have returned physically. A failed ACK
        // deliberately retains its lease together with the one history record.
        if history == nil {
            guard store.release(held.lease) else { return } // Fail closed on an unexpected occupied store.
        }
        if flight === held { flight = nil }
    }
    private func finishUI(_ held: Flight, result: Result<Acknowledgement, Error>) {
        guard let waiting = held.continuation else { return }
        held.continuation = nil
        let cancel = held.cancelDeadline; held.cancelDeadline = nil
        cancel?() // May reenter the account or scheduler; all ownership is rechecked below.
        guard permitted(held) else {
            waiting.resume(throwing: held.revoked ?? (held.cancellation.isCancelled ? Failure.cancelled : Failure.stale)); return
        }
        waiting.resume(with: result)
    }
    private func revoke(_ held: Flight, reason: Failure) {
        guard flight === held else { return }
        if held.revoked == nil { held.revoked = reason }
        finishUI(held, result: .failure(reason))
    }
    private func cancel(_ id: UUID) {
        guard let held = flight, held.id == id else { return }
        revoke(held, reason: .cancelled)
    }
    private func authorityChanged() {
        guard let held = flight, !authorityMatches(held) else { return }
        revoke(held, reason: .stale)
    }
}

/// Mark cancellation before its MainActor delivery, so a queued load callback
/// cannot start transport in that scheduling window.
private final class ReaderMutationCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
