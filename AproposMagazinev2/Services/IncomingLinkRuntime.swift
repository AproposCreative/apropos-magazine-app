import Combine
import Foundation

/// One process-lifetime ingress. Constructors and acceptance open no SDKs or
/// transport; delivery additionally needs preparation, a resolver and actual UI.
@MainActor
final class IncomingLinkRuntime: ObservableObject {
    typealias Request = IncomingLinkCoordinator.Request
    typealias Ticket = IncomingLinkCoordinator.Ticket
    typealias Resolve = @MainActor (Request) async -> Void
    static let shared = IncomingLinkRuntime(disabled:
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled,
        startupReady: {
            let auth = AuthService.shared // Inert bootstrap identity; no SDK work.
            return readerStartupReady(startup: .application, identity: auth.bootstrapIdentity,
                permission: { auth.captureReaderWorkPermission() != nil })
        })
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private(set) var message: String?
    private(set) var messageID: UUID?
    private(set) var hasAcceptedIncomingLink = false
    private(set) var acceptedIntentRevision = UUID()
    private let disabled: Bool
    private let startupReady: @MainActor () -> Bool
    private var readinessID = UUID()
    private var prepared = false
    private var uiReady = false
    private var routePlayerWork = false
    private var bindingID = UUID()
    private var resolve: Resolve?
    private var cancelPendingSeek: (@MainActor () -> Void)?
    private lazy var ingress: IncomingLinkCoordinator = IncomingLinkCoordinator(onInvalidate: { [weak self] in
        guard let self else { return }
        self.message = nil
        self.messageID = nil
        self.objectWillChange.send()
        if self.routePlayerWork {
            self.routePlayerWork = false
            self.cancelPendingSeek?()
        }
    }, deliver: { [weak self] request in
        guard let self, let resolve = self.resolve else { return {} }
        let task = Task { @MainActor [weak self] in
            defer { self?.ingress.complete(request.ticket) }
            guard let self, self.isCurrent(request.ticket) else { return }
            await resolve(request)
        }
        // Cancellation revokes authority but does not release the occupied read
        // slot until the actual resolver returns and completes its original ID.
        return { task.cancel() }
    })

