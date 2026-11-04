import Foundation

/// Actual profile pipeline; effects are explicit and constructors start no work.
@MainActor
final class UserProfileCoordinator {
    typealias Guard = @MainActor () -> Bool
    struct Identity { let actualUID: String?; let canonicalUID: String? }
    enum ReadSource { case standard, server }
    struct ReadResult { let profile: UserProfile?; let isFromCache: Bool }
    struct Effects {
        let capturePermission: @MainActor () -> Guard?
        let identity: @MainActor () -> Identity
        let read: @MainActor (UserProfile, ReadSource, UserProfileState.LoadTicket, @escaping Guard) async throws -> ReadResult
        let write: @MainActor (UserProfile, UserProfileState.SaveTicket, @escaping Guard) async throws -> Void
        let subscribe: @MainActor (UserProfile, @escaping Guard) -> Void
        let unsubscribe: @MainActor (UserProfile, @escaping Guard) -> Void
        let updateFCM: @MainActor (String, @escaping Guard) -> Void
    }
    /// The captured startup authority is never reacquired by a callback or a
    /// derived default-profile write. Once denied, this operation stays denied.
    @MainActor private final class Permission {
        private let original: Guard
        private let parent: Guard?
        private var denied = false
        init(original: @escaping Guard, parent: Guard?) { self.original = original; self.parent = parent }
        func isCurrent() -> Bool {
            guard !denied else { return false }
            guard original(), !denied else { denied = true; return false }
            guard parent?() ?? true, !denied else { denied = true; return false }
            guard original(), !denied else { denied = true; return false }
            return true
        }
    }
    private struct Load { let seed: UserProfile; let ticket: UserProfileState.LoadTicket; let permission: Permission }
    private struct Save { let profile: UserProfile; let ticket: UserProfileState.SaveTicket; let permission: Permission }
    let state: UserProfileState
    private let effects: Effects
    private var started = false
    private var contextOperation = UUID()
    private var entryOperation = UUID()
    private var cleanupOperation = UUID()
    private var suspension: (id: UUID, value: UserProfileState.Suspension)?
    private var cleanup: (id: UUID, profile: UserProfile)?
    private var cleaning = false
    private var controlScheduled = false
    private var pendingLoad: Load?
    private var pendingSave: Save?
    private var activeLoads: Set<UUID> = []
    private static let maximumActiveLoads = 4
    private var activeSave: UUID?

    init(state: UserProfileState, effects: Effects) { self.state = state; self.effects = effects }
    var activity: (loading: Bool, saving: Bool, pendingLoad: Bool, pendingSave: Bool, activeLoadCount: Int) {
        (!activeLoads.isEmpty, activeSave != nil, pendingLoad != nil, pendingSave != nil, activeLoads.count)
    }
    func start() { started = true; pumpLoad(); pumpSave() }

