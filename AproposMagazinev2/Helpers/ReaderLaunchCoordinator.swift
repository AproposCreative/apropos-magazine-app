import Combine
import Foundation

/// The startup/replay presenter advances only after UIKit/SwiftUI confirms that
/// the previous modal was dismissed. No storage, account or permission effects.
@MainActor
final class ReaderLaunchCoordinator: ObservableObject {
    enum Kind: Equatable { case introduction, whatsNew, account, newsletter }
    struct Presentation: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        var accountEntry = ReaderAccountEntry(topicIDs: [])
        var selectedTopicIDs: [String] { accountEntry.topicIDs }
    }
    enum FollowUp { case account(ReaderAccountEntry), newsletter }
    private struct State {
        var didDecideStartup = false
        var presented: Presentation?
        var dismissing: Presentation?
        var pending: Presentation?
        var accountHandoffContext: CanonicalSessionState.ContextTicket?
    }
    private var state = State()
    private let presentationAllowed: @MainActor () -> Bool
    private var operation = UUID()
    private var hasAdmittedOperation = false
    private var denied = false
    private var checkingPermission = false
    init(presentationAllowed: @escaping @MainActor () -> Bool = { true }) {
        self.presentationAllowed = presentationAllowed
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    var cover: Presentation? { state.presented?.kind == .introduction ? state.presented : nil }
    var sheet: Presentation? { state.presented?.kind != .introduction ? state.presented : nil }
    var isAwaitingDismissal: Bool { state.dismissing != nil }
    var isIdle: Bool { state.presented == nil && state.dismissing == nil }

    func start(needsIntroduction: Bool, needsWhatsNew: Bool, blocked: Bool) {
        guard !state.didDecideStartup else { return }
        let token = reserve()
        guard permits(token) else { return }
        var next = state
        next.didDecideStartup = true
        if !blocked, isIdle {
            if needsIntroduction { next.presented = Presentation(kind: .introduction) }
            else if needsWhatsNew { next.presented = Presentation(kind: .whatsNew) }
        }
        commitPresentation(next, token: token)
    }
    func replay() {
        guard isIdle else { return }
        let token = reserve()
        guard permits(token) else { return }
        var next = state
        next.didDecideStartup = true
        next.presented = Presentation(kind: .introduction)
        commitPresentation(next, token: token)
    }
    func finishIntroduction(then followUp: FollowUp? = nil,
                            accountContext: CanonicalSessionState.ContextTicket? = nil) {
        guard let original = cover else { return }
        let token = reserve()
        guard permits(token), state.presented?.id == original.id else { return }
        var next = state
        next.presented = nil
        next.dismissing = original
        switch followUp {
        case .account(let entry):
            next.accountHandoffContext = accountContext
            next.pending = Presentation(kind: .account, accountEntry: entry)
        case .newsletter: next.pending = Presentation(kind: .newsletter)
        case nil: next.pending = nil
        }
        commitPresentation(next, token: token)
    }
    func dismissCover() { dismiss(kind: .introduction) }
    func reconcileAccountHandoff(with canonical: CanonicalSessionState) {
        let token = operation
        if let original = state.accountHandoffContext, !canonical.isCurrent(original), operation == token { suspend() }
    }
    func accountDidAppear() {
        guard sheet?.kind == .account else { return }
        let token = reserve()
        guard permits(token) else { return }
        var next = state
        next.accountHandoffContext = nil
        commitPresentation(next, token: token)
    }
    func dismissSheet() {
        guard let kind = sheet?.kind else { return }
        dismiss(kind: kind)
    }
    private func dismiss(kind: Kind) {
        guard let original = state.presented, original.kind == kind else { return }
        let token = reserve()
        var next = state
        next.presented = nil; next.dismissing = original; next.pending = nil; next.accountHandoffContext = nil
        commitCleanup(next, token: token)
    }
    func coverDidDismiss() { didDismiss(isCover: true) }
    func sheetDidDismiss() { didDismiss(isCover: false) }
    private func didDismiss(isCover: Bool) {
        guard let original = state.dismissing,
              (original.kind == .introduction) == isCover else { return }
        let token = reserve()
        if state.pending != nil {
            guard permits(token), state.dismissing?.id == original.id else {
                // Denial has revoked pending presentation. The matching UIKit
                // dismissal can still retire its original barrier.
                if state.pending == nil, state.dismissing?.id == original.id {
                    let cleanupToken = reserve()
                    var cleanup = state; cleanup.dismissing = nil
                    commitCleanup(cleanup, token: cleanupToken)
                }
                return
            }
        }
        var next = state
        next.dismissing = nil
        next.presented = next.pending
        next.pending = nil
        if next.presented != nil { commitPresentation(next, token: token) }
        else { commitCleanup(next, token: token) }
    }
    /// Incoming navigation wins over an automatic introduction or queued handoff.
    /// Keep the dismissal barrier until the actual presentation callback arrives.
    func suspend() {
        let token = reserve()
        let allowed = permits(token)
        guard operation == token else { return }
        var next = state
        // Initial recovery loading must not consume the later normal startup.
        next.didDecideStartup = next.didDecideStartup || allowed || hasAdmittedOperation
        next.pending = nil
        next.accountHandoffContext = nil
        if let original = next.presented {
            next.presented = nil; next.dismissing = original
        }
        commitCleanup(next, token: token)
    }
    private func reserve() -> UUID { operation = UUID(); return operation }
    private func permits(_ token: UUID) -> Bool {
        guard operation == token, !denied, !checkingPermission else { return false }
        checkingPermission = true
        let allowed = presentationAllowed()
        checkingPermission = false
        guard operation == token, !denied else { return false }
        guard allowed else {
            if hasAdmittedOperation { revoke() }
            return false
        }
        return true
    }
    private func revoke() {
        denied = true; operation = UUID()
        state.pending = nil; state.accountHandoffContext = nil
        if let original = state.presented { state.presented = nil; state.dismissing = original }
        objectWillChange.send()
    }
    private func commitPresentation(_ value: State, token: UUID) {
        guard permits(token) else { return }
        hasAdmittedOperation = true
        state = value
        objectWillChange.send()
        // Publication is an external hook. Never endorse the old operation
        // after a subscriber closed admission or installed newer state.
        guard operation == token else { return }
        _ = permits(token)
    }
    private func commitCleanup(_ value: State, token: UUID) {
        guard operation == token else { return }
        state = value
        objectWillChange.send()
        guard operation == token else { return }
        _ = permits(token)
    }
}
