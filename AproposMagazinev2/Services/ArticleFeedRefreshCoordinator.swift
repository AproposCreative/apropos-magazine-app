import Foundation

/// Owns one feed request across launch, foreground and manual refresh callers.
/// The transport and deadline are injected so lifecycle/race tests use no services.
@MainActor
final class ArticleFeedRefreshCoordinator {
    typealias ResultHandler = (Result<[Article], Error>) -> Void
    typealias Permission = @MainActor () -> Bool
    typealias Fetch = (@escaping Permission, @escaping ResultHandler) -> Void
    typealias CatalogResultHandler = (Result<ArticleFeedSnapshot.Update, Error>) -> Void
    typealias CatalogFetch = @MainActor (@escaping Permission, @escaping CatalogResultHandler) -> Void
    typealias ScheduleTimeout = (@escaping () -> Void) -> (() -> Void)

    private final class Request {
        let permission: Permission
        let id: UUID
        let task: Task<Void, Never>
        var showsLoading: Bool
        var continuation: CheckedContinuation<Void, Never>?
        var cancelTimeout: (() -> Void)?

        init(id: UUID, task: Task<Void, Never>, showsLoading: Bool, permission: @escaping Permission) {
            self.permission = permission
            self.id = id
            self.task = task
            self.showsLoading = showsLoading
        }
    }

    private let fetch: CatalogFetch
    private let scheduleTimeout: ScheduleTimeout
    private let loadingChanged: (Bool) -> Void
    private let completed: (Result<ArticleFeedSnapshot.Update, Error>, Bool, @escaping Permission) -> Void
    private var request: Request?

    var isRefreshing: Bool { request != nil }

    convenience init(
        fetch: @escaping Fetch,
        scheduleTimeout: ScheduleTimeout? = nil,
        loadingChanged: @escaping (Bool) -> Void,
        completed: @escaping (Result<[Article], Error>, Bool, @escaping Permission) -> Void
    ) {
        self.init(fetchCatalog: { permission, done in
            fetch(permission) { done($0.map(ArticleFeedSnapshot.Update.complete)) }
        }, scheduleTimeout: scheduleTimeout, loadingChanged: loadingChanged,
        completedCatalog: { result, visible, permission in completed(result.map(\.articles), visible, permission) })
    }

    init(fetchCatalog: @escaping CatalogFetch, scheduleTimeout: ScheduleTimeout? = nil,
         loadingChanged: @escaping (Bool) -> Void,
         completedCatalog: @escaping (Result<ArticleFeedSnapshot.Update, Error>, Bool, @escaping Permission) -> Void) {
        self.fetch = fetchCatalog
        self.scheduleTimeout = scheduleTimeout ?? Self.defaultTimeout
        self.loadingChanged = loadingChanged
        self.completed = completedCatalog
    }

    deinit {
        request?.cancelTimeout?()
        request?.continuation?.resume()
        request?.task.cancel()
    }

    /// A manual refresh joins existing work, promoting a silent request's loading
    /// state rather than launching a second query with a competing completion.
    @discardableResult
    func refresh(showsLoading: Bool, stillCurrent: @escaping Permission = { true }) -> Task<Void, Never> {
        guard stillCurrent() else { return Task {} }
        if let current = request, !current.permission(), request?.id == current.id { invalidate() }
        guard stillCurrent() else { return Task {} }
        if let request {
            if showsLoading && !request.showsLoading {
                request.showsLoading = true
                loadingChanged(true)
            }
            return request.task
        }

        let id = UUID()
        let task = Task { [weak self] in
            await withCheckedContinuation { continuation in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.begin(id: id, continuation: continuation)
            }
        }
        request = Request(id: id, task: task, showsLoading: showsLoading, permission: stillCurrent)
        if showsLoading { loadingChanged(true) }
        return task
    }

    func waitForCurrentRefresh() async {
        if let task = request?.task { await task.value }
    }

    /// Firestore callbacks cannot always be cancelled. Invalidating their request
    /// identity makes late results harmless while releasing local waiters.
    func invalidate() {
        guard let current = request else { return }
        request = nil
        current.cancelTimeout?()
        current.task.cancel()
        if current.showsLoading { loadingChanged(false) }
        current.continuation?.resume()
    }

    private func begin(id: UUID, continuation: CheckedContinuation<Void, Never>) {
        guard let current = request, current.id == id else {
            continuation.resume()
            return
        }
        current.continuation = continuation
        guard current.permission(), request?.id == id else {
            if request?.id == id { invalidate() }; return
        }
        current.cancelTimeout = scheduleTimeout { [weak self] in
            self?.finish(id: id, result: .failure(NSError(
                domain: "ArticleViewModel", code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "Timeout ved hentning af artikler"]
            )))
        }
        guard current.permission(), request?.id == id else {
            if request?.id == id { invalidate() }
            return
        }
        // SDK work can outlive this observation. Its later decode/mirror/cache
        // effects must lose authority when this request ends, even if the same
        // account remains permitted or a new refresh has already started.
        let accountPermission = current.permission
        let queryPermission: Permission = { [weak self] in
            guard let self, self.request?.id == id else { return false }
            let allowed = accountPermission()
            return allowed && self.request?.id == id
        }
        fetch(queryPermission) { [weak self] result in
            // A transport may invoke its callback off the UI actor.
            Task { @MainActor in self?.finish(id: id, result: result) }
        }
    }

    private func finish(id: UUID, result: Result<ArticleFeedSnapshot.Update, Error>) {
        guard let current = request, current.id == id else { return }
        request = nil
        current.cancelTimeout?()
        if current.showsLoading { loadingChanged(false) }
        if current.permission(), request == nil { completed(result, current.showsLoading, current.permission) }
        current.continuation?.resume()
    }

    private static func defaultTimeout(_ action: @escaping () -> Void) -> () -> Void {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) }
            catch { return }
            action()
        }
        return { task.cancel() }
    }
}
