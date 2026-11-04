import Foundation

/// The production verification/refresh pipeline with explicit SDK boundaries.
/// Construction is inert; an occupied transport slot is released only when its
/// actual injected provider returns, including across account changes.
@MainActor
final class ReaderAccountVerificationCoordinator {
    typealias Guard = @MainActor () -> Bool
    struct Effects {
        let actualUserID: @MainActor () -> String?
        let send: @MainActor (CanonicalSessionState.VerificationTicket, @escaping Guard) async throws -> Void
        let refresh: @MainActor (CanonicalSessionState.RefreshTicket, @escaping Guard) async throws -> ReaderAccountSession
    }
    enum Failure: Error { case incorrectAccount }

    let state: CanonicalSessionState
    private let effects: Effects
    private var sending = false
    private var refreshing = false
    var activity: (sending: Bool, refreshing: Bool) { (sending, refreshing) }
    private static let busyMessage = "En tidligere anmodning afsluttes stadig. Prøv igen om lidt."
    private static let refreshFailure = "Kunne ikke kontrollere e-mailen. Prøv igen, når du er online."

    init(state: CanonicalSessionState, effects: Effects) { self.state = state; self.effects = effects }

    func sendVerification(context: CanonicalSessionState.ContextTicket) async {
        guard permits(context) else { return }
        guard !sending else { reportBusy(context); return }
        sending = true
        defer { sending = false }
        guard let ticket = state.beginVerification(context: context, stillPermitted: { self.permits(context) }),
              permits(ticket) else { return }
        do {
            guard permits(ticket) else { return }
            try await effects.send(ticket, { [weak self] in self?.permits(ticket) ?? false })
            guard permits(ticket) else { return }
            _ = state.finishVerification(ticket: ticket,
                message: "Bekræftelsesmail sendt. Åbn linket i mailen, og vend tilbage hertil.",
                stillPermitted: { self.permits(ticket) })
        } catch {
            guard permits(ticket) else { return }
            _ = state.finishVerification(ticket: ticket,
                message: "Bekræftelsesmailen kunne ikke sendes. Prøv igen herfra.",
                stillPermitted: { self.permits(ticket) })
        }
    }

    func refreshSession(context: CanonicalSessionState.ContextTicket) async throws {
        guard permits(context) else { return }
        guard !refreshing else { reportBusy(context); return }
        refreshing = true
        defer { refreshing = false }
        guard let ticket = state.beginRefresh(context: context, stillPermitted: { self.permits(context) }),
              permits(ticket) else { return }
        do {
            guard permits(ticket) else { return }
            let original = try await effects.refresh(ticket, { [weak self] in self?.permits(ticket) ?? false })
            guard permits(ticket) else { return }
            guard original.uid == ticket.userID else { throw Failure.incorrectAccount }
            _ = state.acceptRefresh(original, ticket: ticket, stillPermitted: { self.permits(ticket) })
        } catch {
            guard permits(ticket) else { return }
            let accepted = state.failRefresh(ticket: ticket, message: Self.refreshFailure,
                stillPermitted: { self.permits(ticket) })
            guard accepted, permits(context) else { return }
            throw error
        }
    }

    private func reportBusy(_ context: CanonicalSessionState.ContextTicket) {
        guard permits(context) else { return }
        _ = state.reportUnavailableAction(context: context, message: Self.busyMessage,
            stillPermitted: { self.permits(context) })
    }
    private func permits(_ context: CanonicalSessionState.ContextTicket) -> Bool {
        let actual = effects.actualUserID()
        return state.isCurrent(context) && context.userID != nil && actual == context.userID
    }
    private func permits(_ ticket: CanonicalSessionState.VerificationTicket) -> Bool {
        let actual = effects.actualUserID()
        return state.isCurrent(ticket) && ticket.userID != nil && actual == ticket.userID
    }
    private func permits(_ ticket: CanonicalSessionState.RefreshTicket) -> Bool {
        let actual = effects.actualUserID()
        return state.isCurrent(ticket) && ticket.userID != nil && actual == ticket.userID
    }
}
