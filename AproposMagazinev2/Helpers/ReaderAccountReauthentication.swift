import Foundation

enum ReaderReauthenticationMethod: CaseIterable, Hashable { case email, apple, google }

/// A separate identity challenge for an already signed-in reader. Construction
/// is inert; the injected adapter must reauthenticate the captured user, then
/// return the auth date from that user's actual ID-token result.
@MainActor
final class ReaderAccountReauthentication<Credential> {
    typealias ActionTicket = ReaderAccountDeletionCoordinator.ActionTicket
    typealias ReauthenticationResult = ReaderAccountDeletionCoordinator.ReauthenticationResult
    typealias Clock = @MainActor () -> Int64

    struct Authentication: Equatable {
        let uid: String
        let authTimeMs: Int64
    }

    struct HeldUser {
        let uid: String
        /// Provider metadata captured with the original SDK instance, never
        /// resolved again when a delayed password form is submitted.
        let email: String?
        let supportsPassword: Bool
        /// Apple's provider subject, captured from this SDK user before any UI.
        /// This is neither the Firebase UID nor an email address.
        let appleSubject: String?
        /// Google provider subject from the same originally captured SDK user.
        let googleSubject: String?
        /// Production checks the identity of the original SDK User instance,
        /// not just its UID. A replacement instance is a different operation.
        let isCurrent: @MainActor () -> Bool
        /// Check the permission before/after each SDK await. A token refresh
        /// alone must never produce Authentication; actual reauthentication
        /// must succeed first, including any error alongside an SDK result.
        let reauthenticate: @MainActor (Credential, @escaping @MainActor () -> Bool) async throws -> Authentication
        /// Optional transport credentials for this same captured SDK instance.
        /// The caller must never resolve a replacement user after reauth.
        let deletionCredentials: (@MainActor (ReauthenticationResult, @escaping @MainActor () -> Bool) async throws -> ReaderDeletionHTTPTransport.Credentials)?

        init(uid: String, isCurrent: @escaping @MainActor () -> Bool,
             reauthenticate: @escaping @MainActor (Credential, @escaping @MainActor () -> Bool) async throws -> Authentication,
             deletionCredentials: (@MainActor (ReauthenticationResult, @escaping @MainActor () -> Bool) async throws -> ReaderDeletionHTTPTransport.Credentials)? = nil,
             email: String? = nil, supportsPassword: Bool = false, appleSubject: String? = nil, googleSubject: String? = nil) {
            self.uid = uid; self.isCurrent = isCurrent; self.reauthenticate = reauthenticate
            self.deletionCredentials = deletionCredentials
            self.email = email; self.supportsPassword = supportsPassword
            self.appleSubject = appleSubject; self.googleSubject = googleSubject
        }
    }

    struct HeldAuthentication {
        let proof: ReauthenticationResult
        let user: HeldUser
    }

    enum Failure: Error, Equatable { case invalidAuthentication }

    private let canonical: CanonicalSessionState
    private let operations: AuthOperationCoordinator
    private let captureUser: @MainActor () -> HeldUser?
    private let nowMilliseconds: Clock

    init(canonical: CanonicalSessionState, operations: AuthOperationCoordinator,
         captureUser: @escaping @MainActor () -> HeldUser?,
         nowMilliseconds: @escaping Clock = { Int64(Date().timeIntervalSince1970 * 1_000) }) {
        self.canonical = canonical
        self.operations = operations
        self.captureUser = captureUser
        self.nowMilliseconds = nowMilliseconds
    }

    /// Read-only provider metadata for an explicit method choice. This neither
    /// captures a login operation nor starts a provider, credential or SDK call.
    func supportedMethods(context: CanonicalSessionState.ContextTicket) -> Set<ReaderReauthenticationMethod> {
        guard canonical.isCurrent(context), let uid = context.userID,
              let user = captureUser(), user.uid == uid, canonical.isCurrent(context),
              user.isCurrent(), canonical.isCurrent(context) else { return [] }
        var result: Set<ReaderReauthenticationMethod> = []
        if user.supportsPassword, let email = user.email,
           EmailAccountForm(email: email, password: "validation-only").validationMessage(for: .signIn) == nil {
            result.insert(.email)
        }
        if let subject = user.appleSubject, !subject.isEmpty { result.insert(.apple) }
        if let subject = user.googleSubject, !subject.isEmpty { result.insert(.google) }
        guard user.isCurrent(), canonical.isCurrent(context) else { return [] }
        return result
    }

