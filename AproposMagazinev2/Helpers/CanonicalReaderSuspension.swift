import Foundation

/// The production signout boundary: both private projections must have accepted
/// their original revocations before canonical suspension or dependent effects.
@MainActor
enum CanonicalReaderSuspension {
    struct Ticket: Equatable, Sendable {
        let canonical: CanonicalSessionState.ContextTicket
        let profile: UserProfileState.ContextTicket
        let preferences: ReaderPreferencesModel.ContextTicket
        let userID: String
    }

    /// Revalidate the original three revocations after the final identity read,
    /// immediately before the actual provider signout effect.
    static func isCurrent(_ ticket: Ticket, canonical: CanonicalSessionState,
                          profile: UserProfileState, preferences: ReaderPreferencesModel,
                          currentUserID: () -> String?) -> Bool {
        let actual = currentUserID()
        return actual == ticket.userID && !ticket.userID.isEmpty
            && ticket.canonical.context == .unresolved && canonical.isCurrent(ticket.canonical)
            && ticket.profile.context == .unresolved && profile.isCurrent(ticket.profile)
            && ticket.preferences.context == .unresolved && preferences.isCurrent(ticket.preferences)
    }

    static func perform(
        canonical: CanonicalSessionState,
        profile: UserProfileState,
        preferences: ReaderPreferencesModel,
        context: CanonicalSessionState.ContextTicket,
        currentUserID: () -> String?,
        suspendProfile: () -> Void,
        dependentSteps: [() -> Void]
    ) -> Ticket? {
        guard let originalUserID = context.userID, !originalUserID.isEmpty else { return nil }
        func ownsOriginal() -> Bool {
            let actual = currentUserID()
            return actual == originalUserID && canonical.isCurrent(context)
        }
        guard ownsOriginal() else { return nil }
        suspendProfile()
        // Capture immediately after the actual profile coordinator returns.
        // Every subsequent identity read is followed by this ticket check.
        let profileRevocation = profile.contextTicket()
        guard profileRevocation.context == .unresolved,
              ownsOriginal(), profile.isCurrent(profileRevocation) else { return nil }
        guard let preferencesRevocation = preferences.changeContext(to: .unresolved),
              preferencesRevocation.context == .unresolved else { return nil }
        func privateRevocationsCurrent() -> Bool {
            profile.isCurrent(profileRevocation) && profileRevocation.context == .unresolved
                && preferences.isCurrent(preferencesRevocation) && preferencesRevocation.context == .unresolved
        }
        func permittedBeforeCanonical() -> Bool {
            let actual = currentUserID()
            return actual == originalUserID && canonical.isCurrent(context) && privateRevocationsCurrent()
        }
        guard permittedBeforeCanonical(),
              let suspension = canonical.suspend(stillPermitted: permittedBeforeCanonical) else { return nil }
        let ticket = Ticket(canonical: suspension, profile: profileRevocation,
                            preferences: preferencesRevocation, userID: originalUserID)
        func ownsSuspension() -> Bool {
            isCurrent(ticket, canonical: canonical, profile: profile, preferences: preferences,
                      currentUserID: currentUserID)
        }
        for step in dependentSteps {
            guard ownsSuspension() else { return nil }
            step()
        }
        return ownsSuspension() ? ticket : nil
    }
}
