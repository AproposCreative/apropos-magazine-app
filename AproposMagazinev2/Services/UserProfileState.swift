import Combine
import Foundation

/// One committed authority; construction has no storage, SDK or scheduling.
@MainActor
final class UserProfileState: ObservableObject {
    enum Context: Equatable, Sendable {
        case unresolved, guest, account(String)
        static func confirmed(userID: String?) -> Self {
            guard let userID else { return .guest }
            guard UserProfileState.validUserID(userID) else { return .unresolved }
            return .account(userID)
        }
        var userID: String? { if case .account(let value) = self { return value }; return nil }
    }
    struct Snapshot: Equatable {
        let context: Context
        let generation: UUID
        let revision: UInt64
        let profile: UserProfile?
        let isLoading: Bool
        let errorMessage: String?
        let loaded: Bool
        var writeReady: Bool { loaded && !isLoading && context.userID != nil && profile?.uid == context.userID }
    }
    struct ContextTicket: Equatable, Sendable {
        let context: Context
        let generation: UUID
        var userID: String? { context.userID }
        fileprivate let modelID: UUID
    }
    struct LoadTicket: Equatable, Sendable {
        let userID: String
        let generation: UUID
        fileprivate let modelID: UUID
        fileprivate let id: UUID
    }
    struct SaveTicket: Equatable, Sendable {
        let userID: String
        let generation: UUID
        fileprivate let modelID: UUID
        fileprivate let loadVersion: UUID
        fileprivate let id: UUID
    }
    struct Suspension {
        let userID: String
        fileprivate let modelID: UUID
        fileprivate let suspended: ContextTicket
        fileprivate let profile: UserProfile?
        fileprivate let loaded: Bool
        fileprivate let errorMessage: String?
    }
    private struct Authority {
        var snapshot: Snapshot
        var loadID: UUID?
        var loadVersion: UUID?
        var saveID: UUID?
        var savePending = false
    }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    var snapshot: Snapshot { committed.snapshot }
    var acceptedLoadVersion: UUID? { committed.loadVersion }
    var changes: AnyPublisher<Snapshot, Never> {
        // This filter is installed separately for EVERY downstream subscriber.
        // If the first subscriber commits B during A's Subject.send, A cannot
        // arrive after B at a later subscriber in that same outer delivery.
        subject.filter { [weak self] candidate in
            guard let self else { return false }
            return self.snapshot.generation == candidate.generation && self.snapshot.revision == candidate.revision
        }.eraseToAnyPublisher()
    }
    private let modelID = UUID()
    private let subject = PassthroughSubject<Snapshot, Never>()
    private var operation = UUID()
    private var notifying = false
    private var committed = Authority(snapshot: Snapshot(context: .unresolved, generation: UUID(), revision: 0,
                                                         profile: nil, isLoading: false, errorMessage: nil, loaded: false))

    func contextTicket() -> ContextTicket {
        ContextTicket(context: snapshot.context, generation: snapshot.generation, modelID: modelID)
    }
    func isCurrent(_ ticket: ContextTicket) -> Bool {
        ticket.modelID == modelID && ticket.context == snapshot.context && ticket.generation == snapshot.generation
    }
    func isCurrent(_ ticket: LoadTicket) -> Bool {
        ticket.modelID == modelID && ticket.userID == snapshot.context.userID
            && ticket.generation == snapshot.generation && ticket.id == committed.loadID
    }
    func isCurrent(_ ticket: SaveTicket) -> Bool {
        ticket.modelID == modelID && ticket.userID == snapshot.context.userID && ticket.generation == snapshot.generation
            && ticket.id == committed.saveID && ticket.loadVersion == committed.loadVersion && snapshot.writeReady
    }