    /// Canonical ingress is pure state: no SDK call or listener is started here.
    func changeAccountContext(userID: String?) {
        let operation = UUID(); contextOperation = operation
        if let held = suspension, held.value.userID == userID {
            _ = restoreAfterFailedSignOut()
            guard contextOperation == operation else { return }
            if state.snapshot.context == .confirmed(userID: userID) { return }
        }
        guard contextOperation == operation else { return }
        suspension = nil
        if let profile = state.snapshot.profile, profile.uid != userID { stageCleanup(profile) }
        _ = state.changeContext(to: .confirmed(userID: userID))
        prunePending()
    }
    func suspendForAccountChange() {
        let operation = UUID(); contextOperation = operation
        if let profile = state.snapshot.profile { stageCleanup(profile) }
        let token = state.contextTicket()
        guard let value = state.suspend(ticket: token), contextOperation == operation else { return }
        suspension = (UUID(), value); prunePending()
    }
    @discardableResult func restoreAfterFailedSignOut() -> Bool {
        guard let held = suspension else { return false }
        let identity = effects.identity()
        guard suspension?.id == held.id, identity.actualUID == held.value.userID,
              identity.canonicalUID == held.value.userID,
              state.restore(held.value, confirmedUserID: held.value.userID) != nil else { return false }
        if suspension?.id == held.id { suspension = nil; cleanup = nil }
        return true
    }
    func clearIfConfirmedGuest() {
        let ticket = state.contextTicket()
        let identity = effects.identity()
        guard state.isCurrent(ticket), identity.actualUID == nil, identity.canonicalUID == nil else { return }
        if let profile = state.snapshot.profile { stageCleanup(profile) }
        guard state.clearForSignOut(ticket: ticket) else { return }
        suspension = nil; prunePending(); runCleanup()
    }
    func load(_ seed: UserProfile, stillCurrent: Guard? = nil) {
        let entry = UUID(); entryOperation = entry
        let origin = state.contextTicket(), revision = state.snapshot.revision
        guard let permission = capturePermission(parent: stillCurrent), entryOperation == entry,
              matches(userID: seed.uid, origin: origin, revision: revision, permission: permission),
              entryOperation == entry else { return }
        let admitted: Guard = { [weak self] in
            guard let self, self.entryOperation == entry else { return false }
            let valid = self.matches(userID: seed.uid, origin: origin, revision: revision, permission: permission)
            return valid && self.entryOperation == entry
        }
        guard let ticket = state.beginLoad(userID: seed.uid, stillPermitted: admitted) else { return }
        let request = Load(seed: seed, ticket: ticket, permission: permission)
        guard owns(request), entryOperation == entry else { state.cancelLoad(ticket: ticket); return }
        pendingLoad = request; pumpLoad()
    }
    @discardableResult func save(_ profile: UserProfile, stillCurrent: Guard? = nil) -> UserProfileState.SaveTicket? {
        let entry = UUID(); entryOperation = entry
        let origin = state.contextTicket(), revision = state.snapshot.revision
        guard let permission = capturePermission(parent: stillCurrent), entryOperation == entry else { return nil }
        return submitSave(profile, permission: permission, entry: entry, origin: origin, revision: revision)
    }
    private func capturePermission(parent: Guard?) -> Permission? {
        // A closed explicit caller must not consult another runtime/provider.
        guard parent?() ?? true, let original = effects.capturePermission() else { return nil }
        let permission = Permission(original: original, parent: parent)
        return permission.isCurrent() ? permission : nil
    }
    @discardableResult private func submitSave(_ profile: UserProfile, permission: Permission, entry: UUID,
        origin: UserProfileState.ContextTicket, revision: UInt64, source: Load? = nil) -> UserProfileState.SaveTicket? {
        let admitted: Guard = { [weak self] in
            guard let self, self.entryOperation == entry else { return false }
            if let source, !self.owns(source) { return false }
            let valid = self.matches(userID: profile.uid, origin: origin, revision: revision, permission: permission)
            return valid && self.entryOperation == entry
        }
        guard admitted(), let ticket = state.beginSave(profile, stillPermitted: admitted) else { return nil }
        let request = Save(profile: profile, ticket: ticket, permission: permission)
        guard owns(request), entryOperation == entry else { return nil }
        pendingSave = request; pumpSave()
        return owns(request) && entryOperation == entry ? ticket : nil
    }
    private func saveDefault(_ profile: UserProfile, from source: Load) {
        let entry = UUID(); entryOperation = entry
        let origin = state.contextTicket(), revision = state.snapshot.revision
        _ = submitSave(profile, permission: source.permission, entry: entry, origin: origin, revision: revision, source: source)
    }
    private func matches(userID: String, origin: UserProfileState.ContextTicket, revision: UInt64, permission: Permission) -> Bool {
        guard permission.isCurrent() else { return false }
        let identity = effects.identity()
        return permission.isCurrent() && identity.actualUID == userID && identity.canonicalUID == userID
            && state.isCurrent(origin) && state.snapshot.revision == revision && origin.context == .confirmed(userID: userID)
    }
    private func owns(_ request: Load) -> Bool {
        guard request.permission.isCurrent(), state.isCurrent(request.ticket) else { return false }
        let identity = effects.identity()
        return request.permission.isCurrent() && identity.actualUID == request.ticket.userID
            && identity.canonicalUID == request.ticket.userID && state.isCurrent(request.ticket)
    }
    private func owns(_ request: Save) -> Bool {
        guard request.permission.isCurrent(), state.isCurrent(request.ticket) else { return false }
        let identity = effects.identity()
        return request.permission.isCurrent() && identity.actualUID == request.ticket.userID
            && identity.canonicalUID == request.ticket.userID && state.isCurrent(request.ticket)
    }
    private func owns(_ ticket: UserProfileState.ContextTicket, permission: Permission) -> Bool {
        guard permission.isCurrent(), state.isCurrent(ticket) else { return false }
        let identity = effects.identity()
        return permission.isCurrent() && identity.actualUID == ticket.userID
            && identity.canonicalUID == ticket.userID && state.isCurrent(ticket)
    }
    private func stageCleanup(_ profile: UserProfile) {
        let id = UUID(); cleanupOperation = id; cleanup = (id, profile)
    }
    private func prunePending() {
        if let pendingLoad, !state.isCurrent(pendingLoad.ticket) { self.pendingLoad = nil }
        if let pendingSave, !state.isCurrent(pendingSave.ticket) { self.pendingSave = nil }
    }
    private func scheduleControl() {
        guard !controlScheduled else { return }
        controlScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }; self.controlScheduled = false
            self.runCleanup(); self.pumpLoad(); self.pumpSave()
        }
    }
    private func runCleanup() {
        guard started, let pending = cleanup else { return }
        if cleaning { scheduleControl(); return }
        let ticket = state.contextTicket()
        guard ticket.context != .unresolved else { return }
        cleaning = true
        defer { cleaning = false }
        // Capture once at cleanup admission. Delayed notification callbacks keep
        // this exact context and authority, never whichever account follows it.
        guard let permission = capturePermission(parent: nil), cleanup?.id == pending.id,
              owns(ticket, permission: permission), cleanup?.id == pending.id else { return }
        let admitted: Guard = { [weak self] in
            guard let self, self.cleanupOperation == pending.id else { return false }
            let current = self.owns(ticket, permission: permission)
            return current && self.cleanupOperation == pending.id
        }
        guard admitted() else { return }
        effects.unsubscribe(pending.profile, admitted)
        if cleanup?.id == pending.id, admitted(), cleanup?.id == pending.id { cleanup = nil }
    }
    private func pumpLoad() {
        guard started, !cleaning else { if cleaning { scheduleControl() }; return }
        runCleanup()
        guard activeLoads.count < Self.maximumActiveLoads, let request = pendingLoad else { return }
        pendingLoad = nil
        guard owns(request) else { state.cancelLoad(ticket: request.ticket); return }
        guard activeLoads.count < Self.maximumActiveLoads else {
            if pendingLoad == nil { pendingLoad = request }; return
        }
        let id = UUID(); activeLoads.insert(id)
        let admitted: Guard = { [weak self] in self?.owns(request) ?? false }
        Task { @MainActor [self] in
            defer { activeLoads.remove(id); state.cancelLoad(ticket: request.ticket); pumpLoad() }
            do {
                guard admitted() else { return }
                var result = try await effects.read(request.seed, .standard, request.ticket, admitted)
                guard admitted() else { return }
                if result.profile == nil && result.isFromCache {
                    result = try await effects.read(request.seed, .server, request.ticket, admitted)
                    guard admitted() else { return }
                }
                guard result.profile != nil || !result.isFromCache else { throw PipelineFailure.unconfirmedAbsence }
                let profile = result.profile.map { Self.merge($0, seed: request.seed) } ?? request.seed
                guard profile.uid == request.ticket.userID else { throw PipelineFailure.wrongOwner }
                guard admitted(), state.acceptLoad(profile, ticket: request.ticket, stillPermitted: admitted), admitted() else { return }
                effects.subscribe(profile, admitted)
                guard admitted() else { return }
                if result.profile == nil { saveDefault(profile, from: request) }
                else { effects.updateFCM(request.ticket.userID, admitted) }
            } catch {
                if admitted() {
                    _ = state.failLoad(ticket: request.ticket,
                        message: "Kunne ikke hente brugerprofil. Prøv igen, når du er online.", stillPermitted: admitted)
                }
            }
        }
    }
    private func pumpSave() {
        guard started, activeSave == nil, let request = pendingSave else { return }
        pendingSave = nil
        guard owns(request), activeSave == nil else { return }
        let id = UUID(); activeSave = id
        let admitted: Guard = { [weak self] in self?.owns(request) ?? false }
        Task { @MainActor [self] in
            defer { if activeSave == id { activeSave = nil }; pumpSave() }
            do {
                guard admitted() else { return }
                try await effects.write(request.profile, request.ticket, admitted)
                guard admitted(), state.finishSave(ticket: request.ticket, message: nil, stillPermitted: admitted), admitted() else { return }
                effects.updateFCM(request.ticket.userID, admitted)
            } catch {
                if admitted() {
                    _ = state.finishSave(ticket: request.ticket, message: "Kunne ikke gemme brugerprofil.", stillPermitted: admitted)
                }
            }
        }
    }
    private enum PipelineFailure: Error { case unconfirmedAbsence, wrongOwner }
    private static func merge(_ existing: UserProfile, seed: UserProfile) -> UserProfile {
        UserProfile(uid: existing.uid, email: seed.email.isEmpty ? existing.email : seed.email,
                    displayName: seed.displayName.isEmpty ? existing.displayName : seed.displayName,
                    photoURL: seed.photoURL ?? existing.photoURL, createdAt: existing.createdAt,
                    lastLoginAt: seed.lastLoginAt, favoriteCategories: existing.favoriteCategories,
                    favoriteAuthors: existing.favoriteAuthors, notificationPreferences: existing.notificationPreferences,
                    readingPreferences: existing.readingPreferences, readArticles: existing.readArticles,
                    bookmarkedArticles: existing.bookmarkedArticles, readingProgress: existing.readingProgress)
    }
}
