import Foundation

/// Owned by the login sheet, not the provider button's visual presence. A native
/// provider presentation or the successful guest→account render is not dismissal.
@MainActor
final class AccountLoginLifetime {
    private(set) var isInvalidated = false
    private var cancellations: [UUID: () -> Void] = [:]

    func register(_ cancel: @escaping () -> Void) -> UUID {
        let id = UUID()
        if isInvalidated { cancel() }
        else { cancellations[id] = cancel }
        return id
    }
    func finish(_ id: UUID) { cancellations.removeValue(forKey: id) }

    /// The email button captures before scheduling its Task. Share the same
    /// lifetime as the introduction so its synchronous denial also reaches a
    /// captured email/reset operation before SwiftUI removes the sheet.
    func captureEmailOperation(_ capture: () throws -> EmailAccountFlowModel.Operation) throws -> EmailAccountFlowModel.Operation {
        guard !isInvalidated else { throw CancellationError() }
        let lease = EmailLease(operation: try capture(), lifetime: self)
        guard !isInvalidated else { lease.cancel(); throw CancellationError() }
        lease.registration = register { [weak lease] in lease?.cancel() }
        guard lease.isAllowed else { lease.cancel(); throw CancellationError() }
        return .init(perform: {
            guard lease.begin() else { throw CancellationError() }
            defer { lease.finish() }
            do {
                let result = try await lease.operation.perform()
                guard lease.isAllowed else { throw CancellationError() }
                return result
            } catch {
                guard lease.isAllowed else { throw CancellationError() }
                throw error
            }
        }, cancel: { lease.cancel() }, feedbackIsCurrent: {
            guard lease.isAllowed else { return false }
            let current = lease.operation.feedbackIsCurrent()
            return lease.isAllowed && current
        })
    }

    @MainActor private final class EmailLease {
        let operation: EmailAccountFlowModel.Operation
        weak var lifetime: AccountLoginLifetime?
        var registration: UUID?
        private var cancelled = false
        private var started = false
        private var returned = false
        init(operation: EmailAccountFlowModel.Operation, lifetime: AccountLoginLifetime) {
            self.operation = operation; self.lifetime = lifetime
        }
        var isAllowed: Bool { !cancelled && lifetime?.isInvalidated == false }
        func begin() -> Bool {
            guard isAllowed, !started, !returned else { return false }
            started = true; return true
        }
        func finish() { returned = true; retireRegistration() }
        func cancel() {
            guard !cancelled, !returned else { return }
            cancelled = true
            // Retire only this registration before a cancellation callback can
            // reenter. Auth retains its own physical SDK slot until completion.
            retireRegistration()
            operation.cancel()
        }
        private func retireRegistration() {
            let original = registration; registration = nil
            if let original { lifetime?.finish(original) }
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        let pending = Array(cancellations.values)
        cancellations.removeAll()
        pending.forEach { $0() }
    }
}
