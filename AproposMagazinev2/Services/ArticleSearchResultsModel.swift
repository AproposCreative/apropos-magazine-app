import Combine
import Foundation

@MainActor
final class ArticleSearchResultsModel: ObservableObject {
    @Published private(set) var page = ArticleSearchPage.empty
    @Published private(set) var isUpdating = false

    private struct Request: Equatable {
        let revision: UInt64
        let query: String
        let sort: ArticleSortOption
    }

    private let processor: any ArticleSearchProcessing
    private let debounceNanoseconds: UInt64
    private let pageSize: Int
    private var articles: [Article] = []
    private var authors: [Author] = []
    private var contentRevision: UInt64 = 0
    private var generation: UInt64 = 0
    private var query = ""
    private var sort: ArticleSortOption = .newest
    private var isActive = false
    private var searchTask: Task<Void, Never>?
    private var contentSubscription: AnyCancellable?
    private enum ContentChange { case articles([Article]), authors([Author]) }
    private var completedRequest: Request?
    private var result = ArticleSearchSnapshot.empty

    init(
        processor: any ArticleSearchProcessing = ArticleSearchWorker(),
        debounceNanoseconds: UInt64 = 300_000_000,
        pageSize: Int = 20
    ) {
        self.processor = processor
        self.debounceNanoseconds = debounceNanoseconds
        self.pageSize = max(1, pageSize)
    }

    deinit { searchTask?.cancel() }

    /// Subscribe once per visible session. Keeping the subscription here avoids
    /// recreating a current-value publisher whenever the SwiftUI body updates.
    func observeContent<Articles: Publisher, Authors: Publisher>(
        articles: Articles,
        authors: Authors
    ) where Articles.Output == [Article], Articles.Failure == Never, Authors.Output == [Author], Authors.Failure == Never {
        guard contentSubscription == nil else { return }
        // Feed changes are committed post-state events and deliberately do not
        // replay a former owner. Authors must still refresh the accepted feed
        // before any new article event has arrived.
        contentSubscription = articles.map(ContentChange.articles)
            .merge(with: authors.map(ContentChange.authors)).sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .articles(let values): self.updateContent(articles: values, authors: self.authors)
                case .authors(let values): self.updateContent(articles: self.articles, authors: values)
                }
            }
    }

    @discardableResult
    func updateContent(articles: [Article], authors: [Author]) -> Task<Void, Never>? {
        // Reappearing lists supply the same feed again. Preserve their loaded
        // page unless a full value changed; Article/Author equality includes
        // content and metadata, unlike Article's ID-only hash implementation.
        guard self.articles != articles || self.authors != authors else { return nil }
        self.articles = articles
        self.authors = authors
        contentRevision &+= 1
        return scheduleSearch(debounce: false)
    }

    @discardableResult
    func updateQuery(_ query: String) -> Task<Void, Never>? {
        let normalized = query.lowercased()
        guard self.query != normalized else { return nil }
        self.query = normalized
        return scheduleSearch(debounce: true)
    }

    @discardableResult
    func updateSort(_ sort: ArticleSortOption) -> Task<Void, Never>? {
        guard self.sort != sort else { return nil }
        self.sort = sort
        return scheduleSearch(debounce: false)
    }

    @discardableResult
    func activate() -> Task<Void, Never>? {
        isActive = true
        return scheduleSearch(debounce: false)
    }

    func deactivate() {
        isActive = false
        generation &+= 1
        searchTask?.cancel()
        contentSubscription?.cancel()
        contentSubscription = nil
        isUpdating = false
    }

    func loadMore() {
        guard !isUpdating, page.hasMore else { return }
        let remaining = max(0, result.articles.count - page.articles.count)
        page = result.page(visibleCount: page.articles.count + min(pageSize, remaining))
    }

    @discardableResult
    private func scheduleSearch(debounce: Bool) -> Task<Void, Never>? {
        generation &+= 1
        let generation = generation
        searchTask?.cancel()
        guard isActive else { return nil }
        let request = Request(revision: contentRevision, query: query, sort: sort)
        guard completedRequest != request else {
            isUpdating = false
            return nil
        }
        isUpdating = true
        let articles = articles
        let authors = authors
        let processor = processor
        let delay = debounce ? debounceNanoseconds : 0
        searchTask = Task { [weak self] in
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                try Task.checkCancellation()
                let snapshot = try await processor.snapshot(
                    articles: articles, authors: authors, revision: request.revision,
                    query: request.query, sort: request.sort
                )
                guard !Task.isCancelled, let self, self.isActive,
                      self.generation == generation else { return }
                self.result = snapshot
                self.page = snapshot.page(visibleCount: self.pageSize)
                self.completedRequest = request
                self.isUpdating = false
            } catch {
                guard let self, self.generation == generation else { return }
                self.isUpdating = false
            }
        }
        return searchTask
    }
}
