import Combine
import Foundation

/// Process-local admission barrier for the integrated legacy SDK writers. No SDK or
/// work starts in init. A local drain receipt is never membership, migration,
/// resource-revision or endpoint authority, and is never persisted across restart.
@MainActor
final class ReaderWriterDrainCoordinator {
    typealias ContextTicket = CanonicalSessionState.ContextTicket
    typealias Guard = @MainActor () -> Bool
    typealias Completion = @Sendable (Error?) -> Void
    typealias Start = @MainActor (@escaping Guard, @escaping Completion) -> Void
    typealias DrainStart = @MainActor (ContextTicket, @escaping Guard, @escaping Completion) -> Void
    typealias Schedule = @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void)
    enum Failure: Error, Equatable { case stale, stopped, busy, timedOut, cancelled, failed, limitExceeded }

    struct StopTicket: Equatable {
        let context: ContextTicket
        fileprivate let coordinatorID: UUID
        fileprivate let id: UUID
    }
    struct Receipt: Equatable {
        let context: ContextTicket
        fileprivate let stop: StopTicket
        fileprivate let attemptID: UUID
    }
    private final class Write {
        let id: UUID
        let context: ContextTicket
        let stillCurrent: Guard
        let cancellation: ReaderWriterCancellationSignal
        var continuation: CheckedContinuation<Void, Error>?
        var awaitingCallback = false
        init(id: UUID, context: ContextTicket, stillCurrent: @escaping Guard,
             cancellation: ReaderWriterCancellationSignal, continuation: CheckedContinuation<Void, Error>) {
            self.id = id; self.context = context; self.stillCurrent = stillCurrent
            self.cancellation = cancellation; self.continuation = continuation
        }
    }
    private final class Drain {
        let id: UUID
        let stop: StopTicket
        let cancellation: ReaderWriterCancellationSignal
        var continuation: CheckedContinuation<Receipt, Error>?
        var cancelDeadline: (@MainActor () -> Void)?
        var awaitingCallback = false
        init(id: UUID, stop: StopTicket, cancellation: ReaderWriterCancellationSignal,
             continuation: CheckedContinuation<Receipt, Error>) {
            self.id = id; self.stop = stop; self.cancellation = cancellation; self.continuation = continuation
        }
    }

    private let canonical: CanonicalSessionState
    private let actualUID: @MainActor () -> String?
    private let schedule: Schedule
    private let drainStart: DrainStart
    private let maximumActiveWrites: Int
    private let id = UUID()
    private var writes: [UUID: Write] = [:]
    private var stop: StopTicket?
    private var draining: Drain?
    private var receipt: Receipt?
    private var physicalIdleWaiter: CheckedContinuation<Void, Error>?
    // Once any journal transition can have committed, legacy writes may never
    // reopen in this process, even after replacing a stale account stop.
    private var recoverySealed = false
    private var observation: AnyCancellable?
    var isStopped: Bool { stop != nil }
    var activeWriteCount: Int { writes.count }
    var isDrainInFlight: Bool { draining != nil }

    /// The exclusive transition owner may await actual callback retirement
    /// after a logical drain timeout/cancellation. Cancellation deliberately
    /// does not complete this waiter or imply that an SDK operation returned.
    func waitForPhysicalIdle() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard physicalIdleWaiter == nil else { continuation.resume(throwing: Failure.busy); return }
            physicalIdleWaiter = continuation
            completePhysicalIdleWaiter()
        }
    }

    private func completePhysicalIdleWaiter() {
        guard writes.isEmpty, draining == nil, let waiting = physicalIdleWaiter else { return }
        physicalIdleWaiter = nil
        waiting.resume()
    }

    init(canonical: CanonicalSessionState, actualUID: @escaping @MainActor () -> String?,
         schedule: Schedule? = nil, drainStart: @escaping DrainStart, maximumActiveWrites: Int = 16) {
        precondition((1...256).contains(maximumActiveWrites))
        self.canonical = canonical; self.actualUID = actualUID; self.drainStart = drainStart
        self.maximumActiveWrites = maximumActiveWrites
        self.schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                action()
            }
            return { task.cancel() }
        }
        observation = canonical.changes.sink { [weak self] _ in self?.accountChanged() }
    }

    /// The adapter must check lastGuard immediately before SDK enqueue, and
    /// invoke completion even when that guard refuses. Once start is entered,
    /// only its real callback frees the occupied physical registration.
    func performWrite(context: ContextTicket, stillCurrent: @escaping Guard, start: Start) async throws {
        let operationID = UUID(), cancellation = ReaderWriterCancellationSignal()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !cancellation.isCancelled, !Task.isCancelled else { continuation.resume(throwing: Failure.cancelled); return }
                guard canonical.isCurrent(context), context.userID != nil else { continuation.resume(throwing: Failure.stale); return }
                guard !isStopped else { continuation.resume(throwing: Failure.stopped); return }
                guard writes.count < maximumActiveWrites else { continuation.resume(throwing: Failure.limitExceeded); return }
                let held = Write(id: operationID, context: context, stillCurrent: stillCurrent,
                                 cancellation: cancellation, continuation: continuation)
                writes[operationID] = held // Before either injected getter or start.
                guard mayStart(held) else { rejectUnstartedWrite(held); return }
                held.awaitingCallback = true
                start({ [weak self, weak held] in
                    guard let self, let held else { return false }
                    return self.mayStart(held)
                }, { [self] error in Task { @MainActor in self.writeReturned(operationID, error: error) } })
            }
            // Cancellation can race with an already resumed continuation.
            guard !cancellation.isCancelled, !Task.isCancelled else { throw Failure.cancelled }
        } onCancel: { [self] in
            cancellation.cancel()
            Task { @MainActor in self.cancelWrite(operationID) }
        }
    }

    /// Synchronous event capture: closes admission before any await. A stale
    /// stop may be replaced for a new generation only after all physical work
    /// returns. The barrier never reopens automatically, including on failure.
    func stopWrites(context: ContextTicket) -> StopTicket? {
        guard canonical.isCurrent(context), context.userID != nil else { return nil }
        if let stop {
            if stop.context == context { return stop }
            guard writes.isEmpty, draining == nil else { return nil }
        }
        let ticket = StopTicket(context: context, coordinatorID: id, id: UUID())
        stop = ticket; receipt = nil
        return ticket
    }

    /// Explicitly abandon the original stop before the caller starts any
    /// journal/server transition. The mandatory predicate must be a pure check
    /// of the caller's original action and pre-transition phase; this local
    /// coordinator cannot prove that an external mutation never happened.
    /// No timeout, cancellation or late callback calls this automatically.
    @discardableResult
    func abortStop(_ original: StopTicket, stillBeforeTransition: Guard) -> Bool {
        guard canAbort(original) else { return false }
        let before = stillBeforeTransition()
        guard before, canAbort(original) else { return false }
        let uid = actualUID()
        if uid != original.context.userID, receipt?.stop == original { receipt = nil }
        guard uid == original.context.userID, canAbort(original) else { return false }
        // An injected identity getter may reenter the owning transition. Read
        // its pure phase check again, then commit with only local checks left.
        let after = stillBeforeTransition()
        guard after, canAbort(original) else { return false }
        receipt = nil
        stop = nil
        return true
    }

    /// Seal immediately before an irreversible/possibly committed transition.
    /// This does not certify that transition or invalidate the current drain
    /// receipt; it only permanently removes the local legacy-reopen option.
    @discardableResult
    func sealStop(_ original: StopTicket) -> Bool {
        guard owns(original), writes.isEmpty, draining == nil else { return false }
        let uid = actualUID()
        guard uid == original.context.userID, owns(original), writes.isEmpty, draining == nil else { return false }
        recoverySealed = true
        return true
    }

    func drain(_ ticket: StopTicket) async throws -> Receipt {
        let attemptID = UUID(), cancellation = ReaderWriterCancellationSignal()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Receipt, Error>) in
                guard !cancellation.isCancelled, !Task.isCancelled else { continuation.resume(throwing: Failure.cancelled); return }
                guard owns(ticket) else { continuation.resume(throwing: Failure.stale); return }
                guard draining == nil else { continuation.resume(throwing: Failure.busy); return }
                let held = Drain(id: attemptID, stop: ticket, cancellation: cancellation, continuation: continuation)
                draining = held; receipt = nil // Reserve before injected hooks.
                guard drainPermitted(held) else { finishDrainUI(held, result: .failure(Failure.stale)); pumpDrain(); return }
                let cancel = schedule { [weak self, weak held] in
                    guard let self, let held, self.draining === held else { return }
                    self.finishDrainUI(held, result: .failure(Failure.timedOut))
                    self.pumpDrain()
                }
                if held.continuation == nil { cancel() } else { held.cancelDeadline = cancel }
                pumpDrain()
            }
        } onCancel: { [self] in
            cancellation.cancel()
            Task { @MainActor in self.cancelDrain(attemptID) }
        }
        guard !cancellation.isCancelled, !Task.isCancelled else { throw Failure.cancelled }
        guard isCurrent(result) else { throw Failure.stale }
        return result
    }

    func isCurrent(_ value: Receipt) -> Bool {
        guard receipt == value, owns(value.stop), writes.isEmpty, draining == nil else { return false }
        let uid = actualUID()
        if uid != value.context.userID, receipt == value { receipt = nil }
        return uid == value.context.userID && receipt == value && owns(value.stop) && writes.isEmpty && draining == nil
    }

    private func writeOwned(_ held: Write) -> Bool {
        held.continuation != nil && !held.cancellation.isCancelled && canonical.isCurrent(held.context)
    }
    private func mayStart(_ held: Write) -> Bool {
        guard writes[held.id] === held, !isStopped, writeOwned(held) else { return false }
        let current = held.stillCurrent()
        guard current, writes[held.id] === held, !isStopped, writeOwned(held) else { return false }
        let uid = actualUID()
        return uid == held.context.userID && writes[held.id] === held && !isStopped && writeOwned(held)
    }
    private func completionOwned(_ held: Write) -> Bool {
        guard writeOwned(held) else { return false }
        let current = held.stillCurrent()
        guard current, writeOwned(held) else { return false }
        let uid = actualUID()
        return uid == held.context.userID && writeOwned(held)
    }
    private func finishWriteUI(_ held: Write, error: Error?) {
        let waiting = held.continuation; held.continuation = nil
        if let error { waiting?.resume(throwing: error) } else { waiting?.resume() }
    }
    private func rejectUnstartedWrite(_ held: Write) {
        defer { completePhysicalIdleWaiter() }
        guard writes[held.id] === held, !held.awaitingCallback else { return }
        writes.removeValue(forKey: held.id)
        finishWriteUI(held, error: held.cancellation.isCancelled ? Failure.cancelled : (isStopped ? Failure.stopped : Failure.stale))
        pumpDrain()
    }
    private func cancelWrite(_ operationID: UUID) {
        defer { completePhysicalIdleWaiter() }
        guard let held = writes[operationID] else { return }
        // Existing callers also own physical transport slots. Keep their await
        // suspended until the real SDK callback; cancellation only revokes it.
        guard !held.awaitingCallback else { return }
        writes.removeValue(forKey: operationID)
        finishWriteUI(held, error: Failure.cancelled)
        pumpDrain()
    }
    private func writeReturned(_ operationID: UUID, error: Error?) {
        defer { completePhysicalIdleWaiter() }
        guard let held = writes.removeValue(forKey: operationID) else { return }
        if held.continuation != nil {
            let owned = completionOwned(held)
            let failure = held.cancellation.isCancelled ? Failure.cancelled : Failure.stale
            finishWriteUI(held, error: owned ? error : failure)
        }
        pumpDrain()
    }
    private func owns(_ ticket: StopTicket) -> Bool {
        ticket.coordinatorID == id && stop == ticket && canonical.isCurrent(ticket.context) && ticket.context.userID != nil
    }
    private func canAbort(_ ticket: StopTicket) -> Bool {
        !recoverySealed && owns(ticket) && writes.isEmpty && draining == nil
    }
    private func drainPermitted(_ held: Drain) -> Bool {
        guard draining === held, held.continuation != nil, !held.cancellation.isCancelled, owns(held.stop) else { return false }
        let uid = actualUID()
        return uid == held.stop.context.userID && draining === held && held.continuation != nil
            && !held.cancellation.isCancelled && owns(held.stop)
    }
    private func pumpDrain() {
        defer { completePhysicalIdleWaiter() }
        guard let held = draining, !held.awaitingCallback, writes.isEmpty else { return }
        guard drainPermitted(held) else {
            if held.continuation != nil {
                finishDrainUI(held, result: .failure(held.cancellation.isCancelled ? Failure.cancelled : Failure.stale))
            }
            if draining === held { draining = nil }
            return
        }
        held.awaitingCallback = true
        drainStart(held.stop.context, { [weak self, weak held] in
            guard let self, let held else { return false }
            return self.writes.isEmpty && self.drainPermitted(held)
        }, { [self] error in Task { @MainActor in self.drainReturned(held.id, error: error) } })
    }
    private func drainReturned(_ attemptID: UUID, error: Error?) {
        defer { completePhysicalIdleWaiter() }
        guard let held = draining, held.id == attemptID, held.awaitingCallback else { return }
        // The physical callback has returned. Clear its slot before arbitrary
        // deadline cancellation/getters; those can reserve a newer operation.
        let permitted = drainPermitted(held) && writes.isEmpty
        guard draining === held else { return }
        draining = nil
        guard held.continuation != nil else { return }
        if permitted, error == nil {
            let value = Receipt(context: held.stop.context, stop: held.stop, attemptID: held.id)
            receipt = value
            finishDrainUI(held, result: .success(value))
        } else {
            finishDrainUI(held, result: .failure(held.cancellation.isCancelled ? Failure.cancelled : (permitted ? Failure.failed : Failure.stale)))
        }
    }
    private func finishDrainUI(_ held: Drain, result: Result<Receipt, Error>) {
        guard let waiting = held.continuation else { return }
        held.continuation = nil
        let cancel = held.cancelDeadline; held.cancelDeadline = nil
        cancel?()
        switch result {
        case .success(let value):
            guard !held.cancellation.isCancelled, isCurrent(value) else {
                waiting.resume(throwing: held.cancellation.isCancelled ? Failure.cancelled : Failure.stale); return
            }
            waiting.resume(returning: value)
        case .failure(let error): waiting.resume(throwing: error)
        }
    }
    private func cancelDrain(_ attemptID: UUID) {
        if receipt?.attemptID == attemptID { receipt = nil }
        guard let held = draining, held.id == attemptID else { return }
        finishDrainUI(held, result: .failure(Failure.cancelled))
        pumpDrain()
    }
    private func accountChanged() {
        if let receipt, !owns(receipt.stop) { self.receipt = nil }
        for held in Array(writes.values) where !canonical.isCurrent(held.context) {
            guard !held.awaitingCallback else { continue }
            writes.removeValue(forKey: held.id)
            finishWriteUI(held, error: Failure.stale)
        }
        if let held = draining, !owns(held.stop) { finishDrainUI(held, result: .failure(Failure.stale)) }
        pumpDrain()
    }
}

/// Cancellation is recorded synchronously before hopping back to MainActor.
/// Thus a callback cannot start a drain while cancellation delivery is queued.
private final class ReaderWriterCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
