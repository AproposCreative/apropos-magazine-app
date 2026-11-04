import Foundation

/// Both provider operations live inside one cloud-coordinator slot. A late
/// profile receipt cannot overtake a newer desired state for the same article.
@MainActor
enum FavoritesMutationTransport {
    typealias ProfileSet = @MainActor (FavoritesModel.DispatchTicket, String, FavoritesModel) async throws -> Void
    typealias GuardedProfileSet = @MainActor (FavoritesModel.DispatchTicket, String, FavoritesModel, @escaping FavoritesCloudCoordinator.Guard) async throws -> Void
    enum Failure: Error { case stale }

    static func perform(model: FavoritesModel, ticket: FavoritesModel.DispatchTicket, expectedUserID: String,
                        writeFavorite: FavoritesCloudCoordinator.Write, setBookmark: ProfileSet) async throws {
        try await perform(model: model, ticket: ticket, expectedUserID: expectedUserID, stillCurrent: { true },
            writeFavorite: { mutation, uid, _ in try await writeFavorite(mutation, uid) },
            setBookmark: { ticket, uid, model, _ in try await setBookmark(ticket, uid, model) })
    }

    static func perform(model: FavoritesModel, ticket: FavoritesModel.DispatchTicket, expectedUserID: String,
                        stillCurrent: @escaping FavoritesCloudCoordinator.Guard,
                        writeFavorite: FavoritesCloudCoordinator.GuardedWrite, setBookmark: GuardedProfileSet) async throws {
        let mutation = ticket.mutation
        var denied = false
        let current: FavoritesCloudCoordinator.Guard = {
            guard !denied, model.context == .confirmed(userID: expectedUserID), model.isCurrent(ticket),
                  stillCurrent(), !denied, model.context == .confirmed(userID: expectedUserID), model.isCurrent(ticket)
            else { denied = true; return false }
            return true
        }
        guard current() else { throw Failure.stale }
        try await writeFavorite(mutation, expectedUserID, current)
        // Both effects retain one admission, including across their physical await.
        guard current() else { throw Failure.stale }
        try await setBookmark(ticket, expectedUserID, model, current)
        guard current() else { throw Failure.stale }
    }
}
