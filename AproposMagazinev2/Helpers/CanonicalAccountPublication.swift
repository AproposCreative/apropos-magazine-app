import Foundation

/// Used by the actual Auth adapter. A synchronous observer may start a newer
/// canonical transition during any publishing step, even A → guest → A.
@MainActor
final class CanonicalAccountPublication {
    private var revision = UUID()

    /// Normal Auth publication uses this same bridge as the injected account
    /// tests. Revoke both private projections before dependent observers, commit
    /// one canonical snapshot, then begin only the original owner's loads.
    @discardableResult
    func performReaderTransition(expectedUserID: String?, currentUserID: () -> String?,
                                 revokeProfile: @escaping () -> Bool,
                                 revokePreferences: @escaping () -> Bool,
                                 revocationsCurrent: @escaping () -> Bool,
                                 dependentSteps: [() -> Void],
                                 commitCanonical: @escaping () -> Bool,
                                 startLoads: @escaping () -> Void,
                                 permission: @escaping () -> Bool = { true }) -> Bool {
        var committed = false
        var accepted = true
        var bothRevoked = false
        let completed = perform(expectedUserID: expectedUserID, currentUserID: currentUserID,
            steps: [
                { accepted = revokeProfile() },
                { accepted = revokePreferences(); bothRevoked = accepted }
            ] + dependentSteps + [
                { committed = commitCanonical(); accepted = committed },
                { startLoads() }
            ], permission: {
                guard permission(), accepted else { return false }
                return !bothRevoked || revocationsCurrent()
            })
        return completed && accepted && committed && permission()
    }

    /// The actual auth adapter uses this ordering. A profile is revoked before
    /// dependent publishers run; profile I/O begins only after they return with
    /// the original canonical identity and publication still accepted.
    @discardableResult
    func performProfileTransition(expectedUserID: String?, currentUserID: () -> String?,
                                  revokeProfile: () -> Void, dependentSteps: [() -> Void],
                                  startProfile: () -> Void) -> Bool {
        withoutActuallyEscaping(revokeProfile) { revoke in
            withoutActuallyEscaping(startProfile) { start in
                perform(expectedUserID: expectedUserID, currentUserID: currentUserID,
                        steps: [revoke] + dependentSteps + [start])
            }
        }
    }

    @discardableResult
    func perform(expectedUserID: String?, currentUserID: () -> String?, steps: [() -> Void],
                 permission: () -> Bool = { true }) -> Bool {
        let ticket = UUID()
        revision = ticket
        // Identity reads are injected and may reenter a newer transition. Reserve
        // before the first read, then recheck AFTER every read before effects.
        let initialUserID = currentUserID()
        guard revision == ticket, initialUserID == expectedUserID else { return false }
        for step in steps {
            guard revision == ticket else { return false }
            let actualUserID = currentUserID()
            guard revision == ticket, actualUserID == expectedUserID else { return false }
            let permitted = permission()
            // Revocation validators are injected too. They cannot reenter a
            // newer transition and then resume an older dependent effect.
            guard revision == ticket, permitted else { return false }
            step()
        }
        guard revision == ticket else { return false }
        let finalUserID = currentUserID()
        return revision == ticket && finalUserID == expectedUserID
    }
}
