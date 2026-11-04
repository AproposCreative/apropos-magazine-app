import Combine
import Foundation

/// Presentation provider for the existing account-deletion reauth operation.
/// The password wait and the visible form's SDK-outcome wait have distinct owners.
@MainActor
final class ReaderEmailReauthenticationPrompt: ObservableObject {
    typealias Action = ReaderAccountDeletionCoordinator.ActionTicket
    nonisolated let objectWillChange = ObservableObjectPublisher()
    enum State: Equatable { case waitingPassword, verifying, failed }
    struct Presentation: Identifiable {
        var id: UUID { action.actionID }
        let action: Action
        let email: String
        let form: EmailAccountFlowModel
        let state: State
    }
    var presentation: Presentation? {
        guard let active, !active.denied else { return nil }
        return Presentation(action: active.action, email: active.email, form: active.form, state: active.state)
    }
    private final class Flight {
        let action: Action
        let email: String
        let isCurrent: @MainActor () -> Bool
        let onCancel: @MainActor () -> Void
        let onRetry: @MainActor () -> Bool
        var form: EmailAccountFlowModel!
        var state = State.waitingPassword
        var denied = false
        var retrying = false
        var captureID: UUID?
        var password: String?
        var passwordWait: CheckedContinuation<String, Error>?
        var outcomeWait: CheckedContinuation<Void, Error>?
        init(action: Action, email: String, isCurrent: @escaping @MainActor () -> Bool,
             onCancel: @escaping @MainActor () -> Void, onRetry: @escaping @MainActor () -> Bool) {
            self.action = action; self.email = email; self.isCurrent = isCurrent
            self.onCancel = onCancel; self.onRetry = onRetry
        }
    }
    private struct RejectedAuthentication: Error {}
    private let canonical: CanonicalSessionState
    private var active: Flight?
    private var lastActionID: UUID?
    private var observation: AnyCancellable?

    init(canonical: CanonicalSessionState) {
        self.canonical = canonical
        observation = canonical.changes.sink { [weak self] _ in self?.canonicalDidChange() }
    }

    func request(action: Action, email: String,
                 isCurrent: @escaping @MainActor () -> Bool,
                 onCancel: @escaping @MainActor () -> Void,
                 onRetry: @escaping @MainActor () -> Bool) async throws -> String {
        try Task.checkCancellation()
        guard active == nil, lastActionID != action.actionID,
              EmailAccountForm(email: email, password: "validation-only").validationMessage(for: .signIn) == nil else {
            throw CancellationError()
        }
        let flight = Flight(action: action, email: email, isCurrent: isCurrent, onCancel: onCancel, onRetry: onRetry)
        active = flight; lastActionID = action.actionID // Reserve before any injected ownership/publication hook.
        let form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: email), capture: { [weak self, weak flight] _, fields in
            guard let self, let flight else { throw CancellationError() }
            guard self.owns(flight) else { self.retire(flight, notifyCancellation: true); throw CancellationError() }
            guard flight.state == .waitingPassword,
                  flight.captureID == nil, !fields.password.isEmpty else { throw CancellationError() }
            let id = UUID(); flight.captureID = id; flight.password = fields.password
            return .init(perform: { [weak self, weak flight] in
                guard let self, let flight else { throw CancellationError() }
                try await self.submit(flight, captureID: id); return nil
            }, cancel: { [weak self, weak flight] in
                guard let self, let flight, flight.captureID == id else { return }
                self.cancel(action: flight.action)
            }, feedbackIsCurrent: { [weak self, weak flight] in
                guard let self, let flight else { return false }
                return self.owns(flight)
            })
        })
        flight.form = form
        guard owns(flight) else { retire(flight, notifyCancellation: true); throw CancellationError() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard owns(flight), !Task.isCancelled else {
                    retire(flight, notifyCancellation: true); continuation.resume(throwing: CancellationError()); return
                }
                flight.passwordWait = continuation
                objectWillChange.send()
                if !owns(flight) { retire(flight, notifyCancellation: true) }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(action: action) }
        })
    }

    /// Called only after the held user's actual reauthentication helper returns.
    func complete(action: Action, error: Error? = nil) {
        guard let flight = active, flight.action == action, flight.state == .verifying else { return }
        guard owns(flight) else { retire(flight, notifyCancellation: true); return }
        let outcome = flight.outcomeWait
        flight.outcomeWait = nil; flight.password = nil
        if let error {
            if error is CancellationError { retire(flight, notifyCancellation: true); outcome?.resume(throwing: CancellationError()); return }
            flight.state = .failed // Checked completion is now historical UI feedback, not active SDK authority.
            objectWillChange.send()
            if owns(flight) { outcome?.resume(throwing: RejectedAuthentication()) }
            else { retire(flight, notifyCancellation: true); outcome?.resume(throwing: CancellationError()) }
        } else {
            flight.denied = true; active = nil
            // A dismissal must not cancel the now-running deletion HTTP phase.
            objectWillChange.send()
            outcome?.resume(returning: ())
        }
    }

    func cancel(action: Action? = nil) {
        guard let flight = active, action == nil || flight.action == action else { return }
        retire(flight, notifyCancellation: true)
    }

    func retry(action: Action? = nil) {
        guard let flight = active, action == nil || flight.action == action,
              flight.state == .failed, !flight.retrying, owns(flight) else { return }
        flight.retrying = true
        let accepted = flight.onRetry() // Existing coordinator creates a NEW action; it may still hold a physical slot.
        flight.retrying = false
        guard active === flight, owns(flight), accepted else { return }
        retire(flight, notifyCancellation: false)
    }

    private func submit(_ flight: Flight, captureID: UUID) async throws {
        guard owns(flight), !Task.isCancelled else { retire(flight, notifyCancellation: true); throw CancellationError() }
        guard flight.state == .waitingPassword,
              flight.captureID == captureID, flight.password != nil else { throw CancellationError() }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard owns(flight), !Task.isCancelled, flight.outcomeWait == nil,
                      let password = flight.password, let provider = flight.passwordWait else {
                    retire(flight, notifyCancellation: true); continuation.resume(throwing: CancellationError()); return
                }
                flight.password = nil; flight.passwordWait = nil
                flight.outcomeWait = continuation; flight.state = .verifying
                objectWillChange.send()
                guard owns(flight) else {
                    retire(flight, notifyCancellation: true); provider.resume(throwing: CancellationError()); return
                }
                provider.resume(returning: password)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(action: flight.action) }
        })
    }

    private func owns(_ flight: Flight) -> Bool {
        guard active === flight, !flight.denied, canonical.isCurrent(flight.action.context),
              flight.action.context.userID == flight.action.request.expectedUID else { flight.denied = true; return false }
        if flight.state == .failed { return true }
        let accepted = flight.isCurrent()
        guard accepted, active === flight, !flight.denied, canonical.isCurrent(flight.action.context) else {
            flight.denied = true; return false
        }
        return true
    }
    private func canonicalDidChange() {
        guard let flight = active, !canonical.isCurrent(flight.action.context) else { return }
        retire(flight, notifyCancellation: true)
    }
    private func retire(_ flight: Flight, notifyCancellation: Bool) {
        guard active === flight else { return }
        active = nil; flight.denied = true; flight.password = nil
        let password = flight.passwordWait, outcome = flight.outcomeWait
        flight.passwordWait = nil; flight.outcomeWait = nil
        if notifyCancellation { flight.onCancel() }
        flight.form?.cancel() // Exact old form only; its operation callback now sees no active prompt.
        password?.resume(throwing: CancellationError()); outcome?.resume(throwing: CancellationError())
        objectWillChange.send()
    }
}
