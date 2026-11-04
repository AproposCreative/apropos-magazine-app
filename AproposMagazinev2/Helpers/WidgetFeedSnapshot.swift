import Foundation

/// The widget depends only on these small metadata values, never on article HTML.
/// A sorted feed can be reduced to five rows before comparison or preparation.
struct WidgetFeedSource: Equatable {
    struct Entry: Equatable {
        let widget: WidgetArticle
        let createdOn: String?
        let editorialDate: String?

        var sortArticle: Article {
            Article(
                id: widget.id, name: "", slug: "", content: "", intro: "", topicID: "",
                date: editorialDate, createdOn: createdOn
            )
        }
    }

    let entries: [Entry]
    let articlesAreSorted: Bool

    init(articles: [Article], topics: [Topic], articlesAreSorted: Bool = false) {
        self.articlesAreSorted = articlesAreSorted
        let topicNames = Dictionary(topics.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var entries: [Entry] = []
        var seen = Set<String>()
        for article in articles where article.isPubliclyPublished {
            guard !article.id.isEmpty, seen.insert(article.id).inserted else { continue }
            let topicIDs = [article.topicID].compactMap { $0 } + (article.topicsIDs ?? [])
            let topic = topicIDs.lazy.compactMap { topicNames[$0] }.first ?? ""
            entries.append(Entry(
                widget: WidgetArticle(
                    id: article.id,
                    name: article.name ?? "Artikel",
                    slug: article.slug ?? article.id,
                    thumbURL: (article.thumbURL ?? article.mobileImageURL ?? article.coverURL)?.absoluteString ?? "",
                    intro: article.intro ?? "",
                    date: article.lastPublished ?? article.createdOn ?? article.date ?? "",
                    stjerne: article.stjerne,
                    topic: topic
                ),
                createdOn: article.createdOn,
                editorialDate: article.date
            ))
            if articlesAreSorted, entries.count == 5 { break }
        }
        self.entries = entries
    }
}

struct WidgetFeedSnapshot {
    private struct DateKey {
        let createdOn: String?
        let editorialDate: String?
        let value: Date
    }

    let articles: [WidgetArticle]
    private let dateKeys: [String: DateKey]

    init(
        source: WidgetFeedSource,
        reusing previous: WidgetFeedSnapshot? = nil,
        dateProvider: (Article) -> Date = { $0.feedSortDate }
    ) throws {
        try Task.checkCancellation()
        if source.articlesAreSorted {
            articles = source.entries.map(\.widget)
            dateKeys = [:]
            return
        }

        var keys: [String: DateKey] = [:]
        for entry in source.entries {
            try Task.checkCancellation()
            let cached = previous?.dateKeys[entry.widget.id]
            let value: Date
            if let cached, cached.createdOn == entry.createdOn, cached.editorialDate == entry.editorialDate {
                value = cached.value
            } else {
                value = dateProvider(entry.sortArticle)
            }
            keys[entry.widget.id] = DateKey(createdOn: entry.createdOn, editorialDate: entry.editorialDate, value: value)
        }

        // Preserve the existing home/widget order, including its createdOn-first
        // comparison. Date parsing occurs once per changed date input, off-main.
        articles = source.entries.sorted { lhs, rhs in
            let leftCreated = lhs.createdOn ?? ""
            let rightCreated = rhs.createdOn ?? ""
            if !leftCreated.isEmpty, !rightCreated.isEmpty, leftCreated != rightCreated {
                return leftCreated > rightCreated
            }
            let leftDate = keys[lhs.widget.id]?.value ?? .distantPast
            let rightDate = keys[rhs.widget.id]?.value ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.widget.id > rhs.widget.id
        }.prefix(5).map(\.widget)
        dateKeys = keys
    }
}

actor WidgetFeedSnapshotWorker {
    private var previous: WidgetFeedSnapshot?

    func prepare(_ source: WidgetFeedSource) throws -> [WidgetArticle] {
        let snapshot = try WidgetFeedSnapshot(source: source, reusing: previous)
        previous = snapshot
        return snapshot.articles
    }
}
