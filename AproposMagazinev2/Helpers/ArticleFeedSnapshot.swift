import Foundation

enum ArticleFeedSnapshot {
    struct Update {
        let articles: [Article]
        /// Only decoded source rows, never revisions borrowed from retained UI/cache.
        let sourceArticles: [Article]
        let cacheTimestamp: Date?
        let failures: [ArticleContentLanguage: Error]
        let hasAcceptedNamespace: Bool
        let didChange: Bool
        let freshLanguages: Set<ArticleContentLanguage>
        let baselineIsCurrent: @MainActor () -> Bool

        static func complete(_ articles: [Article]) -> Update {
            Update(articles: articles, sourceArticles: articles, cacheTimestamp: Date(), failures: [:],
                hasAcceptedNamespace: true, didChange: !articles.isEmpty,
                freshLanguages: Set(ArticleContentLanguage.allCases), baselineIsCurrent: { true })
        }
        func displayError(for language: ArticleContentLanguage) -> Error? {
            failures[language] == nil ? nil : ArticleMirrorCatalog.LanguageFailure(language: language)
        }
    }

    /// Shared cold-baseline admission, also used by the platform cache owner.
    /// Storage/clock remain injected; the actual decoder owns the CPU lane.
    @MainActor
    static func prepare(_ update: ArticleMirrorCatalog.Update,
        original: ArticleCacheHydrationCoordinator.Capture,
        load: (ArticleCacheHydrationCoordinator.Capture, @escaping @MainActor () -> Bool) async -> ArticleCacheHydrationCoordinator.Outcome,
        isCurrent: @escaping @MainActor (ArticleCacheHydrationCoordinator.Capture) -> Bool,
        current: @escaping @MainActor () -> [Article], now: @MainActor () -> Date,
        stillPermitted: @escaping @MainActor () -> Bool) async throws -> Update {
        guard stillPermitted(), !Task.isCancelled else { throw CancellationError() }
        guard isCurrent(original) else { throw CancellationError() }
        let outcome = await load(original, stillPermitted)
        guard isCurrent(original), stillPermitted(), isCurrent(original), !Task.isCancelled else { throw CancellationError() }
        let baseline: ArticleCacheHydrationCoordinator.Prepared?
        switch outcome {
        case .stale: throw CancellationError()
        case .ready(let value): baseline = value
        case .missing, .rejected: baseline = nil
        }
        let currentArticles = current(), date = now()
        guard stillPermitted(), isCurrent(original) else { throw CancellationError() }
        return resolving(update, baseline: baseline, current: currentArticles, now: date,
                         baselineIsCurrent: { isCurrent(original) })
    }

    /// A single policy for UI and OS background refresh. Fresh coverage may
    /// replace only its own namespace; cached/pending replies are additive.
    /// Retained rows never borrow a newer timestamp from a healthy namespace.
    static func resolving(_ update: ArticleMirrorCatalog.Update,
                          baseline: ArticleCacheHydrationCoordinator.Prepared?, current: [Article],
                          now: Date, baselineIsCurrent: @escaping @MainActor () -> Bool) -> Update {
        let cached = baseline?.articles ?? []
        var priorByID = Dictionary(merging(cached, retainingDetailsFrom: current)
            .filter(\.hasValidContentIdentity).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for article in current where article.isPubliclyPublished && article.hasValidContentIdentity {
            if let previous = priorByID[article.id], previous.bodyRevision != article.bodyRevision,
               let previousDate = previous.revisionDate, let currentDate = article.revisionDate,
               currentDate < previousDate { continue }
            // Equal/unknown dates do not give old disk bytes authority over an
            // already accepted detail revision (including its matching body).
            priorByID[article.id] = article
        }
        let prior = Article.sortedByCreatedNewestFirst(Array(priorByID.values))
        let fresh = update.freshLanguages
        let retained = prior.filter { article in
            guard let language = article.contentLanguage else { return false }
            return !fresh.contains(language)
        }
        var byID = Dictionary(retained.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for namespace in update.namespaces {
            for article in merging(namespace.articles, retainingDetailsFrom: prior) {
                if namespace.isFresh || byID[article.id] == nil { byID[article.id] = article }
            }
        }
        let result = Article.sortedByCreatedNewestFirst(Array(byID.values))
        let retainsUnrefreshed = result.contains { article in
            article.contentLanguage.map { !fresh.contains($0) } ?? true
        }
        // An unpersisted detail row has no feed-cache acquisition date. Preserve
        // it in memory, but do not invent a new age for it on disk.
        let hasUndatedRetained = retained.contains { item in !cached.contains(where: { $0.id == item.id }) }
        let date: Date? = !retainsUnrefreshed ? now
            : hasUndatedRetained ? nil : baseline.map { min($0.timestamp, now) }
        return Update(articles: result, sourceArticles: update.articles, cacheTimestamp: date, failures: update.failures,
            hasAcceptedNamespace: update.namespaces.contains { $0.isFresh || !$0.articles.isEmpty }, didChange: result != prior,
            freshLanguages: fresh,
            baselineIsCurrent: baselineIsCurrent)
    }

    /// Merge at commit time, after any detail request that finished while the
    /// feed was loading. Detail bodies belong to a specific CMS revision.
    static func merging(_ incoming: [Article], retainingDetailsFrom current: [Article]) -> [Article] {
        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let merged = incoming.filter(\.isPubliclyPublished).map { article in
            var merged = article.strippingBodyContent()
            guard let previous = currentByID[article.id] else { return merged }
            if article.bodyRevision != previous.bodyRevision,
               let incomingDate = article.revisionDate,
               let previousDate = previous.revisionDate,
               incomingDate < previousDate {
                // A cache-backed feed can arrive after a newer detail response.
                // Keep that entire revision, rather than mixing old metadata
                // with a newer body or sending the reader back to an older one.
                return previous
            }
            if article.bodyRevision == previous.bodyRevision,
               article.createdOn == previous.createdOn,
               let body = previous.content, !body.isEmpty {
                merged = merged.replacingBodyContent(body)
            }
            if merged.author == nil, article.authorID == previous.authorID {
                merged.author = previous.author
            }
            return merged
        }
        return Article.sortedByCreatedNewestFirst(merged)
    }


}
