import Foundation

/// The merge used by both single saves and an entire restored favorites snapshot.
/// No I/O, image downloads, Firebase or connectivity monitoring is performed here.
enum OfflineLibrarySnapshot {
    struct Update {
        let articles: [Article]
        let removedIDs: Set<String>
        let changedArticles: [Article]
    }

    static func merging(_ incoming: [Article], into existing: [Article], limit: Int = 50) -> Update {
        var result = existing
        for article in incoming where !article.id.isEmpty {
            let previous = result.first { $0.id == article.id }
            let resolved: Article
            if article.content?.isEmpty != false,
               let previous, let body = previous.content, !body.isEmpty,
               ArticleDetailContentPolicy.sameRevision(article, previous) {
                // A summary of the same revision must not erase an offline body.
                resolved = article.replacingBodyContent(body)
            } else {
                resolved = article
            }
            result.removeAll { $0.id == article.id }
            result.append(resolved)
        }
        result = Array(result.suffix(max(0, limit)))
        let retainedIDs = Set(result.map(\.id))
        var previousByID: [String: Article] = [:]
        for article in existing { previousByID[article.id] = article }
        return Update(
            articles: result,
            removedIDs: Set(existing.map(\.id)).subtracting(retainedIDs),
            changedArticles: result.filter { previousByID[$0.id] != $0 }
        )
    }
}
