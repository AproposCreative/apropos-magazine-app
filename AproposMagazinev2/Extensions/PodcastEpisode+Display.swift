import Foundation

extension PodcastEpisode {
    static func matchingArticle(for episode: PodcastEpisode, in articles: [Article]) -> Article? {
        articles.first { article in
            if let articleId = episode.articleId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !articleId.isEmpty,
               article.id.caseInsensitiveCompare(articleId) == .orderedSame {
                return true
            }
            if let slug = episode.articleSlug?.trimmingCharacters(in: .whitespacesAndNewlines),
               !slug.isEmpty,
               let articleSlug = article.slug?.trimmingCharacters(in: .whitespacesAndNewlines),
               !articleSlug.isEmpty,
               articleSlug.caseInsensitiveCompare(slug) == .orderedSame {
                return true
            }
            return false
        }
    }

    func authorDisplayName(
        matchingArticle article: Article?,
        authorLookup: ((Article) -> Author?)?
    ) -> String? {
        if let article {
            if let lookup = authorLookup,
               let resolvedAuthor = lookup(article) {
                let resolved = resolvedAuthor.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !resolved.isEmpty {
                    return resolved
                }
            }
            if let embeddedAuthor = article.author {
                let embedded = embeddedAuthor.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !embedded.isEmpty {
                    return embedded
                }
            }
        }

        let hostLine = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        return hostLine.isEmpty ? nil : hostLine
    }

    func playerSubtitleLine(
        matchingArticle article: Article?,
        authorLookup: ((Article) -> Author?)?
    ) -> String {
        if let author = authorDisplayName(matchingArticle: article, authorLookup: authorLookup) {
            return author
        }

        if let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subtitle.isEmpty,
           subtitle.caseInsensitiveCompare("Lyt til artiklen") != .orderedSame {
            return subtitle
        }

        return "Apropos Magazine"
    }
}
