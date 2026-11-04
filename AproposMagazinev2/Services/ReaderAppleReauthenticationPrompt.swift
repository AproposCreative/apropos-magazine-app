import Combine
import Foundation

/// Apple credential presentation for one existing deletion action. The actual
/// provider callback and held SDK exchange own distinct physical reservations.
@MainActor
final class ReaderAppleReauthenticationPrompt: ObservableObject {
    typealias Action = ReaderAccountDeletionCoordinator.ActionTicket
    nonisolated let objectWillChange = ObservableObjectPublisher()
    struct CredentialValue: Equatable, Sendable { let idToken: String; let rawNonce: String }
    struct Presentation: Identifiable {
        var id: UUID { action.actionID }
        let action: Action
        let flow: AppleAccountFlowModel
    }
    var presentation: Presentation? {
        guard let active, !active.denied else { return nil }
        return Presentation(action: active.action, flow: active.flow)
    }
    private enum Phase { case waiting, provider, providerReturned, exchange }
    private final class Flight {
        let action: Action
        let expectedAppleUserID: String
        let isCurrent: @MainActor () -> Bool
        let onCancel: @MainActor () -> Void
        var flow: AppleAccountFlowModel!
        var phase = Phase.waiting
        var denied = false, cancellationNotified = false
        var providerWait: CheckedContinuation<CredentialValue, Error>?
        var outcomeWait: CheckedContinuation<Void, Error>?
        init(action: Action, expectedAppleUserID: String, isCurrent: @escaping @MainActor () -> Bool,
             onCancel: @escaping @MainActor () -> Void) {
            self.action = action; self.expectedAppleUserID = expectedAppleUserID
            self.isCurrent = isCurrent; self.onCancel = onCancel
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

    func request(action: Action, expectedAppleUserID: String,
                 isCurrent: @escaping @MainActor () -> Bool,
                 onCancel: @escaping @MainActor () -> Void) async throws -> CredentialValue {
        try Task.checkCancellation()
        guard active == nil, lastActionID != action.actionID,
              !expectedAppleUserID.isEmpty, expectedAppleUserID.utf8.count <= 1_024,
              !expectedAppleUserID.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw CancellationError()
        }
        let flight = Flight(action: action, expectedAppleUserID: expectedAppleUserID, isCurrent: isCurrent, onCancel: onCancel)
        active = flight; lastActionID = action.actionID
        flight.flow = AppleAccountFlowModel(purpose: .reauthentication, preparationFailed: { [weak self, weak flight] in
            guard let self, let flight, self.active === flight, flight.phase == .waiting else { return }
            self.settle(flight, error: RejectedAuthentication())
        }, capture: { [weak self, weak flight] in
            guard let self, let flight else { throw CancellationError() }
            guard self.owns(flight), flight.phase == .waiting else {
                self.deny(flight); throw CancellationError()
            }
            flight.phase = .provider // The model drains an unpresented begin through providerFailed.
            return .init(perform: { [weak self, weak flight] token, nonce, _ in
                guard let self, let flight else { throw CancellationError() }
                try await self.exchange(flight, credential: CredentialValue(idToken: token, rawNonce: nonce)); return nil
            }, providerReturned: { [weak self, weak flight] in
                guard let self, let flight else { throw CancellationError() }
                try self.providerReturned(flight)
            }, providerFailed: { [weak self, weak flight] in
                guard let self, let flight else { return false }
                return self.providerFailed(flight)
            }, cancel: { [weak self, weak flight] in
                guard let self, let flight else { return }
                self.cancelFromFlow(flight)
            }, feedbackIsCurrent: { [weak self, weak flight] in
                guard let self, let flight else { return false }
                return self.owns(flight)
            }, expectedAppleUserID: flight.expectedAppleUserID)
        })
        guard owns(flight) else { deny(flight); throw CancellationError() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard owns(flight), !Task.isCancelled else {
                    deny(flight); continuation.resume(throwing: CancellationError()); return
                }
                flight.providerWait = continuation
                objectWillChange.send()
                if !owns(flight) { deny(flight) }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(action: action) }
        })
    }

    /// Only the actual held SDK reauthentication's return can release exchange.
    func complete(action: Action, error: Error? = nil) {
        guard let flight = active, flight.action == action, flight.phase == .exchange else { return }
        let accepted = owns(flight)
        if !accepted || error is CancellationError {
            deny(flight)
            settle(flight, error: CancellationError())
        } else {
            settle(flight, error: error == nil ? nil : RejectedAuthentication())
        }
    }

    func cancel(action: Action? = nil) {
        guard let flight = active, action == nil || flight.action == action else { return }
        deny(flight)
    }

    private func providerReturned(_ flight: Flight) throws {
        guard active === flight, flight.phase == .provider else { throw CancellationError() }
        flight.phase = .providerReturned // This physical callback arrived, even if its credentials will be rejected.
        guard owns(flight) else { deny(flight); throw CancellationError() }
    }
    private func providerFailed(_ flight: Flight) -> Bool {
        guard active === flight, flight.phase == .provider || flight.phase == .providerReturned else { return false }
        flight.phase = .providerReturned
        let accepted = owns(flight)
        if !accepted { deny(flight) }
        settle(flight, error: accepted ? RejectedAuthentication() : CancellationError())
        return accepted
    }
    private func cancelFromFlow(_ flight: Flight) {
        guard active === flight else { return }
        if flight.phase == .providerReturned, !flight.denied {
            // Invalid state/token/Apple subject is a completed provider failure,
            // not a new user cancellation or a second SDK credential attempt.
            settle(flight, error: RejectedAuthentication())
        } else { deny(flight) }
    }

    private func exchange(_ flight: Flight, credential: CredentialValue) async throws {
        guard active === flight, flight.phase == .providerReturned else { throw CancellationError() }
        guard owns(flight), !Task.isCancelled else { deny(flight); throw CancellationError() }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard owns(flight), !Task.isCancelled, flight.outcomeWait == nil, let provider = flight.providerWait else {
                    deny(flight); continuation.resume(throwing: CancellationError()); return
                }
                flight.providerWait = nil; flight.outcomeWait = continuation; flight.phase = .exchange
                // Install the outcome wait before delivering credentials. No
                // identity token or nonce remains stored in presentation state.
                provider.resume(returning: credential)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(action: flight.action) }
        })
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
        if !flight.cancellationNotified {
            flight.cancellationNotified = true
            flight.onCancel()
        }
        guard active === flight else { return }
        if first, let ticket = flight.flow?.activeTicketID { flight.flow.cancel(ticketID: ticket) }
        guard active === flight else { return }
        switch flight.phase {
        case .waiting, .providerReturned:
            settle(flight, error: CancellationError())
        case .provider, .exchange:
            // Hiding/cancelling native UI is not a provider/SDK acknowledgement.
            // Retain both original continuations and reject any replacement.
            if first { objectWillChange.send() }
        }
    }
    private func settle(_ flight: Flight, error: Error?) {
        guard active === flight else { return }
        active = nil; flight.denied = true
        let provider = flight.providerWait, outcome = flight.outcomeWait
        flight.providerWait = nil; flight.outcomeWait = nil
        // The existing deletion coordinator owns failure/retry presentation.
        // This provider sheet cannot retry credentials on an already-used action.
        objectWillChange.send()
        // A success is only possible after credentials were already delivered.
        provider?.resume(throwing: error ?? CancellationError())
        if let error { outcome?.resume(throwing: error) } else { outcome?.resume(returning: ()) }
    }
}
