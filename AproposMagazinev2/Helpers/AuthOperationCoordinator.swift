import Foundation

/// An immutable receipt for one explicit login, never inferred from profile data
/// or a general account-state observation.
struct ReaderLoginResult: Equatable {
    let originalContext: CanonicalSessionState.ContextTicket
    let acceptedContext: CanonicalSessionState.ContextTicket
    let session: ReaderAccountSession
    let isNewUser: Bool
    let actionID: UUID
}

/// One real provider/identity-mutation slot shared by all native login entry
/// points. Cancellation revokes an intent; it cannot cancel an accepted SDK call.
@MainActor
final class AuthOperationCoordinator {
    enum Kind: Equatable { case google, apple, emailSignIn, emailSignUp, passwordReset, signOut, reauthentication }
    enum Failure: Error {
        case busy
        var message: String { "Et login er stadig ved at blive afsluttet. Vent et øjeblik, og prøv igen." }
    }
    final class Ticket {
        fileprivate enum Phase { case reserved, provider, exchange, finished }
        let kind: Kind
        let actionID = UUID()
        let context: CanonicalSessionState.ContextTicket
        let newsletterOptIn: Bool
        fileprivate let coordinatorID: UUID
        /// Selected once from the original model-bound context. In particular,
        /// Auth-only reauth never rebinds to a later reader session with that UID.
        fileprivate let identity: CanonicalSessionState
        fileprivate var phase = Phase.reserved
        fileprivate var revoked = false
        fileprivate var receipt: CanonicalSessionState.ContextTicket?
        fileprivate var loginResult: ReaderLoginResult?
        fileprivate init(kind: Kind, context: CanonicalSessionState.ContextTicket, coordinatorID: UUID,
                         identity: CanonicalSessionState, newsletterOptIn: Bool = false) {
            self.kind = kind; self.context = context; self.coordinatorID = coordinatorID; self.identity = identity
            self.newsletterOptIn = newsletterOptIn && kind != .passwordReset && kind != .signOut && kind != .reauthentication
        }
    }
    private let canonical: CanonicalSessionState
    private let reauthenticationIdentity: CanonicalSessionState?
    private let actualUserID: () -> String?
    private let id = UUID()
    private var admission = UUID()
    private var active: Ticket?
    private var latest: Ticket?
    var isBusy: Bool { active != nil }

    init(canonical: CanonicalSessionState, actualUserID: @escaping () -> String?,
         reauthenticationIdentity: CanonicalSessionState? = nil) {
        self.canonical = canonical; self.actualUserID = actualUserID
        self.reauthenticationIdentity = reauthenticationIdentity
    }

    /// Call synchronously in the original button/challenge event, before Task or
    /// a provider dialog. Current login UI admits a confirmed guest only.
    func capture(_ kind: Kind, newsletterOptIn: Bool = false) throws -> Ticket {
        guard active == nil else { throw Failure.busy }
        let operation = UUID(); admission = operation
        let context = canonical.contextTicket()
        guard kind != .signOut, kind != .reauthentication, context.context == .guest else { throw CancellationError() }
        let actual = actualUserID()
        guard admission == operation, active == nil, actual == nil, canonical.isCurrent(context) else { throw CancellationError() }
        let ticket = Ticket(kind: kind, context: context, coordinatorID: id, identity: canonical, newsletterOptIn: newsletterOptIn)
        active = ticket; latest = ticket
        return ticket
    }

    /// Reauthentication belongs to the original signed-in action, never to a
    /// login capture or whichever owner happens to exist after a provider sheet.
    func captureReauthentication(context: CanonicalSessionState.ContextTicket) throws -> Ticket {
        guard active == nil else { throw Failure.busy }
        let operation = UUID(); admission = operation
        let identity: CanonicalSessionState
        if canonical.isCurrent(context) { identity = canonical }
        else if let secondary = reauthenticationIdentity, secondary.isCurrent(context) { identity = secondary }
        else { throw CancellationError() }
        guard let userID = context.userID else { throw CancellationError() }
        let actual = actualUserID()
        guard admission == operation, active == nil, identity.isCurrent(context), actual == userID else {
            throw CancellationError()
        }
        let ticket = Ticket(kind: .reauthentication, context: context, coordinatorID: id, identity: identity)
        active = ticket; latest = ticket
        return ticket
    }

    func cancel(_ ticket: Ticket) {
        guard ticket.coordinatorID == id else { return }
        ticket.revoked = true
        // No asynchronous effect has started in reserved; provider/exchange
        // remains occupied until its real callback/return drains it.
        if active === ticket, ticket.phase == .reserved { finish(ticket) }
    }

