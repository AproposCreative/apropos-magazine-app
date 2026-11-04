import Combine
import Foundation

/// The committed, SDK-free account projection. Merely constructing it performs no work.
@MainActor
final class CanonicalSessionState: ObservableObject {
    enum Context: Equatable, Sendable {
        case unresolved, guest, account(String)
        var userID: String? { if case .account(let uid) = self { return uid }; return nil }
    }
    enum VerificationStatus: Equatable { case idle, sending, refreshing }
    struct Snapshot: Equatable {
        let context: Context
        let session: ReaderAccountSession?
        let generation: UUID
        let revision: UInt64
        let verificationMessage: String?
        let verificationStatus: VerificationStatus
        var userID: String? { context.userID }
    }
    struct ContextTicket: Equatable, Sendable {
        let context: Context
        let generation: UUID
        var userID: String? { context.userID }
        fileprivate let modelID: UUID
    }
    struct VerificationTicket: Equatable, Sendable {
        let context: ContextTicket
        var userID: String? { context.userID }
        fileprivate let id: UUID
    }
    struct RefreshTicket: Equatable, Sendable {
        let context: ContextTicket
        var userID: String? { context.userID }
        fileprivate let id: UUID
    }
    private struct Authority {
        var snapshot: Snapshot
        var verificationID: UUID?
        var refreshID: UUID?
    }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    var snapshot: Snapshot { committed.snapshot }
    var changes: AnyPublisher<Snapshot, Never> {
        // The filter belongs to EACH subscription: a nested B publication may
        // otherwise reach subscriber two before the suspended outer A send.
        subject.filter { [weak self] candidate in
            guard let self else { return false }
            return candidate.generation == self.snapshot.generation && candidate.revision == self.snapshot.revision
        }.eraseToAnyPublisher()
    }
    private let modelID = UUID()
    private let subject = PassthroughSubject<Snapshot, Never>()
    private var operation = UUID()
    private var notifying = false
    private var committed = Authority(snapshot: Snapshot(context: .unresolved, session: nil, generation: UUID(), revision: 0,
                                                         verificationMessage: nil, verificationStatus: .idle))

    func contextTicket() -> ContextTicket {
        ContextTicket(context: snapshot.context, generation: snapshot.generation, modelID: modelID)
    }
    func isCurrent(_ ticket: ContextTicket) -> Bool {
        ticket.modelID == modelID && ticket.context == snapshot.context && ticket.generation == snapshot.generation
    }
    func isCurrent(_ ticket: VerificationTicket) -> Bool {
        isCurrent(ticket.context) && committed.verificationID == ticket.id && snapshot.verificationStatus == .sending
    }
    func isCurrent(_ ticket: RefreshTicket) -> Bool {
        isCurrent(ticket.context) && committed.refreshID == ticket.id && snapshot.verificationStatus == .refreshing
    }

    /// Only a confirmed canonical nil means guest. Initial nil is left unresolved.
    @discardableResult
    func adopt(_ original: ReaderAccountSession?, forceNewGeneration: Bool = false,
               stillPermitted: () -> Bool = { true }) -> ContextTicket? {
        let context: Context
        if let original {
            guard Self.validUserID(original.uid) else { return nil }
            context = .account(original.uid)
        } else { context = .guest }
        let token = reserve()
        let permitted = stillPermitted()
        guard permitted, operation == token else { return nil }
        if !forceNewGeneration, context == snapshot.context, original == snapshot.session {
            // A request for the still committed owner during willChange cancels
            // the outer proposal, even when that request needs no assignment.
            return contextTicket()
        }
        let sameOwner = !forceNewGeneration && context == snapshot.context
        let keepRefresh = sameOwner && committed.refreshID != nil && snapshot.verificationStatus == .refreshing
        let keepVerification = sameOwner && original?.isEmailVerified != true
        let value = Authority(snapshot: next(context: context, session: original,
            generation: sameOwner ? snapshot.generation : UUID(),
            message: sameOwner && original?.isEmailVerified != true ? snapshot.verificationMessage : nil,
            status: keepRefresh ? .refreshing : (keepVerification ? snapshot.verificationStatus : .idle)),
            verificationID: keepVerification ? committed.verificationID : nil,
            refreshID: keepRefresh ? committed.refreshID : nil)
        guard commit(value, token: token, stillPermitted: stillPermitted) else { return nil }
        return contextTicket()
    }

    /// Signout revokes actions immediately. A failed signout must adopt its
    /// still-confirmed account again; that adoption receives a fresh generation.
    @discardableResult
    func suspend(stillPermitted: () -> Bool = { true }) -> ContextTicket? {
        let token = reserve()
        let value = Authority(snapshot: next(context: .unresolved, session: nil, generation: UUID(), message: nil, status: .idle))
        guard commit(value, token: token, stillPermitted: stillPermitted) else { return nil }
        return contextTicket()
    }

