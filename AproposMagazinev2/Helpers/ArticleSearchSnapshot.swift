import Foundation

enum ArticleSortOption: String, CaseIterable, Identifiable {
    case newest = "Nyeste"
    case oldest = "Ældste"
    case titleAZ = "Titel A-Å"
    case titleZA = "Titel Å-A"
    case category = "Kategori"

    var id: String { rawValue }
}

/// Immutable search output. Pagination only reveals a prefix of this result;
/// it never re-filters, re-sorts, or keeps an index into an older result.
struct ArticleSearchSnapshot {
    let articles: [Article]

    static let empty = ArticleSearchSnapshot(articles: [])

    func page(visibleCount: Int) -> ArticleSearchPage {
        let count = min(max(0, visibleCount), articles.count)
        return ArticleSearchPage(
            articles: Array(articles.prefix(count)),
            totalCount: articles.count,
            hasMore: count < articles.count
        )
    }
}

struct ArticleSearchPage {
    let articles: [Article]
    let totalCount: Int
    let hasMore: Bool

    static let empty = ArticleSearchPage(articles: [], totalCount: 0, hasMore: false)
}

/// Prepared keys are shared by every query/sort for a content revision. Author
/// metadata and body-only changes reuse dates when their source fields agree.
struct ArticleSearchIndex {
    private struct DateSignature: Equatable {
        let createdOn: String?
        let editorialDate: String?
    }

    private struct DateKey {
        let signature: DateSignature
        let value: Date
    }

    private struct Entry {
        let article: Article
        let date: Date
        let title: String
        let category: String
        let searchTitle: String
        let searchIntro: String
        let searchAuthor: String
    }

    private let entries: [Entry]
    private let dateKeys: [String: DateKey]

    init(
        articles: [Article],
        authors: [Author],
        reusing previous: ArticleSearchIndex? = nil,
        dateProvider: (Article) -> Date = { $0.feedSortDate }
    ) throws {
        let authorByID = Dictionary(authors.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var prepared: [Entry] = []
        var dates: [String: DateKey] = [:]
        prepared.reserveCapacity(articles.count)
        dates.reserveCapacity(articles.count)

        for article in articles {
            try Task.checkCancellation()
            // A corrupt/duplicated input must not produce duplicate SwiftUI IDs.
            guard dates[article.id] == nil else { continue }
            let signature = DateSignature(createdOn: article.createdOn, editorialDate: article.date)
            let date: Date
            if let cached = previous?.dateKeys[article.id], cached.signature == signature {
                date = cached.value
            } else {
                date = dateProvider(article)
            }
            dates[article.id] = DateKey(signature: signature, value: date)

            var displayArticle = article
            if let authorID = article.authorID, let author = authorByID[authorID] {
                displayArticle.author = author
            }
            prepared.append(Entry(
                article: displayArticle,
                date: date,
                title: article.name ?? "",
                category: article.topicID ?? "",
                searchTitle: (article.name ?? "").lowercased(),
                searchIntro: (article.intro ?? "").lowercased(),
                searchAuthor: (displayArticle.author?.name ?? "").lowercased()
            ))
        }
        self.entries = prepared
        self.dateKeys = dates
    }

    func snapshot(query: String, sort: ArticleSortOption) throws -> ArticleSearchSnapshot {
        let query = query.lowercased()
        var matches: [Entry] = []
        matches.reserveCapacity(entries.count)
        for entry in entries {
            try Task.checkCancellation()
            if query.isEmpty || entry.searchTitle.contains(query)
                || entry.searchIntro.contains(query) || entry.searchAuthor.contains(query) {
                matches.append(entry)
            }
        }
        matches.sort { lhs, rhs in
            switch sort {
            case .newest where lhs.date != rhs.date: return lhs.date > rhs.date
            case .oldest where lhs.date != rhs.date: return lhs.date < rhs.date
            case .titleAZ where lhs.title != rhs.title: return lhs.title < rhs.title
            case .titleZA where lhs.title != rhs.title: return lhs.title > rhs.title
            case .category where lhs.category != rhs.category: return lhs.category < rhs.category
            default: return lhs.article.id < rhs.article.id
            }
        }
        try Task.checkCancellation()
        return ArticleSearchSnapshot(articles: matches.map(\.article))
    }
}

protocol ArticleSearchProcessing: Sendable {
    func snapshot(
        articles: [Article], authors: [Author], revision: UInt64,
        query: String, sort: ArticleSortOption
    ) async throws -> ArticleSearchSnapshot
}

/// The actor owns preparation, date parsing and query sorting, away from the UI.
actor ArticleSearchWorker: ArticleSearchProcessing {
    private var index: ArticleSearchIndex?
    private var preparedRevision: UInt64?

    func snapshot(
        articles: [Article], authors: [Author], revision: UInt64,
        query: String, sort: ArticleSortOption
    ) throws -> ArticleSearchSnapshot {
        try Task.checkCancellation()
        if preparedRevision != revision {
            let prepared = try ArticleSearchIndex(articles: articles, authors: authors, reusing: index)
            try Task.checkCancellation()
            index = prepared
            preparedRevision = revision
        }
        return try index?.snapshot(query: query, sort: sort) ?? .empty
    }
}