    /// A side-effect-free final barrier after an adapter's injected identity
    /// reads. Actual SDK ownership still requires canPublishFeedback as well.
    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.coordinatorID == id && latest === ticket && !ticket.revoked
            && ticket.identity.isCurrent(ticket.receipt ?? ticket.context)
    }

    func canPublishFeedback(_ ticket: Ticket) -> Bool {
        guard isCurrent(ticket) else { return false }
        let context = ticket.receipt ?? ticket.context
        let actual = actualUserID()
        return isCurrent(ticket) && ticket.identity.isCurrent(context) && actual == context.userID
    }

    func beginProvider(_ ticket: Ticket) throws {
        try admit(ticket)
        ticket.phase = .provider
    }

    /// Also used by Apple's callback adapter. Call only once the original
    /// provider has actually returned; a cancelled presentation is not a return.
    func providerReturned(_ ticket: Ticket) throws {
        guard active === ticket, ticket.phase == .provider else { throw CancellationError() }
        ticket.phase = .reserved
        do { try admit(ticket) }
        catch { finish(ticket); throw error }
    }

    @discardableResult func providerFailed(_ ticket: Ticket) -> Bool {
        guard active === ticket, ticket.phase == .provider else { return false }
        let publish = canPublishFeedback(ticket)
        guard active === ticket, ticket.phase == .provider else { return false }
        finish(ticket)
        return publish && canPublishFeedback(ticket)
    }

    func provider<Value>(_ ticket: Ticket, perform: () async throws -> Value) async throws -> Value {
        try rejectCancelledReauthentication(ticket)
        try beginProvider(ticket)
        do {
            let value = try await perform()
            if ticket.kind == .reauthentication, Task.isCancelled { cancel(ticket) }
            try providerReturned(ticket)
            return value
        } catch {
            if ticket.kind == .reauthentication, Task.isCancelled { cancel(ticket) }
            let publish = providerFailed(ticket)
            if publish { throw error }
            throw CancellationError()
        }
    }

    func exchange<Value>(_ ticket: Ticket, perform: () async throws -> Value) async throws -> Value {
        try rejectCancelledReauthentication(ticket)
        try admit(ticket)
        ticket.phase = .exchange
        defer { finish(ticket) }
        do {
            let value = try await perform()
            if ticket.kind == .reauthentication {
                if Task.isCancelled { cancel(ticket) }
                // Unlike login, reauthentication may not adopt a new identity
                // generation, even when Firebase reports the same UID again.
                guard isCurrentReauthentication(ticket) else { throw CancellationError() }
            }
            // The app's own Firebase callback can legitimately change canonical
            // generation while this slot is occupied. The adapter must bind its
            // result to actual UID + the newly accepted canonical context.
            guard active === ticket, ticket.phase == .exchange, !ticket.revoked else { throw CancellationError() }
            return value
        } catch {
            if ticket.kind == .reauthentication, Task.isCancelled { cancel(ticket) }
            guard canPublishFeedback(ticket) else { throw CancellationError() }
            throw error
        }
    }

    func acceptResult(_ ticket: Ticket, context: CanonicalSessionState.ContextTicket,
                      isNewUser: Bool? = nil) -> Bool {
        guard ticket.kind != .reauthentication, active === ticket, ticket.phase == .exchange, !ticket.revoked,
              ticket.receipt == nil, canonical.isCurrent(context) else { return false }
        let actual = actualUserID()
        guard active === ticket, ticket.phase == .exchange, !ticket.revoked, ticket.receipt == nil,
              canonical.isCurrent(context), actual == context.userID else { return false }
        ticket.receipt = context
        if ticket.kind != .passwordReset, ticket.kind != .signOut,
           let isNewUser, let session = canonical.snapshot.session,
           canonical.acceptedSession(session, ticket: context) != nil {
            ticket.loginResult = ReaderLoginResult(originalContext: ticket.context, acceptedContext: context,
                session: session, isNewUser: isNewUser, actionID: ticket.actionID)
        }
        return true
    }

    /// Only a completed, still-current original operation can advance onboarding.
    /// Missing provider newness metadata cannot become a guessed new/existing user.
    func acceptedLoginResult(_ ticket: Ticket, session: ReaderAccountSession) -> ReaderLoginResult? {
        guard ticket.kind != .reauthentication, ticket.coordinatorID == id, ticket.phase == .finished,
              let result = ticket.loginResult, result.session == session,
              canPublishFeedback(ticket),
              canonical.acceptedSession(session, ticket: result.acceptedContext) != nil else { return nil }
        return result
    }

    /// Signout is never reported complete while an identity SDK call can still
    /// return. A merely queued intent can be cancelled before signout starts.
    func signOut(perform: () throws -> Void) throws {
        if let active, active.phase == .reserved { cancel(active) }
        guard active == nil else { throw Failure.busy }
        let ticket = Ticket(kind: .signOut, context: canonical.contextTicket(), coordinatorID: id, identity: canonical)
        active = ticket; latest = ticket; ticket.phase = .exchange
        defer { finish(ticket) }
        try perform()
    }

    private func admit(_ ticket: Ticket) throws {
        guard active === ticket, ticket.coordinatorID == id, ticket.phase == .reserved,
              !ticket.revoked, ticket.identity.isCurrent(ticket.context) else { try rejectAdmission(ticket) }
        let actual = actualUserID()
        guard active === ticket, ticket.phase == .reserved, !ticket.revoked,
              ticket.identity.isCurrent(ticket.context), actual == ticket.context.userID else { try rejectAdmission(ticket) }
    }
    private func rejectCancelledReauthentication(_ ticket: Ticket) throws {
        guard ticket.kind == .reauthentication, Task.isCancelled else { return }
        cancel(ticket)
        throw CancellationError()
    }
    private func isCurrentReauthentication(_ ticket: Ticket) -> Bool {
        guard active === ticket, ticket.coordinatorID == id, ticket.phase == .exchange,
              !ticket.revoked, let userID = ticket.context.userID, ticket.identity.isCurrent(ticket.context) else { return false }
        let actual = actualUserID()
        // The injected identity read may synchronously revoke or replace state.
        return active === ticket && ticket.phase == .exchange && !ticket.revoked
            && ticket.identity.isCurrent(ticket.context) && actual == userID
    }
    private func rejectAdmission(_ ticket: Ticket) throws -> Never {
        if active === ticket, ticket.phase == .reserved { finish(ticket) }
        throw CancellationError()
    }
    private func finish(_ ticket: Ticket) {
        guard active === ticket else { return }
        ticket.phase = .finished; active = nil
    }
}
