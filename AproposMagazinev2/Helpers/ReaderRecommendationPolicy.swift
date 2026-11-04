import Foundation

enum ReaderRecommendationPolicy {
    private struct Ranked {
        let index: Int
        let score: Int
        let article: Article
        let reason: String
    }
    static func recommendations(
        articles: [Article], favorites: [Article], interestTopicIDs: [String],
        readArticleIDs: Set<String>, limit: Int = 10
    ) -> [(Article, String)] {
        let interests = Set(interestTopicIDs)
        let favoriteTopics = Set(favorites.flatMap { ($0.topicsIDs ?? []) + [$0.topicID].compactMap { $0 } })
        let favoriteAuthors = Set(favorites.compactMap(\.authorID))
        var seen = Set<String>()
        let newest = Article.sortedByCreatedNewestFirst(articles.filter {
            $0.isPubliclyPublished && !$0.id.isEmpty && !readArticleIDs.contains($0.id) && seen.insert($0.id).inserted
        })
        var ranked: [Ranked] = []
        for (index, article) in newest.enumerated() {
            let topics = Set((article.topicsIDs ?? []) + [article.topicID].compactMap { $0 })
            let interest = !topics.intersection(interests).isEmpty
            let favorite = !topics.intersection(favoriteTopics).isEmpty
            let author = article.authorID.map { favoriteAuthors.contains($0) } ?? false
            let score = (interest ? 6 : 0) + (favorite ? 4 : 0) + (author ? 2 : 0)
            let reason: String
            if interest { reason = "Matcher dine valgte interesser" }
            else if favorite { reason = "Matcher emner fra dine gemte artikler" }
            else if author { reason = "Fra en forfatter i dine gemte artikler" }
            else { reason = "Nyt fra Apropos Magazine" }
            ranked.append(Ranked(index: index, score: score, article: article, reason: reason))
        }
        ranked.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        var selected: [(Article, String)] = []
        var deferred: [(Article, String)] = []
        var perTopic: [String: Int] = [:]
        for entry in ranked {
            let topic = entry.article.topicID ?? ""
            if !topic.isEmpty, perTopic[topic, default: 0] >= 3 {
                deferred.append((entry.article, entry.reason))
            } else {
                selected.append((entry.article, entry.reason))
                perTopic[topic, default: 0] += 1
            }
        }
        return Array((selected + deferred).prefix(max(0, limit)))
    }
}
