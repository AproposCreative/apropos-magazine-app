import Foundation

struct ArticleDetailRequestIdentity: Hashable {
    let id: String
    let bodyRevision: String?
    let createdOn: String?
    let availabilityRevision: String?

    init(_ article: Article, availabilityRevision: String? = nil) {
        id = article.id
        bodyRevision = article.bodyRevision
        createdOn = article.createdOn
        self.availabilityRevision = availabilityRevision
    }
}

enum ArticleDetailContentPolicy {
    static func hasBody(_ article: Article?) -> Bool {
        guard let article, article.isPubliclyPublished, let content = article.content else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func sameRevision(_ lhs: Article, _ rhs: Article) -> Bool {
        lhs.bodyRevision == rhs.bodyRevision && lhs.createdOn == rhs.createdOn
    }

    static func canApplyFetchedBody(_ incoming: Article, requestedFrom: Article?, current: Article?) -> Bool {
        guard let current else { return true }
        // getDocument can return an older disk snapshot when connectivity
        // fails. Matching request metadata must not authorize that regression.
        if let incomingDate = incoming.revisionDate,
           let currentDate = current.revisionDate, incomingDate < currentDate {
            return false
        }
        if sameRevision(incoming, current) { return true }
        // A newer detail may arrive before the next feed refresh. It is safe
        // while the feed still has the revision from this request's selection.
        return requestedFrom.map { sameRevision($0, current) } ?? false
    }



    static func applyingAuthor(
        _ author: Author, articleID: String, authorID: String, to current: Article?
    ) -> Article? {
        guard var current, current.id == articleID, current.authorID == authorID else { return nil }
        current.author = author
        return current
    }

    /// A current feed revision takes precedence over a previously opened body.
    static func cachedArticle(
        id: String, feed: Article?, full: Article?, initial: Article?
    ) -> Article? {
        let feed = feed.flatMap { $0.id == id ? $0 : nil }
        let candidates = [feed, full, initial].compactMap { $0 }.filter { $0.id == id }
        if let body = candidates.first(where: { candidate in
            hasBody(candidate) && (feed.map { sameRevision($0, candidate) } ?? true)
        }) {
            return body
        }
        return feed ?? candidates.first
    }
}

enum ArticleDetailBodyOrigin {
    case cached
    case fetched(requestedFrom: Article?)
    case offlineFallback
}

/// Serializes non-cancellable callback transports. Superseded selections keep
/// their transport slot until completion/deadline; only the latest pending
/// selection survives. Request UUIDs reject late callbacks and old deadlines.
@MainActor
final class ArticleDetailLoader {
    typealias FetchArticle = (String, @escaping (Result<Article, Error>) -> Void) -> Void
    typealias FetchAuthor = (String, @escaping (Result<Author, Error>) -> Void) -> Void
    typealias ScheduleDeadline = (TimeInterval, @escaping () -> Void) -> (() -> Void)

    private struct Selection {
        let id: String
        let generation: UUID
        let cached: Article?
        let canFetch: Bool
    }

    private enum Phase { case body, author }

    private struct Request {
        let token: UUID
        var selection: Selection
        var phase: Phase
        var body: Article?
        var allowsRejoin = true
        var cancelDeadline: (() -> Void)?
    }

    private let fetchArticle: FetchArticle
    private let fetchAuthor: FetchAuthor
    private let permitsBody: (Article) -> Bool
    private let offlineArticle: (String) -> Article?
    private let onBody: (Article, ArticleDetailBodyOrigin) -> Void
    private let onAuthor: (String, String, Author) -> Void
    private let onFailure: (String, Error) -> Void
    private let onLoadingChange: (Set<String>) -> Void
    private let scheduleDeadline: ScheduleDeadline
    private let timeout: TimeInterval
    private var selection: Selection?
    private var pending: Selection?
    private var active: Request?

    init(
        timeout: TimeInterval = 15,
        scheduleDeadline: ScheduleDeadline? = nil,
        fetchArticle: @escaping FetchArticle,
        fetchAuthor: @escaping FetchAuthor,
        offlineArticle: @escaping (String) -> Article? = { _ in nil },
        permitsBody: @escaping (Article) -> Bool = { $0.isPubliclyPublished },
        onBody: @escaping (Article, ArticleDetailBodyOrigin) -> Void,
        onAuthor: @escaping (String, String, Author) -> Void,
        onFailure: @escaping (String, Error) -> Void = { _, _ in },
        onLoadingChange: @escaping (Set<String>) -> Void = { _ in }
    ) {
        self.timeout = timeout
        self.fetchArticle = fetchArticle
        self.fetchAuthor = fetchAuthor
        self.permitsBody = permitsBody
        self.offlineArticle = offlineArticle
        self.onBody = onBody
        self.onAuthor = onAuthor
        self.onFailure = onFailure
        self.onLoadingChange = onLoadingChange
        self.scheduleDeadline = scheduleDeadline ?? { seconds, fire in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
                catch { return }
                fire()
            }
            return { task.cancel() }
        }
    }

