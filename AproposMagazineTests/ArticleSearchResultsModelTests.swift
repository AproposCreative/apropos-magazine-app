import Combine
import XCTest
@testable import Apropos

/// Controlled continuations exercise stale completions without sleeps, network,
/// Firebase, or UI startup. The processor deliberately ignores cancellation.
private actor ControlledSearchProcessor: ArticleSearchProcessing {
    private var pending: [String: CheckedContinuation<ArticleSearchSnapshot, Error>] = [:]
    private var observers: [String: CheckedContinuation<Void, Never>] = [:]

    func snapshot(
        articles: [Article], authors: [Author], revision: UInt64,
        query: String, sort: ArticleSortOption
    ) async throws -> ArticleSearchSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation
            observers.removeValue(forKey: query)?.resume()
        }
    }

    func waitForRequest(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { observers[query] = $0 }
    }

    func complete(_ query: String, articles: [Article]) {
        pending.removeValue(forKey: query)?.resume(returning: ArticleSearchSnapshot(articles: articles))
    }
}

final class ArticleSearchResultsModelTests: XCTestCase {
    @MainActor
    func testLanguageProjectionHidesOldPageWhileReplacementSearchIsHeld() async throws {
        let processor = ControlledSearchProcessor()
        let model = ArticleSearchResultsModel(processor: processor, debounceNanoseconds: 0)
        let source = "0123456789abcdef01234567"
        let da = article(source)
        let en = Article(id: "en_" + source, name: "English story", slug: "story", content: "English body",
            intro: "English intro", topicID: "music", contentLanguage: .english,
            sourceArticleID: source, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        model.updateContent(articles: [da], authors: [])
        let initial = try XCTUnwrap(model.activate())
        await processor.waitForRequest("")
        await processor.complete("", articles: [da]); await initial.value
        XCTAssertEqual(model.page.articles.map(\.id), [da.id])
        let replacement = try XCTUnwrap(model.updateContent(articles: [en], authors: []))
        await processor.waitForRequest("")
        XCTAssertTrue(model.isUpdating)
        XCTAssertEqual(model.page.articles.map(\.id), [da.id], "Hold proves the prior page really remains")
        XCTAssertTrue(ArticleLanguageSelection.visible(model.page.articles, language: .english).isEmpty,
            "The exact native row policy removes the previous language immediately")
        await processor.complete("", articles: [en]); await replacement.value
        XCTAssertEqual(ArticleLanguageSelection.visible(model.page.articles, language: .english).map(\.id), [en.id])
    }

    private func article(_ id: String, authorID: String? = nil) -> Article {
        Article(id: id, name: id, slug: id, content: "", intro: "", topicID: "music", authorID: authorID)
    }

    @MainActor
    func testAuthorsOnlyChangeRefreshesCurrentFeedWithoutReplayFromArticlePublisher() async {
        final class Metadata: ObservableObject { @Published var authors: [Author] = [] }
        let metadata = Metadata()
        let changes = PassthroughSubject<[Article], Never>()
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.observeContent(articles: changes.eraseToAnyPublisher(), authors: metadata.$authors)
        model.updateContent(articles: [article("story", authorID: "writer")], authors: [])
        await model.updateQuery("Journalist")?.value
        await model.activate()?.value
        XCTAssertTrue(model.page.articles.isEmpty)
        metadata.authors = [Author(id: "writer", name: "Journalist", bio: nil, imageURL: nil, position: "", photoURL: "")]
        // Re-activation joins/returns the current actual author-triggered work.
        await model.activate()?.value
        XCTAssertEqual(model.page.articles.map(\.id), ["story"])
    }

    @MainActor
    func testObsoleteQueryCannotPublishEvenWhenProcessorIgnoresCancellation() async throws {
        let processor = ControlledSearchProcessor()
        let model = ArticleSearchResultsModel(processor: processor, debounceNanoseconds: 0)
        model.updateContent(articles: [article("old"), article("new")], authors: [])
        model.updateQuery("old")
        let obsolete = try XCTUnwrap(model.activate())
        await processor.waitForRequest("old")
        let latest = try XCTUnwrap(model.updateQuery("new"))
        await processor.waitForRequest("new")
        await processor.complete("new", articles: [article("new")])
        await latest.value
        XCTAssertEqual(model.page.articles.map(\.id), ["new"])
        await processor.complete("old", articles: [article("old")])
        await obsolete.value
        XCTAssertEqual(model.page.articles.map(\.id), ["new"])
        XCTAssertFalse(model.isUpdating)
    }

    @MainActor
    func testReturningToUnchangedArticleListPreservesLoadedRowsAfterViewLifecycle() async {
        let articles = (0..<45).map { article("article-\($0)") }
        let changes = PassthroughSubject<[Article], Never>()
        let authors = CurrentValueSubject<[Author], Never>([])
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.observeContent(articles: changes.eraseToAnyPublisher(), authors: authors.eraseToAnyPublisher())
        model.updateContent(articles: articles, authors: [])
        model.updateQuery("article")
        await model.activate()?.value
        model.loadMore()
        let visibleBeforeOpeningArticle = model.page.articles.map(\.id)
        XCTAssertEqual(visibleBeforeOpeningArticle.count, 40)
        XCTAssertTrue(model.page.hasMore)

        // The actual SearchView_Enhanced hides while an article is open, then
        // resubscribes and supplies its current feed on returning to the list.
        model.deactivate()
        model.observeContent(articles: changes.eraseToAnyPublisher(), authors: authors.eraseToAnyPublisher())
        model.updateContent(articles: articles, authors: [])
        await model.activate()?.value

        XCTAssertEqual(model.page.articles.map(\.id), visibleBeforeOpeningArticle)
        XCTAssertEqual(model.page.articles.count, 40)
        XCTAssertEqual(model.page.totalCount, 45)
        XCTAssertTrue(model.page.hasMore)
    }

    @MainActor
    func testSameIDArticleEditsAreVisibleAfterReturningToTheList() async throws {
        func version(name: String = "Original", content: String = "Original body",
                     rating: Int = 2, revision: String = "revision-1") -> Article {
            Article(id: "same-id", name: name, slug: "story", content: content, intro: "Intro",
                    stjerne: rating, topicID: "music", contentRevision: revision)
        }
        let original = version()
        let edits = [version(name: "Corrected title"), version(content: "Corrected body"),
                     version(rating: 6), version(revision: "revision-2")]
        for edited in edits {
            let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
            model.updateContent(articles: [original], authors: [])
            await model.activate()?.value
            model.deactivate()
            model.updateContent(articles: [edited], authors: [])
            await model.activate()?.value

            let shown = try XCTUnwrap(model.page.articles.first)
            XCTAssertEqual(shown.id, original.id)
            XCTAssertEqual(shown.name, edited.name)
            XCTAssertEqual(shown.content, edited.content)
            XCTAssertEqual(shown.stjerne, edited.stjerne)
            XCTAssertEqual(shown.bodyRevision, edited.bodyRevision)
        }
    }

    @MainActor
    func testSameIDAuthorRenameUpdatesReturnedResultsAndSearch() async throws {
        let story = article("story", authorID: "writer")
        let oldAuthor = Author(id: "writer", name: "Maja", bio: nil, imageURL: nil, position: "", photoURL: "")
        let newAuthor = Author(id: "writer", name: "Nora", bio: nil, imageURL: nil, position: "", photoURL: "")
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.updateContent(articles: [story], authors: [oldAuthor])
        model.updateQuery("maja")
        await model.activate()?.value
        XCTAssertEqual(model.page.articles.map(\.id), ["story"])

        model.deactivate()
        model.updateContent(articles: [story], authors: [newAuthor])
        await model.activate()?.value
        XCTAssertTrue(model.page.articles.isEmpty)
        await model.updateQuery("nora")?.value
        XCTAssertEqual(model.page.articles.map(\.id), ["story"])
        XCTAssertEqual(model.page.articles.first?.author?.name, "Nora")
    }

    @MainActor
    func testChangedFeedOnReturnRemovesWithdrawnRows() async {
        let original = (0..<45).map { article("article-\($0)") }
        let retained = Array(original.prefix(3))
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.updateContent(articles: original, authors: [])
        await model.activate()?.value
        model.loadMore()
        XCTAssertEqual(model.page.articles.count, 40)

        model.deactivate()
        model.updateContent(articles: retained, authors: [])
        await model.activate()?.value
        XCTAssertEqual(Set(model.page.articles.map(\.id)), Set(retained.map(\.id)))
        XCTAssertEqual(model.page.totalCount, 3)
        XCTAssertFalse(model.page.hasMore)
    }

    @MainActor
    func testRemovedFeedCannotReturnFromOldSearchAfterReactivation() async throws {
        let processor = ControlledSearchProcessor()
        let model = ArticleSearchResultsModel(processor: processor, debounceNanoseconds: 0)
        model.updateContent(articles: [article("old")], authors: [])
        model.updateQuery("old")
        let obsolete = try XCTUnwrap(model.activate())
        await processor.waitForRequest("old")

        model.deactivate()
        model.updateContent(articles: [], authors: [])
        model.updateQuery("withdrawn")
        let current = try XCTUnwrap(model.activate())
        await processor.waitForRequest("withdrawn")
        await processor.complete("withdrawn", articles: [])
        await current.value
        XCTAssertTrue(model.page.articles.isEmpty)

        await processor.complete("old", articles: [article("old")])
        await obsolete.value
        XCTAssertTrue(model.page.articles.isEmpty)
        XCTAssertEqual(model.page.totalCount, 0)
        XCTAssertFalse(model.isUpdating)
    }

    @MainActor
    func testChangedSortStillResetsExpandedPaginationForSameContent() async {
        let articles = (0..<45).map { article("article-\($0)") }
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.updateContent(articles: articles, authors: [])
        await model.activate()?.value
        model.loadMore()
        XCTAssertEqual(model.page.articles.count, 40)

        await model.updateSort(.titleZA)?.value
        XCTAssertEqual(model.page.articles.count, 20)
        XCTAssertEqual(model.page.articles.map(\.id), Array(articles.map(\.id).sorted(by: >).prefix(20)))
        XCTAssertEqual(model.page.totalCount, 45)
        XCTAssertTrue(model.page.hasMore)
    }

    @MainActor
    func testShrinkingQueryResetsPaginationWithoutDelayedSlices() async throws {
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.updateContent(articles: (0..<45).map { article("article-\($0)") }, authors: [])
        await model.activate()?.value
        XCTAssertEqual(model.page.articles.count, 20)
        model.loadMore()
        XCTAssertEqual(model.page.articles.count, 40)
        await model.updateQuery("article-44")?.value
        model.loadMore()
        XCTAssertEqual(model.page.articles.map(\.id), ["article-44"])
        XCTAssertEqual(model.page.totalCount, 1)
        XCTAssertFalse(model.page.hasMore)
    }

    @MainActor
    func testEmptyFeedThenArticlesAndAuthorsRefreshTheSameQuery() async throws {
        let model = ArticleSearchResultsModel(debounceNanoseconds: 0)
        model.updateQuery("maja")
        await model.activate()?.value
        XCTAssertTrue(model.page.articles.isEmpty)
        await model.updateContent(articles: [article("story", authorID: "writer")], authors: [])?.value
        XCTAssertTrue(model.page.articles.isEmpty)
        let author = Author(id: "writer", name: "Maja", bio: nil, imageURL: nil, position: "", photoURL: "")
        await model.updateContent(articles: [article("story", authorID: "writer")], authors: [author])?.value
        XCTAssertEqual(model.page.articles.map(\.id), ["story"])
    }

    @MainActor
    func testInactiveViewCannotReceiveLateResultsAndCanResume() async throws {
        let processor = ControlledSearchProcessor()
        let model = ArticleSearchResultsModel(processor: processor, debounceNanoseconds: 0)
        let hidden = try XCTUnwrap(model.activate())
        await processor.waitForRequest("")
        model.deactivate()
        await processor.complete("", articles: [article("hidden")])
        await hidden.value
        XCTAssertTrue(model.page.articles.isEmpty)
        let visible = try XCTUnwrap(model.activate())
        await processor.waitForRequest("")
        await processor.complete("", articles: [article("visible")])
        await visible.value
        XCTAssertEqual(model.page.articles.map(\.id), ["visible"])
    }
}
