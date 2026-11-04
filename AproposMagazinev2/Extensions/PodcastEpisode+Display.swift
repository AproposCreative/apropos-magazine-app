import Foundation

extension PodcastEpisode {
    static func matchingArticle(for episode: PodcastEpisode, in articles: [Article]) -> Article? {
        let valid = articles.filter(\.hasValidContentIdentity)
        if let rawID = episode.articleId {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty {
                let matches = valid.filter { article in
                    article.contentLanguage == .english ? article.id == rawID
                        : article.id.caseInsensitiveCompare(id) == .orderedSame
                }
                // An explicit mismatch can never borrow another locale's slug.
                return matches.count == 1 ? matches[0] : nil
            }
        }
        guard let slug = episode.articleSlug?.trimmingCharacters(in: .whitespacesAndNewlines),
              !slug.isEmpty else { return nil }
        let matches = valid.filter { article in
            guard article.contentLanguage == .danish,
                  let articleSlug = article.slug?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !articleSlug.isEmpty else { return false }
            return articleSlug.caseInsensitiveCompare(slug) == .orderedSame
        }
        return matches.count == 1 ? matches[0] : nil
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