    func reauthenticate(action: ActionTicket,
        obtainCredential: @MainActor (ActionTicket) async throws -> Credential) async throws -> ReauthenticationResult {
        try await reauthenticateHoldingUser(action: action, obtainCredential: obtainCredential).proof
    }

    func reauthenticateHoldingUser(action: ActionTicket,
        obtainCredential: @MainActor (ActionTicket) async throws -> Credential) async throws -> HeldAuthentication {
        try await reauthenticateHoldingUser(action: action, obtainCredentialForUser: { action, _ in
            try await obtainCredential(action)
        })
    }

    func reauthenticateHoldingUser(action: ActionTicket,
        obtainCredentialForUser: @MainActor (ActionTicket, HeldUser) async throws -> Credential) async throws -> HeldAuthentication {
        try requireAction(action)
        let ticket = try operations.captureReauthentication(context: action.context)
        // A provider/SDK await must physically return before this reservation
        // is released. Cancelling the caller does not create a second slot.
        defer { operations.cancel(ticket) }
        guard let user = captureUser() else { throw CancellationError() }
        try requireOwnership(action, ticket: ticket, user: user)
        let startedNow = nowMilliseconds()
        try requireOwnership(action, ticket: ticket, user: user)
        try requireFreshAction(action, now: startedNow)

        do {
            let credential = try await operations.provider(ticket) {
                try self.requireOwnership(action, ticket: ticket, user: user)
                return try await obtainCredentialForUser(action, user)
            }
            try requireOwnership(action, ticket: ticket, user: user)
            let authentication = try await operations.exchange(ticket) {
                try self.requireOwnership(action, ticket: ticket, user: user)
                let value = try await user.reauthenticate(credential) { [self] in
                    (try? requireOwnership(action, ticket: ticket, user: user)) != nil
                }
                try self.requireOwnership(action, ticket: ticket, user: user)
                return value
            }
            try requireOwnership(action, ticket: ticket, user: user)
            let now = nowMilliseconds()
            try requireOwnership(action, ticket: ticket, user: user)
            try requireFreshAction(action, now: now)
            // Firebase auth_time is rounded down to seconds. This tolerance
            // belongs to this exact action; it cannot authorize a later retry.
            let earliest = (action.startedAtMs / 1_000) * 1_000
            guard authentication.uid == action.request.expectedUID,
                  (1...ReaderAccountDeletionContract.maximumSafeInteger).contains(authentication.authTimeMs),
                  authentication.authTimeMs >= earliest, authentication.authTimeMs <= now,
                  now - authentication.authTimeMs < 300_000 else { throw Failure.invalidAuthentication }
            return HeldAuthentication(proof: ReauthenticationResult(action: action, authenticatedUID: authentication.uid,
                authTimeMs: authentication.authTimeMs, kind: .reauthenticated), user: user)
        } catch {
            // A late error is just as stale as a late success. Do not surface an
            // old account's provider error after cancellation or replacement.
            try requireOwnership(action, ticket: ticket, user: user)
            throw error
        }
    }

    private func requireAction(_ action: ActionTicket) throws {
        try Task.checkCancellation()
        guard canonical.isCurrent(action.context), action.context.userID == action.request.expectedUID,
              canonical.snapshot.session?.uid == action.request.expectedUID else { throw CancellationError() }
    }

    private func requireOwnership(_ action: ActionTicket, ticket: AuthOperationCoordinator.Ticket,
                                  user: HeldUser) throws {
        try requireAction(action)
        guard user.uid == action.request.expectedUID, operations.canPublishFeedback(ticket) else { throw CancellationError() }
        try requireAction(action)
        let stillHeld = user.isCurrent()
        // No injected getters after the object identity check: their reentry
        // could replace the held user or cancel the original reservation.
        try requireAction(action)
        guard stillHeld, operations.isCurrent(ticket) else { throw CancellationError() }
    }

    private func requireFreshAction(_ action: ActionTicket, now: Int64) throws {
        let valid = 1...ReaderAccountDeletionContract.maximumSafeInteger
        guard valid.contains(action.startedAtMs), valid.contains(now),
              now >= action.startedAtMs, now - action.startedAtMs < 300_000 else { throw Failure.invalidAuthentication }
    }
}