    deinit {
        active?.cancelDeadline?()
    }

    func select(id: String, cached: Article? = nil, canFetch: Bool = true) {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cached = cached.flatMap { $0.id == id && permitsBody($0) ? $0 : nil }
        let next = Selection(id: id, generation: UUID(), cached: cached, canFetch: canFetch)
        selection = next
        pending = nil

        if ArticleDetailContentPolicy.hasBody(cached), let cached {
            onBody(cached, .cached)
            if cached.author != nil || cached.authorID?.isEmpty != false || !canFetch {
                notifyLoading()
                return
            }
        }
        guard canFetch else {
            notifyLoading()
            return
        }

        if var request = active, request.allowsRejoin, request.selection.id == id,
           revisionsMatch(request.selection.cached, cached) {
            // A repeated appearance joins the same body/author transport.
            request.selection = next
            active = request
            if let body = request.body { onBody(body, .fetched(requestedFrom: request.selection.cached)) }
        } else {
            pending = next
        }
        startNextIfPossible()
        notifyLoading()
    }

    func deselect(id: String) {
        guard selection?.id == id else { return }
        selection = nil
        pending = nil
        notifyLoading()
    }

    private func revisionsMatch(_ lhs: Article?, _ rhs: Article?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)): return ArticleDetailContentPolicy.sameRevision(lhs, rhs)
        default: return false
        }
    }

    private func isSelected(_ request: Request) -> Bool {
        selection?.generation == request.selection.generation
    }

    private func notifyLoading() {
        var ids = Set<String>()
        if let active, isSelected(active) { ids.insert(active.selection.id) }
        if let pending { ids.insert(pending.id) }
        onLoadingChange(ids)
    }

    private func startNextIfPossible() {
        guard active == nil, let next = pending else { return }
        pending = nil
        let token = UUID()
        let hasBody = ArticleDetailContentPolicy.hasBody(next.cached)
        active = Request(token: token, selection: next, phase: hasBody ? .author : .body, body: hasBody ? next.cached : nil)
        let cancel = scheduleDeadline(timeout) { [weak self] in self?.didTimeout(token: token) }
        // Also tolerate a deterministic injected scheduler firing synchronously.
        guard active?.token == token else { cancel(); return }
        active?.cancelDeadline = cancel
        if hasBody, let article = next.cached {
            startAuthor(for: article, token: token)
        } else {
            fetchArticle(next.id) { [weak self] result in self?.didFetchBody(result, token: token) }
        }
    }

    private func didFetchBody(_ result: Result<Article, Error>, token: UUID) {
        guard let request = active, request.token == token, request.phase == .body else { return }
        guard isSelected(request) else { finish(token: token); return }
        switch result {
        case .success(let article):
            guard article.id == request.selection.id, permitsBody(article) else {
                fail(NSError(domain: "ArticleDetailLoader", code: 1), token: token)
                return
            }
            active?.body = article
            active?.phase = .author
            onBody(article, .fetched(requestedFrom: request.selection.cached))
            startAuthor(for: article, token: token)
        case .failure(let error):
            fail(error, token: token)
        }
    }

    private func startAuthor(for article: Article, token: UUID) {
        guard let request = active, request.token == token, isSelected(request) else {
            finish(token: token)
            return
        }
        guard article.author == nil, let authorID = article.authorID, !authorID.isEmpty else {
            finish(token: token)
            return
        }
        fetchAuthor(authorID) { [weak self] result in
            guard let self, let current = self.active,
                  current.token == token, current.phase == .author else { return }
            if self.isSelected(current), case .success(let author) = result {
                self.onAuthor(article.id, authorID, author)
            }
            self.finish(token: token)
        }
    }

    func invalidate(id: String) {
        if active?.selection.id == id { active?.allowsRejoin = false }
        deselect(id: id)
    }

    private func fail(_ error: Error, token: UUID) {
        guard let request = active, request.token == token else { return }
        if isSelected(request) {
            let explicitlyWithdrawn: Bool
            if let error = error as? FirestoreArticleError, case .withdrawn = error { explicitlyWithdrawn = true }
            else { explicitlyWithdrawn = false }
            if request.phase == .body, !explicitlyWithdrawn,
               let offline = offlineArticle(request.selection.id), permitsBody(offline), ArticleDetailContentPolicy.hasBody(offline) {
                onBody(offline, .offlineFallback)
            }
            onFailure(request.selection.id, error)
        }
        finish(token: token)
    }

    private func didTimeout(token: UUID) {
        fail(URLError(.timedOut), token: token)
    }

    private func finish(token: UUID) {
        guard let request = active, request.token == token else { return }
        request.cancelDeadline?()
        active = nil
        startNextIfPossible()
        notifyLoading()
    }
}
