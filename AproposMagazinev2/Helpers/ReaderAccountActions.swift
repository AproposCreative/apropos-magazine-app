import Foundation

/// The actual account form's event boundary. Capture synchronously in the button
/// event, then carry this original owner and payload through the delayed Task.
@MainActor
struct ReaderAccountActions {
    struct OwnerAction {
        let userID: String
        let canonical: CanonicalSessionState.ContextTicket
        let preferences: ReaderPreferencesModel.ContextTicket
        let readerPermission: ReaderPreferencesModel.Guard?
    }
    struct SaveAction {
        let owner: OwnerAction
        let request: ReaderPreferencesModel.SaveRequest
    }
    typealias Verify = (CanonicalSessionState.ContextTicket) async -> Void
    typealias Refresh = (CanonicalSessionState.ContextTicket) async throws -> Void
    private let canonical: CanonicalSessionState
    private let preferences: ReaderPreferencesModel
    private let verify: Verify
    private let refreshOperation: Refresh

    init(canonical: CanonicalSessionState, preferences: ReaderPreferencesModel,
         verify: @escaping Verify, refresh: @escaping Refresh) {
        self.canonical = canonical; self.preferences = preferences
        self.verify = verify; self.refreshOperation = refresh
    }
    func captureOwner(userID: String, context: CanonicalSessionState.ContextTicket) -> OwnerAction? {
        guard canonical.isCurrent(context), context.userID == userID else { return nil }
        let original = preferences.contextTicket()
        let permission = preferences.capturePermissionForCurrentContext(original)
        let owner = OwnerAction(userID: userID, canonical: context, preferences: original, readerPermission: permission)
        return isCurrent(owner) ? owner : nil
    }
    func captureSave(ids: [String], userID: String, context: CanonicalSessionState.ContextTicket) -> SaveAction? {
        guard let owner = captureOwner(userID: userID, context: context) else { return nil }
        return captureSave(ids: ids, owner: owner)
    }
    private func captureSave(ids: [String], owner: OwnerAction) -> SaveAction? {
        guard isCurrentReader(owner), let permission = owner.readerPermission,
              let request = preferences.captureSave(ids: ids, context: owner.preferences, stillCurrent: permission) else { return nil }
        guard isCurrentReader(owner) else {
            preferences.abandonCapture(request)
            return nil
        }
        return SaveAction(owner: owner, request: request)
    }
    /// Reader authority is separate from Auth-only verification/refresh access.
    func isCurrentReader(_ action: OwnerAction) -> Bool {
        guard isCurrent(action), let permission = action.readerPermission, permission() else { return false }
        return isCurrent(action)
    }
    func isCurrent(_ action: OwnerAction) -> Bool {
        canonical.isCurrent(action.canonical) && action.canonical.userID == action.userID
            && preferences.isCurrent(action.preferences) && action.preferences.userID == action.userID
            && canonical.isCurrent(action.canonical)
    }
    func isCurrent(_ action: SaveAction) -> Bool { isCurrent(action.owner) }
    /// Use only after this action's save returned true. New loads, saves and
    /// owner epochs revoke a previously acknowledged form's success controls.
    func isCurrentReceipt(_ action: SaveAction) -> Bool {
        isCurrentReader(action.owner) && preferences.isCurrent(action.request) && !preferences.snapshot.isSaving
            && isCurrentReader(action.owner)
    }

    func save(_ action: SaveAction) async -> Bool {
        defer { preferences.abandonCapture(action.request) }
        guard isCurrentReader(action.owner) else { return false }
        let accepted = await preferences.saveInterests(action.request)
        return accepted && isCurrentReader(action.owner)
    }

    /// The intro can become visible before Auth's preference load completes.
    /// Capture this exact owner and explicit selection, then wait for a real
    /// accepted load (or retry a failed load) before using the normal save path.
    /// A timeout is an unconfirmed result, never permission to bypass loading.
    /// Capture synchronously in the intro button event, before its Task. A
    /// later ready gate cannot turn a rejected old click into a new operation.
    func captureInterestCommit(ids: [String], userID: String, context: CanonicalSessionState.ContextTicket,
                               scheduleLoadDeadline: ReaderInterestCommitPreparation.Schedule? = nil) -> (@MainActor () async -> Bool)? {
        guard let owner = captureOwner(userID: userID, context: context), isCurrentReader(owner) else { return nil }
        let originalIDs = ids
        var consumed = false
        return {
            guard !consumed else { return false }
            consumed = true
            guard !Task.isCancelled, self.isCurrentReader(owner) else { return false }
            let preparation = ReaderInterestCommitPreparation(canonical: self.canonical, preferences: self.preferences,
                actions: self, owner: owner, schedule: scheduleLoadDeadline)
            guard await preparation.prepare(), !Task.isCancelled, self.isCurrentReader(owner),
                  let save = self.captureSave(ids: originalIDs, owner: owner) else { return false }
            let accepted = await self.save(save)
            return accepted && !Task.isCancelled && self.isCurrentReader(owner) && self.isCurrentReceipt(save)
        }
    }
    func commitInterests(ids: [String], userID: String, context: CanonicalSessionState.ContextTicket,
                         scheduleLoadDeadline: ReaderInterestCommitPreparation.Schedule? = nil) async -> Bool {
        guard !Task.isCancelled, let commit = captureInterestCommit(ids: ids, userID: userID, context: context,
            scheduleLoadDeadline: scheduleLoadDeadline) else { return false }
        return await commit()
    }

    func retry(_ action: OwnerAction) async -> Bool {
        guard isCurrentReader(action), let permission = action.readerPermission else { return false }
        await preferences.retry(action.preferences, stillCurrent: permission)
        return isCurrentReader(action) && preferences.snapshot.loaded
    }
    func sendVerification(_ action: OwnerAction) async -> Bool {
        guard isCurrent(action) else { return false }
        await verify(action.canonical)
        return isCurrent(action)
    }
    func refresh(_ action: OwnerAction) async throws -> Bool {
        guard isCurrent(action) else { return false }
        do {
            try await refreshOperation(action.canonical)
            return isCurrent(action)
        } catch {
            // An old form cannot turn a later owner's screen into its error UI.
            guard isCurrent(action) else { return false }
            throw error
        }
    }
}
