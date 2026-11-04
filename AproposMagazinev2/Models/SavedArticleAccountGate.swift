import Combine
import Foundation

/// One in-memory save intention, accepted only by its explicit login receipt.
/// Publications commit together; reentrant cancellation wins over old work.
@MainActor
final class SavedArticleAccountGate: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let originalContext: CanonicalSessionState.ContextTicket
        let article: Article?
        let language: ArticleContentLanguage
        var isModal: Bool { article != nil }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }
    private struct State {
        var request: Request?
        var dismissalID: UUID?
        var isWorking = false
        var message: String?
        var actionID: UUID?
        var acceptedContext: CanonicalSessionState.ContextTicket?
        var setupOwner: CanonicalSessionState.ContextTicket?
        var setupAfterDismissal = false
        var needsSetup = false
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private var state = State()
    private let canonical: CanonicalSessionState
    private var observation: AnyCancellable?
    private var operation = UUID()
    private var notifying = false
    var request: Request? { state.request }
    var isWorking: Bool { state.isWorking }
    var message: String? { state.message }
    var needsSetup: Bool { state.needsSetup && permitsSetup }
    var permitsSetup: Bool { state.setupOwner.map(canonical.isCurrent) == true }
    var isGuest: Bool { canonical.snapshot.context == .guest }
    var isUnresolved: Bool { canonical.snapshot.context == .unresolved }
    var hasAccount: Bool { canonical.snapshot.userID != nil }

    init(canonical: CanonicalSessionState) {
        self.canonical = canonical
        observation = canonical.changes.sink { [weak self] _ in
            guard let self else { return }
            if let owner = self.state.acceptedContext ?? self.state.setupOwner,
               !canonical.isCurrent(owner) { self.cancel() }
        }
    }
    @discardableResult
    func present(article: Article? = nil, language: ArticleContentLanguage) -> Bool {
        let original = canonical.contextTicket()
        guard original.context == .guest, canonical.isCurrent(original),
              article.map({ $0.hasValidContentIdentity && $0.contentLanguage == language }) ?? true else { return false }
        let entry = Request(originalContext: original, article: article, language: language)
        return commit(State(request: entry, dismissalID: entry.id)) {
            self.canonical.isCurrent(original)
        }
    }
    @discardableResult
    func beginLogin(_ id: UUID) -> Bool {
        guard let original = request, canonical.isCurrent(original.originalContext), !isWorking else { return false }
        var next = state
        next.actionID = id; next.acceptedContext = nil; next.message = nil; next.isWorking = true
        return commit(next) { self.request?.id == original.id && self.canonical.isCurrent(original.originalContext) }
    }
    func loginFinished(_ id: UUID) {
        guard state.actionID == id, state.acceptedContext == nil else { return }
        if let original = request, !canonical.isCurrent(original.originalContext) { cancel(); return }
        var next = state; next.actionID = nil; next.isWorking = false
        _ = commit(next)
    }
    @discardableResult
    func accept(_ result: ReaderLoginResult, needsIntroduction: Bool) -> Bool {
        guard let original = request, state.acceptedContext == nil,
              result.actionID == state.actionID, result.originalContext == original.originalContext,
              canonical.acceptedSession(result.session, ticket: result.acceptedContext) != nil else { return false }
        var next = state
        next.acceptedContext = result.acceptedContext
        next.setupOwner = needsIntroduction ? result.acceptedContext : nil
        next.setupAfterDismissal = needsIntroduction; next.isWorking = true
        let accepted = commit(next) {
            self.request?.id == original.id && self.canonical.acceptedSession(result.session, ticket: result.acceptedContext) != nil
        }
        if !accepted, request?.id == original.id, !canonical.isCurrent(result.acceptedContext) { cancel() }
        return accepted
    }
    /// Account/library publications drive this method; no retry timer is used.
    func reconcile(language: ArticleContentLanguage, favorites: FavoritesSnapshot, favoritesContext: FavoritesContext,
                   canSave: Bool, currentArticle: (String) -> Article?, save: (Article) -> Bool) {
        guard let original = request else { return }
        guard original.language == language else { cancel(); return }
        guard let owner = state.acceptedContext else {
            // Exchange may publish an account before delivering its receipt.
            // Such a publication alone still cannot save an article.
            if state.actionID == nil && !canonical.isCurrent(original.originalContext) { cancel() }
            return
        }
        guard canonical.isCurrent(owner), let uid = owner.userID else { cancel(); return }
        guard let requested = original.article else { complete(original, owner: owner); return }
        guard favoritesContext == .confirmed(userID: uid), canSave else { return }
        guard let current = currentArticle(requested.id), current.hasValidContentIdentity,
              current.id == requested.id, current.bodyRevision == requested.bodyRevision,
              current.contentLanguage == original.language else {
            if request?.id == original.id { cancel() }; return
        }
        guard canonical.isCurrent(owner), request?.id == original.id else { return }
        if favorites.articles.contains(where: { $0.id == current.id }) { complete(original, owner: owner); return }
        guard complete(original, owner: owner) else { return }
        // Retired before the effect. A synchronous membership publication cannot
        // consume twice or turn an intended save into removal.
        let saved = save(current)
        if !saved, request == nil, canonical.isCurrent(owner) {
            var next = state; next.message = "Artiklen kunne ikke gemmes. Prøv igen."
            _ = commit(next) { self.request == nil && self.canonical.isCurrent(owner) }
        }
    }
    func cancel() { _ = commit(State()) }
    func presentationDidDismiss(requestID: UUID? = nil) {
        guard let id = requestID ?? state.dismissalID, id == state.dismissalID else { return }
        if request != nil { cancel(); return }
        guard state.setupAfterDismissal, let owner = state.setupOwner else { return }
        guard canonical.isCurrent(owner) else { cancel(); return }
        var next = state; next.setupAfterDismissal = false; next.needsSetup = true
        _ = commit(next) { self.canonical.isCurrent(owner) }
    }
    func acknowledgeSetup() {
        var next = state; next.needsSetup = false; next.setupOwner = nil
        _ = commit(next)
    }
    func clearMessage() { var next = state; next.message = nil; _ = commit(next) }
    @discardableResult
    private func complete(_ original: Request, owner: CanonicalSessionState.ContextTicket) -> Bool {
        var next = state
        next.request = nil; next.actionID = nil; next.acceptedContext = nil; next.isWorking = false
        return commit(next) { self.request?.id == original.id && self.canonical.isCurrent(owner) }
    }
    @discardableResult
    private func commit(_ next: State, stillCurrent: () -> Bool = { true }) -> Bool {
        let token = UUID(); operation = token
        if !notifying {
            notifying = true; objectWillChange.send(); notifying = false
        }
        guard operation == token, stillCurrent(), operation == token else { return false }
        state = next
        return true
    }
}