    /// Provider completions return their original accepted value, never whichever
    /// unrelated account happens to be in a mutable adapter property afterwards.
    func acceptedSession(_ original: ReaderAccountSession, ticket: ContextTicket) -> ReaderAccountSession? {
        guard isCurrent(ticket), ticket.userID == original.uid, snapshot.session == original else { return nil }
        return original
    }

    func beginVerification(context: ContextTicket, stillPermitted: () -> Bool = { true }) -> VerificationTicket? {
        guard isCurrent(context), context.userID != nil, snapshot.session?.isEmailVerified == false,
              snapshot.verificationStatus == .idle else { return nil }
        let token = reserve(), id = UUID()
        let ticket = VerificationTicket(context: context, id: id)
        let value = Authority(snapshot: next(message: nil, status: .sending), verificationID: id)
        guard commit(value, token: token, stillPermitted: stillPermitted), isCurrent(ticket) else { return nil }
        return ticket
    }
    @discardableResult
    func finishVerification(ticket: VerificationTicket, message: String?, stillPermitted: () -> Bool = { true }) -> Bool {
        guard isCurrent(ticket) else { return false }
        let token = reserve()
        return commit(Authority(snapshot: next(message: message, status: .idle)), token: token, stillPermitted: stillPermitted)
    }
    func beginRefresh(context: ContextTicket, stillPermitted: () -> Bool = { true }) -> RefreshTicket? {
        guard isCurrent(context), context.userID != nil, snapshot.verificationStatus == .idle else { return nil }
        let token = reserve(), id = UUID()
        let ticket = RefreshTicket(context: context, id: id)
        let value = Authority(snapshot: next(message: nil, status: .refreshing), refreshID: id)
        guard commit(value, token: token, stillPermitted: stillPermitted), isCurrent(ticket) else { return nil }
        return ticket
    }
    @discardableResult
    func acceptRefresh(_ original: ReaderAccountSession, ticket: RefreshTicket, stillPermitted: () -> Bool = { true }) -> Bool {
        guard isCurrent(ticket), original.uid == ticket.userID else { return false }
        let token = reserve()
        let value = Authority(snapshot: next(session: original,
            message: original.isEmailVerified ? nil : "E-mailen er endnu ikke bekræftet. Åbn linket i bekræftelsesmailen, og prøv igen.", status: .idle))
        return commit(value, token: token, stillPermitted: stillPermitted)
    }
    @discardableResult
    func failRefresh(ticket: RefreshTicket, message: String, stillPermitted: () -> Bool = { true }) -> Bool {
        guard isCurrent(ticket) else { return false }
        let token = reserve()
        return commit(Authority(snapshot: next(message: message, status: .idle)), token: token, stillPermitted: stillPermitted)
    }

    /// A still-occupied older provider slot is an unavailable action, never a
    /// successful request for this account. No work ticket is created here.
    @discardableResult
    func reportUnavailableAction(context: ContextTicket, message: String, stillPermitted: () -> Bool = { true }) -> Bool {
        guard isCurrent(context), context.userID != nil, snapshot.verificationStatus == .idle else { return false }
        let token = reserve()
        return commit(Authority(snapshot: next(message: message, status: .idle)), token: token, stillPermitted: stillPermitted)
    }

    private func reserve() -> UUID { let value = UUID(); operation = value; return value }
    private func next(context: Context? = nil, session: ReaderAccountSession? = nil, generation: UUID? = nil,
                      message: String?, status: VerificationStatus) -> Snapshot {
        let targetContext = context ?? snapshot.context
        let targetSession = targetContext.userID == nil ? nil : (session ?? snapshot.session)
        return Snapshot(context: targetContext, session: targetSession, generation: generation ?? snapshot.generation,
            revision: snapshot.revision == UInt64.max ? UInt64.max : snapshot.revision + 1,
            verificationMessage: message, verificationStatus: status)
    }
    private func commit(_ value: Authority, token: UUID, stillPermitted: () -> Bool = { true }) -> Bool {
        guard operation == token, snapshot.revision < UInt64.max else { return false }
        let beforeNotification = stillPermitted()
        guard operation == token, beforeNotification else { return false }
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        let afterNotification = stillPermitted()
        guard operation == token, afterNotification else { return false }
        committed = value
        subject.send(value.snapshot)
        return operation == token && snapshot.generation == value.snapshot.generation && snapshot.revision == value.snapshot.revision
    }
    nonisolated private static func validUserID(_ uid: String) -> Bool {
        !uid.isEmpty && uid.utf8.count <= 512 && uid == uid.trimmingCharacters(in: .whitespacesAndNewlines)
            && !uid.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !uid.contains("/") && uid != "." && uid != ".."
            && !(uid.hasPrefix("__") && uid.hasSuffix("__"))
    }
}
