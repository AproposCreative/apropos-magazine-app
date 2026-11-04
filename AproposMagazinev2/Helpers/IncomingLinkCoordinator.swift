import CryptoKit
import Foundation

/// Memory-only, pseudonymous ownership. Initial unknown authentication is never
/// assumed to be guest; a fresh public intent can wait unowned for confirmation.
enum IncomingLinkContext: Equatable, Sendable {
    case unresolved, guest, account(String)
    static func confirmed(userID: String?) -> Self {
        guard let userID else { return .guest }
        guard !userID.isEmpty, userID.utf8.count <= 512,
              userID.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
              !userID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return .unresolved }
        let digest = SHA256.hash(data: Data(("apropos/incoming-links/v1\u{0}" + userID).utf8))
        return .account(digest.map { String(format: "%02x", $0) }.joined())
    }
    fileprivate var isResolved: Bool {
        switch self {
        case .unresolved: return false
        case .guest: return true
        case .account(let value): return value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
}

/// One actual resolver slot and one latest pending intent. A cancelled provider
/// may still be running; only its exact completion releases the slot. Completion
/// does not revoke a validator already handed to an owned ready/seek operation.
@MainActor
final class IncomingLinkCoordinator {
    typealias Cancel = @MainActor () -> Void
    struct Ticket: Equatable, Sendable {
        fileprivate let coordinatorID: UUID
        fileprivate let requestID: UUID
        fileprivate let contextID: UUID
    }
    struct Request: Equatable, Sendable {
        let link: DeepLink
        let fallbackIdentifier: String?
        let ticket: Ticket
    }
    private struct Pending {
        let id: UUID
        let link: DeepLink
        let fallbackIdentifier: String?
        /// nil means accepted while unresolved, never an earlier account intent.
        var contextID: UUID?
    }
    private final class Active {
        let request: Request
        var cancel: Cancel?
        var cancellationRequested = false
        var finished = false
        init(_ request: Request) { self.request = request }
    }
    private let deliver: @MainActor (Request) -> Cancel
    private let onInvalidate: @MainActor () -> Void
    private let coordinatorID = UUID()
    private(set) var context = IncomingLinkContext.unresolved
    private(set) var isUIReady = false
    private var contextID = UUID()
    private var latestID: UUID?
    private var pending: Pending?
    private var active: Active?
    private var invalidationDepth = 0

    init(onInvalidate: @escaping @MainActor () -> Void = {}, deliver: @escaping @MainActor (Request) -> Cancel) {
        self.onInvalidate = onInvalidate; self.deliver = deliver
    }
    @discardableResult func accept(_ url: URL) -> Bool {
        guard let link = DeepLink.parse(url) else { return false }
        return accept(link)
    }
    @discardableResult func accept(_ link: DeepLink, fallbackIdentifier: String? = nil) -> Bool {
        guard link.isValid, fallbackIdentifier.map({ link.supportsFallbackIdentifier && DeepLink.isValidIdentifier($0) }) ?? true else { return false }
        let hadAuthority = latestID != nil
        let id = UUID()
        latestID = id
        pending = Pending(id: id, link: link, fallbackIdentifier: fallbackIdentifier == link.identifier ? nil : fallbackIdentifier,
                          contextID: context.isResolved ? contextID : nil)
        revokeActive(notify: hadAuthority)
        drain()
        return true
    }
    func setUIReady(_ ready: Bool) {
        guard isUIReady != ready else { return }
        isUIReady = ready
        if ready { drain() }
        else { invalidate() }
    }
    func changeContext(to proposed: IncomingLinkContext) {
        let desired = proposed.isResolved ? proposed : .unresolved
        guard desired != context else { return }
        let keepUnowned = context == .unresolved && pending?.contextID == nil
        let hadAuthority = latestID != nil
        context = desired; contextID = UUID()
        if keepUnowned, var value = pending {
            value.contextID = desired.isResolved ? contextID : nil
            pending = value;latestID = value.id
        } else { pending = nil;latestID = nil }
        revokeActive(notify: hadAuthority)
        drain()
    }
    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.coordinatorID == coordinatorID && ticket.requestID == latestID
            && ticket.contextID == contextID && context.isResolved && isUIReady
    }
    /// Always retire the original resolver in defer, even for stale/error paths.
    /// An old completion cannot release a newer active slot or revoke a seek.
    func complete(_ ticket: Ticket) {
        guard let current = active, current.request.ticket == ticket else { return }
        current.finished = true;current.cancel = nil;active = nil
        drain()
    }
    func invalidate() {
        let hadAuthority = latestID != nil
        latestID = nil;pending = nil
        revokeActive(notify: hadAuthority)
    }
    private func revokeActive(notify: Bool) {
        let previous = active
        previous?.cancellationRequested = true
        let cancel = previous?.cancel
        previous?.cancel = nil
        invalidationDepth += 1
        // Original validators are already false before any injected callback.
        if notify { onInvalidate() }
        cancel?()
        invalidationDepth -= 1
    }
    private func drain() {
        guard invalidationDepth == 0, active == nil, isUIReady, context.isResolved,
              let value = pending, value.id == latestID else { return }
        guard value.contextID == nil || value.contextID == contextID else { pending = nil;return }
        pending = nil
        let ticket = Ticket(coordinatorID: coordinatorID, requestID: value.id, contextID: contextID)
        let current = Active(Request(link: value.link, fallbackIdentifier: value.fallbackIdentifier, ticket: ticket))
        active = current
        let cancel = deliver(current.request)
        if current.cancellationRequested { cancel() }
        else if !current.finished, active === current { current.cancel = cancel }
    }
}
