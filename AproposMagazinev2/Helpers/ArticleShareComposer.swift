import Foundation
import UIKit

enum ArticleShareComposer {
    static func richShareText(for article: Article, categories: [String], language: ArticleContentLanguage = .danish) -> String {
        var shareText = "📰 \(article.name ?? AppLocalization.string("Artikel", language: language))"

        if let subtitle = article.subtitle, !subtitle.isEmpty {
            shareText += "\n\n\(subtitle)"
        }

        if let intro = article.intro, !intro.isEmpty {
            let truncatedIntro = intro.count > 150 ? String(intro.prefix(150)) + "..." : intro
            shareText += "\n\n\(truncatedIntro)"
        }

        if let authorName = article.author?.name, !authorName.isEmpty {
            shareText += "\n\n👤 " + AppLocalization.string("Af:", language: language) + " " + authorName
        }

        if let stjerne = article.stjerne, stjerne > 0 {
            shareText += "\n\n⭐ \(stjerne)/6"
        }

        if !categories.isEmpty {
            shareText += "\n\n🏷️ \(categories.map { AppLocalization.taxonomy($0, language: language) }.joined(separator: ", "))"
        }

        if let location = article.location, !location.isEmpty {
            shareText += "\n\n📍 \(location)"
        }

        shareText += "\n\n📖 " + AppLocalization.string("Læs hele artiklen på Apropos Magazine", language: language)
        shareText += language == .english ? "\n\n#AproposMagazine #Culture #Music" : "\n\n#AproposMagazine #Kultur #Musik"

        return shareText
    }

    static func podcastClipShareText(
        episode: PodcastEpisode,
        article: Article?,
        timestamp: TimeInterval,
        language: ArticleContentLanguage = .danish
    ) -> String {
        let timeLabel = ShareLinkBuilder.formattedTimestamp(timestamp)
        var lines: [String] = ["🎧 \(episode.title)"]

        if let articleName = article?.name, !articleName.isEmpty {
            lines.append(AppLocalization.format("Fra: %@", language: language, arguments: [articleName]))
        }

        lines.append(AppLocalization.format("Hør fra %@", language: language, arguments: [timeLabel]))
        lines.append("")
        lines.append("Apropos Magazine")
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func shareItems(
        for article: Article,
        categories: [String],
        image: UIImage?,
        language: ArticleContentLanguage = .danish
    ) -> [Any] {
        var items: [Any] = [richShareText(for: article, categories: categories, language: language)]
        if let url = ShareLinkBuilder.articleURL(slug: article.slug, articleId: article.id) {
            items.append(url)
        }
        if let image {
            items.insert(image, at: 0)
        }
        return items
    }

    @MainActor
    static func podcastClipShareItems(
        episode: PodcastEpisode,
        article: Article?,
        timestamp: TimeInterval,
        artwork: UIImage? = nil,
        language: ArticleContentLanguage = .danish
    ) -> [Any] {
        let articleId = article?.id ?? episode.articleId ?? episode.id
        let slug = article?.slug ?? episode.articleSlug
        var items: [Any] = [
            podcastClipShareText(episode: episode, article: article, timestamp: timestamp, language: language)
        ]

        if let url = ShareLinkBuilder.podcastClipURL(
            slug: slug,
            articleId: articleId,
            timestampSeconds: ShareLinkBuilder.timestampSeconds(timestamp)
        ) {
            items.append(url)
        }

        if let artwork {
            items.insert(artwork, at: 0)
        }

        return items
    }
}