    @discardableResult
    func changeContext(to proposed: Context) -> ContextTicket? {
        let desired = proposed.userID.map { Context.confirmed(userID: $0) } ?? proposed
        if desired == snapshot.context {
            // A nested request for the still-committed owner can cancel an
            // outer willChange transition before its assignment occurs.
            if notifying { _ = reserve() }
            return contextTicket()
        }
        let token = reserve()
        let value = Authority(snapshot: next(context: desired, generation: UUID(), profile: nil,
                                             loading: false, error: nil, loaded: false))
        guard commit(value, token: token) else { return nil }
        return contextTicket()
    }
    func beginLoad(userID: String, stillPermitted: @MainActor () -> Bool = { true }) -> LoadTicket? {
        guard snapshot.context == .confirmed(userID: userID), Self.validUserID(userID) else { return nil }
        let token = reserve(), id = UUID()
        let value = Authority(snapshot: next(profile: snapshot.profile, loading: true, error: nil, loaded: false), loadID: id)
        let ticket = LoadTicket(userID: userID, generation: snapshot.generation, modelID: modelID, id: id)
        guard commit(value, token: token, stillPermitted: stillPermitted), isCurrent(ticket) else { return nil }
        return ticket
    }
    @discardableResult
    func acceptLoad(_ profile: UserProfile, ticket: LoadTicket, stillPermitted: @MainActor () -> Bool = { true }) -> Bool {
        guard isCurrent(ticket), snapshot.isLoading, profile.uid == ticket.userID else { return false }
        let token = reserve()
        let value = Authority(snapshot: next(profile: profile, loading: false, error: nil, loaded: true),
                              loadID: ticket.id, loadVersion: ticket.id)
        return commit(value, token: token, stillPermitted: stillPermitted) && isCurrent(ticket)
    }
    @discardableResult
    func failLoad(ticket: LoadTicket, message: String, stillPermitted: @MainActor () -> Bool = { true }) -> Bool {
        guard isCurrent(ticket), snapshot.isLoading else { return false }
        let token = reserve()
        let value = Authority(snapshot: next(profile: snapshot.profile, loading: false, error: message, loaded: false))
        return commit(value, token: token, stillPermitted: stillPermitted)
    }
    func beginSave(_ profile: UserProfile, stillPermitted: @MainActor () -> Bool = { true }) -> SaveTicket? {
        guard snapshot.writeReady, let userID = snapshot.context.userID, profile.uid == userID,
              let loadVersion = committed.loadVersion else { return nil }
        let token = reserve(), id = UUID()
        let ticket = SaveTicket(userID: userID, generation: snapshot.generation, modelID: modelID, loadVersion: loadVersion, id: id)
        // A new user edit also revokes follow-up effects from an older load.
        let value = Authority(snapshot: next(profile: profile, loading: false, error: nil, loaded: true),
                              loadVersion: loadVersion, saveID: id, savePending: true)
        guard commit(value, token: token, stillPermitted: stillPermitted), isCurrent(ticket) else { return nil }
        return ticket
    }
    @discardableResult
    func finishSave(ticket: SaveTicket, message: String?, stillPermitted: @MainActor () -> Bool = { true }) -> Bool {
        guard isCurrent(ticket), committed.savePending else { return false }
        let token = reserve()
        var value = committed
        value.snapshot = next(profile: snapshot.profile, loading: false, error: message, loaded: true)
        value.savePending = false
        return commit(value, token: token, stillPermitted: stillPermitted) && isCurrent(ticket)
    }

    /// Local retirement only. A denied original request may clear its spinner,
    /// but cannot clear a newer load or publish a provider failure over it.
    @discardableResult
    func cancelLoad(ticket: LoadTicket) -> Bool {
        guard isCurrent(ticket), snapshot.isLoading else { return false }
        let token = reserve()
        let value = Authority(snapshot: next(profile: snapshot.profile, loading: false, error: nil, loaded: false))
        return commit(value, token: token)
    }

    /// Revoke before any external signout/unsubscribe effect. The cached profile
    /// exists only in this original token, never in the unresolved projection.
    func suspend(ticket: ContextTicket) -> Suspension? {
        guard isCurrent(ticket), let userID = ticket.userID else { return nil }
        let cached = snapshot
        guard let suspended = changeContext(to: .unresolved), isCurrent(suspended) else { return nil }
        return Suspension(userID: userID, modelID: modelID, suspended: suspended, profile: cached.profile,
                          loaded: cached.loaded && !cached.isLoading, errorMessage: cached.errorMessage)
    }
    @discardableResult
    func restore(_ suspension: Suspension, confirmedUserID: String) -> ContextTicket? {
        guard suspension.modelID == modelID, suspension.userID == confirmedUserID,
              Self.validUserID(confirmedUserID), isCurrent(suspension.suspended), snapshot.context == .unresolved,
              suspension.profile == nil || suspension.profile?.uid == confirmedUserID else { return nil }
        let token = reserve()
        let loaded = suspension.loaded && suspension.profile != nil
        let value = Authority(snapshot: next(context: .account(confirmedUserID), generation: UUID(), profile: suspension.profile,
                                             loading: false, error: suspension.errorMessage, loaded: loaded),
                              loadVersion: loaded ? UUID() : nil)
        guard commit(value, token: token) else { return nil }
        return contextTicket()
    }
    @discardableResult
    func clearForSignOut(ticket: ContextTicket) -> Bool {
        guard isCurrent(ticket) else { return false }
        return changeContext(to: .guest) != nil
    }

    private func reserve() -> UUID { let value = UUID(); operation = value; return value }
    private func next(context: Context? = nil, generation: UUID? = nil, profile: UserProfile?,
                      loading: Bool, error: String?, loaded: Bool) -> Snapshot {
        Snapshot(context: context ?? snapshot.context, generation: generation ?? snapshot.generation,
                 revision: snapshot.revision == UInt64.max ? UInt64.max : snapshot.revision + 1,
                 profile: profile, isLoading: loading, errorMessage: error, loaded: loaded)
    }
    private func commit(_ value: Authority, token: UUID, stillPermitted: @MainActor () -> Bool = { true }) -> Bool {
        guard operation == token, snapshot.revision < UInt64.max, stillPermitted(), operation == token else { return false }
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard operation == token, stillPermitted(), operation == token else { return false }
        committed = value
        subject.send(value.snapshot)
        return operation == token && snapshot.generation == value.snapshot.generation && snapshot.revision == value.snapshot.revision
    }
    nonisolated private static func validUserID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !value.contains("/") && value != "." && value != ".."
            && !(value.hasPrefix("__") && value.hasSuffix("__"))
    }
}
