import Foundation

/// Narrow compatibility mirror. Local profile loading is neither write
/// authority nor a prerequisite; visible favorites belong to FavoritesModel.
@MainActor
enum FavoritesProfileMirror {
    typealias Guard = @MainActor () -> Bool
    struct Identity: Equatable, Sendable {
        let actualUID: String?
        let canonicalUID: String?
    }
    struct Effects {
        let identity: @MainActor () -> Identity
        /// Must update an existing profile field, never merge-create a profile.
        let updateExisting: @MainActor (String, String, Bool, @escaping Guard) async throws -> Void

        init(identity: @escaping @MainActor () -> Identity,
             guardedUpdateExisting: @escaping @MainActor (String, String, Bool, @escaping Guard) async throws -> Void) {
            self.identity = identity; updateExisting = guardedUpdateExisting
        }

        /// Compatibility for isolated pure mirror tests. Production adapters
        /// use guardedUpdateExisting and check it at the physical SDK boundary.
        init(identity: @escaping @MainActor () -> Identity,
             updateExisting: @escaping @MainActor (String, String, Bool) async throws -> Void) {
            self.identity = identity
            self.updateExisting = { uid, id, saved, _ in try await updateExisting(uid, id, saved) }
        }
    }
    enum Failure: Error, Equatable { case invalidRequest, stale }

    static func perform(model: FavoritesModel, ticket: FavoritesModel.DispatchTicket,
                        expectedUserID: String, stillCurrent: @escaping Guard = { true }, effects: Effects) async throws {
        let mutation = ticket.mutation
        guard safeDocumentID(expectedUserID), safeDocumentID(mutation.articleID),
              mutation.namespace == FavoritesContext.confirmed(userID: expectedUserID).namespace,
              mutation.namespace != .guest else { throw Failure.invalidRequest }
        var revoked = false
        let original: Guard = {
            guard !revoked, !Task.isCancelled, stillCurrent(), !revoked,
                  model.context == .confirmed(userID: expectedUserID), model.isCurrent(ticket) else {
                revoked = true; return false
            }
            let identity = effects.identity()
            guard stillCurrent(), !revoked, !Task.isCancelled,
                  owns(model: model, ticket: ticket, expectedUserID: expectedUserID, identity: identity) else {
                revoked = true; return false
            }
            return true
        }
        guard original() else { throw Failure.stale }
        // All three immutable arguments come from the original dispatch. No
        // loaded profile, current toggle or later account can supply payload.
        try await effects.updateExisting(expectedUserID, mutation.articleID, mutation.enabled, original)
        guard original() else { throw Failure.stale }
    }

    private static func owns(model: FavoritesModel, ticket: FavoritesModel.DispatchTicket,
                             expectedUserID: String, identity: Identity) -> Bool {
        // Evaluate the injected identity read before checking the model: even a
        // synchronous getter may revoke the original owner/intent reentrantly.
        identity.actualUID == expectedUserID && identity.canonicalUID == expectedUserID
            && model.context == .confirmed(userID: expectedUserID) && model.isCurrent(ticket)
    }
    private static func safeDocumentID(_ value: String) -> Bool {
        FavoritesRecordCodec.isValidID(value) && !value.contains("/") && value != "." && value != ".."
            && !(value.hasPrefix("__") && value.hasSuffix("__"))
    }
}
