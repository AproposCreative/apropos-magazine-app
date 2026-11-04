import Combine
import Foundation

/// Presentation provider around the existing Google service and held Firebase
/// reauth helper. It never replaces a Firebase/app login session or calls restore,
/// signOut or disconnect. Google's interactive SDK may update its own session.
@MainActor
final class ReaderGoogleReauthenticationPrompt: ObservableObject {
    typealias Action = ReaderAccountDeletionCoordinator.ActionTicket
    nonisolated let objectWillChange = ObservableObjectPublisher()
    struct CredentialValue: Equatable, Sendable { let idToken: String; let accessToken: String }
    struct Presentation: Identifiable {
        var id: UUID { action.actionID }
        let action: Action
        let isWorking: Bool
    }
    let service: GoogleSignInService
    var presentation: Presentation? {
        guard let active, !active.denied else { return nil }
        return Presentation(action: active.action, isWorking: active.phase != .waiting)
    }
    private enum Phase { case waiting, provider, exchange }
    @MainActor private final class Flight {
        let action: Action
        let subject: String
        let isCurrent: @MainActor () -> Bool
        let onCancel: @MainActor () -> Void
        var phase = Phase.waiting
        var denied = false, cancellationNotified = false
        var providerWait: CheckedContinuation<CredentialValue, Error>?
        var outcomeWait: CheckedContinuation<Void, Error>?
        init(action: Action, subject: String, isCurrent: @escaping @MainActor () -> Bool, onCancel: @escaping @MainActor () -> Void) {
            self.action = action; self.subject = subject; self.isCurrent = isCurrent; self.onCancel = onCancel
        }
    }
    private struct RejectedAuthentication: Error {}
    private let canonical: CanonicalSessionState
    private var active: Flight?
    private var lastActionID: UUID?
    private var observation: AnyCancellable?

    init(canonical: CanonicalSessionState, service: GoogleSignInService) {
        self.canonical = canonical; self.service = service
        observation = canonical.changes.sink { [weak self] _ in self?.canonicalDidChange() }
    }

    func request(action: Action, expectedGoogleUserID: String,
                 isCurrent: @escaping @MainActor () -> Bool,
                 onCancel: @escaping @MainActor () -> Void) async throws -> CredentialValue {
        try Task.checkCancellation()
        guard active == nil, lastActionID != action.actionID, !expectedGoogleUserID.isEmpty,
              expectedGoogleUserID.utf8.count <= 1_024,
              !expectedGoogleUserID.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { throw CancellationError() }
        let flight = Flight(action: action, subject: expectedGoogleUserID, isCurrent: isCurrent, onCancel: onCancel)
        active = flight; lastActionID = action.actionID // Reserve before any injected identity/presentation hook.
        guard owns(flight) else { deny(flight); throw CancellationError() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard owns(flight), !Task.isCancelled else { deny(flight); continuation.resume(throwing: CancellationError()); return }
                flight.providerWait = continuation
                objectWillChange.send()
                if !owns(flight) { deny(flight) }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.cancel(action: action) } })
    }

    /// The button captures the action synchronously before starting this Task.
    /// This method cannot borrow a newer presentation or begin twice.
    func start(action: Action) async {
        guard let flight = active, flight.action == action, flight.phase == .waiting else { return }
        flight.phase = .provider
        objectWillChange.send()
        guard owns(flight), !Task.isCancelled else { deny(flight); settle(flight, error: CancellationError()); return }
        await withTaskCancellationHandler(operation: {
            do {
                let identity = try await service.reauthenticate(action: action, expectedGoogleUserID: flight.subject,
                    isCurrent: { [weak self, weak flight] in
                        guard let self, let flight else { return false }; return self.owns(flight)
                    })
                // Service return is the physical provider callback (or a setup
                // rejection before dispatch), never merely a UI cancellation.
                guard owns(flight), !Task.isCancelled, identity.userID == flight.subject else {
                    deny(flight); settle(flight, error: CancellationError()); return
                }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard owns(flight), !Task.isCancelled, let provider = flight.providerWait, flight.outcomeWait == nil else {
                        deny(flight); settle(flight, error: CancellationError()); continuation.resume(throwing: CancellationError()); return
                    }
                    flight.providerWait = nil; flight.outcomeWait = continuation; flight.phase = .exchange
                    provider.resume(returning: CredentialValue(idToken: identity.idToken, accessToken: identity.accessToken))
                }
            } catch {
                let accepted = owns(flight)
                if !accepted || error is CancellationError { deny(flight); settle(flight, error: CancellationError()) }
                else { settle(flight, error: RejectedAuthentication()) }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.cancel(action: action) } })
    }

    /// The actual held SDK exchange's callback is required to release this wait.
    func complete(action: Action, error: Error? = nil) {
        guard let flight = active, flight.action == action, flight.phase == .exchange else { return }
        if !owns(flight) || error is CancellationError { deny(flight); settle(flight, error: CancellationError()) }
        else { settle(flight, error: error == nil ? nil : RejectedAuthentication()) }
    }
    func cancel(action: Action? = nil) {
        guard let flight = active, action == nil || flight.action == action else { return }
        deny(flight)
    }
    private func owns(_ flight: Flight) -> Bool {
        guard active === flight, !flight.denied, canonical.isCurrent(flight.action.context),
              flight.action.context.userID == flight.action.request.expectedUID else { return false }
        let accepted = flight.isCurrent()
        return accepted && active === flight && !flight.denied && canonical.isCurrent(flight.action.context)
    }
    private func canonicalDidChange() {
        guard let flight = active, !canonical.isCurrent(flight.action.context) else { return }
        deny(flight)
    }
    private func deny(_ flight: Flight) {
        guard active === flight else { return }
        let first = !flight.denied
        flight.denied = true
        service.cancelReauthentication(action: flight.action)
        if !flight.cancellationNotified { flight.cancellationNotified = true; flight.onCancel() }
        guard active === flight else { return }
        if flight.phase == .waiting { settle(flight, error: CancellationError()) }
        else if first { objectWillChange.send() } // Keep provider/SDK continuations until actual completion.
    }
    private func settle(_ flight: Flight, error: Error?) {
        guard active === flight else { return }
        active = nil; flight.denied = true
        let provider = flight.providerWait, outcome = flight.outcomeWait
        flight.providerWait = nil; flight.outcomeWait = nil
        // Existing deletion coordinator owns unavailable/canRetry feedback.
        objectWillChange.send()
        provider?.resume(throwing: error ?? CancellationError())
        if let error { outcome?.resume(throwing: error) } else { outcome?.resume(returning: ()) }
    }
}