    init(disabled: Bool, startupReady: @escaping @MainActor () -> Bool = { true }) {
        self.disabled = disabled; self.startupReady = startupReady
    }
    /// Do not ask a permission provider that can touch Auth until reader startup
    /// permits it. Keep the original canonical context through provider reentry.
    static func readerStartupReady(startup: ReaderSDKStartupState, identity: CanonicalSessionState,
                                   permission: @MainActor () -> Bool) -> Bool {
        let original = identity.contextTicket()
        guard startup.permitsReaderServices(identity: identity) else { return false }
        let allowed = permission()
        return allowed && identity.isCurrent(original) && startup.permitsReaderServices(identity: identity)
    }
    func prepareIfNeeded() {
        guard !disabled else { return }
        prepared = true
        updateReadiness()
    }
    func bindResolver(_ resolve: @escaping Resolve, cancelPendingSeek: @escaping @MainActor () -> Void) {
        guard !disabled else { return }
        let own = UUID()
        bindingID = own
        // First bind preserves cold ingress. Replacement revokes the previous
        // presentation before swapping effects, retaining its active read slot.
        if self.resolve != nil { ingress.invalidate() }
        guard bindingID == own else { return }
        self.resolve = resolve
        self.cancelPendingSeek = cancelPendingSeek
        updateReadiness()
    }
    @discardableResult func accept(_ url: URL) -> Bool {
        guard !disabled, updateReadiness() else { return false }
        let accepted = ingress.accept(url)
        if accepted { hasAcceptedIncomingLink = true; acceptedIntentRevision = UUID(); objectWillChange.send() }
        return accepted
    }
    @discardableResult func accept(_ link: DeepLink, fallbackIdentifier: String? = nil) -> Bool {
        guard !disabled, updateReadiness() else { return false }
        let accepted = ingress.accept(link, fallbackIdentifier: fallbackIdentifier)
        if accepted { hasAcceptedIncomingLink = true; acceptedIntentRevision = UUID(); objectWillChange.send() }
        return accepted
    }
    @discardableResult func acceptNotification(_ payload: NotificationNavigation.Payload) -> Bool {
        let link: DeepLink = payload.isPodcastNotification
            ? .podcast(id: payload.articleIdentifier, startSeconds: nil) : .article(id: payload.articleIdentifier)
        return accept(link, fallbackIdentifier: payload.articleSlug == payload.articleIdentifier ? nil : payload.articleSlug)
    }
    func changeAccountContext(userID: String?) {
        guard !disabled else { return }
        guard updateReadiness() else { return }
        ingress.changeContext(to: .confirmed(userID: userID))
    }
    func suspendForAccountChange() {
        guard !disabled else { return }
        readinessID = UUID()
        ingress.changeContext(to: .unresolved)
    }
    func setUIReady(_ ready: Bool) {
        guard !disabled else { return }
        uiReady = ready
        updateReadiness()
    }
    /// Called after the original guarded startup is released; no new link is needed.
    func refreshStartupReadiness() {
        guard !disabled else { return }
        updateReadiness()
    }
    func isCurrent(_ ticket: Ticket) -> Bool {
        guard !disabled, ingress.isCurrent(ticket) else { return false }
        let ready = startupReady() // May reenter an account/intent change.
        guard ingress.isCurrent(ticket) else { return false }
        guard ready else {
            readinessID = UUID()
            ingress.setUIReady(false) // Revoke observed old authority; never resurrect it on reopening.
            return false
        }
        return true
    }
    @discardableResult func willStartPlayerWork(ticket: Ticket) -> Bool {
        guard isCurrent(ticket) else { return false }
        routePlayerWork = true
        return true
    }
    func showMessage(_ value: String, ticket: Ticket) {
        guard isCurrent(ticket) else { return }
        objectWillChange.send()
        guard isCurrent(ticket) else { return }
        message = value
        messageID = UUID()
    }
    func dismissMessage(id: UUID) {
        guard messageID == id else { return }
        message = nil;messageID = nil;objectWillChange.send()
    }
    @discardableResult private func updateReadiness() -> Bool {
        let own = UUID(); readinessID = own
        let startupIsReady = startupReady()
        guard readinessID == own else { return false }
        ingress.setUIReady(prepared && uiReady && resolve != nil && startupIsReady)
        return readinessID == own
    }
}

/// Bounded, deterministic decisions used by the actual resolver. Catalog
/// matching cannot authorize unpublished data or invent an episode binding.
enum IncomingLinkResolutionPolicy {
    static func article(identifier: String, in articles: [Article], permits: (Article) -> Bool) -> Article? {
        let exact = articles.filter { $0.id == identifier }
        let matches = exact.isEmpty ? articles.filter { $0.slug == identifier } : exact
        let byID = Dictionary(grouping: matches, by: \.id)
        guard byID.count == 1, let values = byID.values.first, let value = values.first,
              values.allSatisfy({ $0.bodyRevision == value.bodyRevision && $0.isPubliclyPublished }),
              value.isPubliclyPublished, permits(value) else { return nil }
        return value
    }
    /// A partial local catalog proves only an exact canonical document ID.
    /// One cached slug match cannot establish global slug uniqueness.
    static func offlineArticle(identifier: String, in articles: [Article], permits: (Article) -> Bool) -> Article? {
        let exact = articles.filter { $0.id == identifier }
        return article(identifier: identifier, in: exact, permits: permits)
    }
    static func episode(for article: Article, in episodes: [PodcastEpisode]) -> PodcastEpisode? {
        guard article.isPubliclyPublished else { return nil }
        let candidates = episodes.filter { episode in
            guard episode.hasPlayableAudioURL else { return false }
            if let id = episode.articleId, !id.isEmpty {
                guard id == article.id else { return false }
            } else {
                guard let slug = episode.articleSlug, !slug.isEmpty, slug == article.slug else { return false }
            }
            if let slug = episode.articleSlug, !slug.isEmpty, let canonical = article.slug, !canonical.isEmpty,
               slug != canonical { return false }
            return !episode.isAINarration || (episode.sourceContentRevision != nil && episode.sourceContentRevision == article.bodyRevision)
        }
        let human = candidates.filter { !$0.isAINarration }
        if human.count == 1 { return human[0] }
        guard human.isEmpty, candidates.count == 1 else { return nil }
        return candidates.first
    }
}
