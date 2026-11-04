import Foundation

/// Actor-owned worker. Construction neither starts a task nor touches services.
actor HomeFeedWorker {
    private var builder: HomeFeedBuilder?
    func prepare(_ input: HomeFeedInput) -> HomeFeedSnapshot {
        if builder == nil { builder = HomeFeedBuilder() }
        return builder!.build(input)
    }
}

/// Keep one instance on one executor; mutable formatters and caches are never shared.
final class HomeFeedBuilder {
    private struct LayoutArticle: Equatable {
        let id: String; let created: String?; let date: String?
    }
    private struct Named: Equatable { let id: String; let name: String }
    private struct LayoutKey: Equatable { let articles: [LayoutArticle] }
    private struct MetadataKey: Equatable {
        let id: String; let topic: String?; let topics: [String]; let section: String?; let author: String?
        let mobile: URL?; let thumb: URL?; let cover: URL?; let fallback: URL?
    }
    private struct MatchArticle: Equatable {
        let id: String; let name: String?; let slug: String?; let mobile: URL?; let thumb: URL?; let cover: URL?
    }
    private let parser = ArticlePresentationDateParser()
    private var layoutKey: LayoutKey?
    private var createdIDs: [String] = [], feedIDs: [String] = []
    private var dates: [String: ArticlePresentationDateParser.Keys] = [:]
    private var metadataKeys: [MetadataKey] = []
    private var metadataSources: [[Named]] = []
    private var metadata: [String: HomeArticleMetadata] = [:]
    private var htmlImages: [String: (content: String?, url: URL?)] = [:]
    private var matchArticles: [MatchArticle] = []
    private var matchEpisodes: [PodcastEpisode] = []
    private var matchOrder: [String] = []
    private var podcastChoices: [(String, PodcastEpisode)] = []
    private var fallbackChoices: [PodcastEpisode: String] = [:]
    private(set) var metrics = HomePreparationMetrics()

    func build(_ input: HomeFeedInput) -> HomeFeedSnapshot {
        metrics.builds += 1
        let articles = Self.acceptedArticles(input.articles)
        let byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        let topics = Self.firstNamed(input.topics.map { Named(id: $0.id, name: $0.name) })
        let sections = Self.firstNamed(input.sections.map { Named(id: $0.id, name: $0.name) })
        let key = LayoutKey(articles: articles.map { LayoutArticle(id: $0.id, created: $0.createdOn, date: $0.date) })
        if layoutKey != key {
            layoutKey = key
            dates = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, parser.dates(for: $0)) })
            createdIDs = parser.sortedByCreatedNewestFirst(articles).map(\.id)
            // Stable input order remains the tie-break for equal feed dates, as in the old selector.
            feedIDs = articles.sorted { dates[$0.id]!.feed > dates[$1.id]!.feed }.map(\.id)
            metrics.archiveSorts += 2
        }
        let heroIDs = Array(createdIDs.filter { (dates[$0]!.created ?? dates[$0]!.feed) <= input.now }.prefix(5))
        let heroSet = Set(heroIDs)
        let reviewID = topics.first { $0.name == "Anmeldelser" }?.id
        let reviewInput = topics.isEmpty ? [] : articles.filter { $0.topicID == reviewID && !heroSet.contains($0.id) }
        let used = heroSet.union(reviewInput.prefix(10).map(\.id))
        let reviewSet = Set(reviewInput.map(\.id))
        let reviews = createdIDs.filter { reviewSet.contains($0) }
        let popular = createdIDs.filter { !used.contains($0) }
        let recent = feedIDs.filter { dates[$0]!.feed <= input.now }
        let section = Array(recent.prefix(10)).filter { !used.contains($0) }
        let allSection = recent.filter { !used.contains($0) }
        let current: ([String]) -> [Article] = { $0.compactMap { byID[$0] } }
        var reasons: [String: String] = [:], recommendationIDs: [String] = []
        for value in input.recommendations where byID[value.articleID] != nil && reasons[value.articleID] == nil {
            reasons[value.articleID] = value.reason; recommendationIDs.append(value.articleID)
        }
        if recommendationIDs.isEmpty {
            recommendationIDs = section.count > 1 ? section : Array((allSection.isEmpty ? articles.map(\.id) : allSection).prefix(6))
        }
        var rails = [HomeRail(kind: .recommended, visible: current(recommendationIDs), all: current(allSection), reasonsByID: reasons),
                     HomeRail(kind: .reviews, visible: current(Array(reviews.prefix(10))), all: current(reviews)),
                     HomeRail(kind: .popular, visible: current(Array(popular.prefix(6))), all: current(popular))]
        let topicLookup = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.name) })
        let sectionForArticle: (Article) -> Named? = { article in
            for id in [article.topicID].compactMap({ $0 }) + (article.topicsIDs ?? []) {
                if let name = topicLookup[id], let value = Self.section(for: name, sections: sections) { return value }
            }
            return nil
        }
        let grouped = Dictionary(grouping: articles, by: { sectionForArticle($0)?.id ?? "" })
        for (kind, name) in [(HomeRail.Kind.music, "musik"), (.culture, "kultur"), (.seriesFilm, "film")] {
            let target = sections.first { name == "film" ? ($0.name.lowercased().contains("serier") || $0.name.lowercased().contains("film")) : $0.name.lowercased().contains(name) }
            let group = Set((target.flatMap { grouped[$0.id] } ?? []).map(\.id))
            let all = createdIDs.filter { group.contains($0) }
            rails.append(HomeRail(kind: kind, visible: current(Array(all.filter { !used.contains($0) }.prefix(6))), all: current(all)))
        }
        let authors = input.authors.map { Named(id: $0.id, name: $0.name) }
        let keys = articles.map { article in MetadataKey(id: article.id, topic: article.topicID, topics: article.topicsIDs ?? [],
            section: article.sectionID, author: article.authorID, mobile: article.mobileImageURL, thumb: article.thumbURL,
            cover: article.coverURL, fallback: fallbackImage(article)) }
        if metadataKeys != keys || metadataSources != [topics, sections, authors] {
            metadataKeys = keys; metadataSources = [topics, sections, authors]
            var authorLookup: [String: String] = [:]
            for author in authors {
                for value in [author.id, author.name] {
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if authorLookup[normalized] == nil { authorLookup[normalized] = author.name }
                }
            }
            let sectionLookup = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.name) })
            metadata = Dictionary(uniqueKeysWithValues: zip(articles, keys).map { article, key in
                var categories: [String] = [], seen = Set<String>()
                for id in [article.topicID].compactMap({ $0 }) + (article.topicsIDs ?? []) {
                    if let name = topicLookup[id], seen.insert(name).inserted { categories.append(name) }
                }
                if categories.isEmpty { categories = ["Generelt"] }
                let direct = article.sectionID.flatMap { $0.isEmpty ? nil : sectionLookup[$0] }
                let sectionName = direct ?? sectionForArticle(article)?.name
                let authorName = article.authorID.flatMap { authorLookup[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] }
                var seenURLs = Set<String>()
                let images = [key.thumb, key.cover, key.mobile, key.fallback].compactMap { $0 }.filter { seenURLs.insert($0.absoluteString).inserted }
                metrics.metadataBuilds += 1
                return (article.id, HomeArticleMetadata(categories: categories, sectionName: sectionName,
                    heroTag: sectionName.flatMap { $0.isEmpty ? nil : $0 } ?? categories.prefix(2).joined(separator: " | "),
                    authorName: authorName, podcastByline: authorName ?? "Apropos Magazine", heroImageCandidates: images,
                    cardImageURL: key.mobile ?? key.thumb ?? key.cover, listImageURL: key.fallback))
            })
            htmlImages = htmlImages.filter { byID[$0.key] != nil }
        }
        let matches = articles.map { MatchArticle(id: $0.id, name: $0.name, slug: $0.slug, mobile: $0.mobileImageURL, thumb: $0.thumbURL, cover: $0.coverURL) }
        if matches != matchArticles || input.episodes != matchEpisodes || feedIDs != matchOrder {
            matchArticles = matches; matchEpisodes = input.episodes; matchOrder = feedIDs
            var index = HomePodcastIndex(episodes: input.episodes)
            podcastChoices = []
            for id in feedIDs {
                guard podcastChoices.count < 100 else { break }
                if let article = byID[id], let episode = index.bestMatch(for: article) { podcastChoices.append((id, episode)) }
            }
            metrics.podcastCandidateChecks += index.candidateChecks
            var idIndex: [String: (Int, String)] = [:], slugIndex: [String: (Int, String)] = [:]
            for (offset, article) in articles.enumerated() {
                if let id = HomePodcastIndex.resumeIdentity(article.id, trimming: false), idIndex[id] == nil { idIndex[id] = (offset, article.id) }
                if let slug = HomePodcastIndex.resumeIdentity(article.slug), slugIndex[slug] == nil { slugIndex[slug] = (offset, article.id) }
            }
            fallbackChoices = [:]
            for episode in input.episodes where episode.hasPlayableAudioURL {
                let id = HomePodcastIndex.resumeIdentity(episode.articleId).flatMap { idIndex[$0] }
                let slug = HomePodcastIndex.resumeIdentity(episode.articleSlug).flatMap { slugIndex[$0] }
                let choice = [id, slug].compactMap { $0 }.min { $0.0 < $1.0 }
                if let choice { fallbackChoices[episode] = choice.1 }
            }
        }
        let pairs = podcastChoices.compactMap { id, episode -> PodcastArticlePair? in
            byID[id].map { PodcastArticlePair(article: $0, episode: HomePodcastIndex.enriched(episode, with: $0)) }
        }
        let resume = HomeResumeIndex(playableEpisodesByID: Dictionary(grouping: input.episodes.filter(\.hasPlayableAudioURL), by: \.id),
            articlesByID: byID, fallbackArticleByEpisode: fallbackChoices.compactMapValues { byID[$0] })
        let next = dates.values.flatMap { [$0.created ?? $0.feed, $0.feed] }.filter { $0 > input.now }.min()
        metrics.dateParses = parser.dateParses
        return HomeFeedSnapshot(authority: input.authority, hero: current(heroIDs), rails: rails, metadataByID: metadata,
            podcastPairs: pairs, resumeIndex: resume, nextBoundary: next, metrics: metrics)
    }
    static func acceptedArticles(_ articles: [Article]) -> [Article] {
        var seen = Set<String>()
        return articles.filter { $0.isPubliclyPublished && CMSMirrorDocumentPolicy.isSafeDocumentID($0.id) && seen.insert($0.id).inserted }
    }
    private static func firstNamed(_ values: [Named]) -> [Named] {
        var seen = Set<String>(); return values.filter { seen.insert($0.id).inserted }
    }
    private static func section(for name: String, sections: [Named]) -> Named? {
        let name = name.lowercased()
        if name.contains("serier") || name.contains("tv") || name.contains("film") {
            return sections.first { $0.name.lowercased().contains("serier") || $0.name.lowercased().contains("film") }
        }
        if name.contains("musik") || name.contains("koncert") { return sections.first { $0.name.lowercased().contains("musik") } }
        if name.contains("kultur") || name.contains("mening") { return sections.first { $0.name.lowercased().contains("kultur") } }
        return nil
    }
    private func fallbackImage(_ article: Article) -> URL? {
        if let direct = article.mobileImageURL ?? article.thumbURL ?? article.coverURL { return direct }
        if let cached = htmlImages[article.id], cached.content == article.content { return cached.url }
        var value = article
        let raw = value.thumbnailURL
        let url = raw.isEmpty ? nil : (URL(string: raw) ?? raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:)))
        htmlImages[article.id] = (article.content, url)
        return url
    }
}

/// Indexes the binding tiers without changing manifest tie order or human preference.
struct HomePodcastIndex {
    private var byID: [String: [PodcastEpisode]] = [:], bySlug: [String: [PodcastEpisode]] = [:], byTitle: [String: [PodcastEpisode]] = [:]
    private var loose: [(String, PodcastEpisode)] = []
    private(set) var candidateChecks = 0
    init(episodes: [PodcastEpisode]) {
        for episode in episodes {
            if let id = episode.articleId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { byID[id, default: []].append(episode) }
            else if let slug = Self.normalized(episode.articleSlug) { bySlug[slug, default: []].append(episode) }
            else if let title = Self.normalized(episode.title) { byTitle[title, default: []].append(episode); loose.append((title, episode)) }
        }
    }
    mutating func bestMatch(for article: Article, requirePlayableAudio: Bool = false) -> PodcastEpisode? {
        guard article.hasValidContentIdentity else { return nil }
        func preferred(_ values: [PodcastEpisode]) -> PodcastEpisode? {
            let permitted = requirePlayableAudio ? values.filter(\.hasPlayableAudioURL) : values
            return permitted.first { !$0.isAINarration } ?? permitted.first
        }
        let indexed = byID[article.id] ?? []
        let ids = article.contentLanguage == .english
            ? indexed.filter { $0.articleId == article.id } : indexed
        candidateChecks += ids.count
        if let value = preferred(ids) { return value }
        // A Danish legacy slug/title does not establish an English recording.
        guard article.contentLanguage != .english else { return nil }
        if let slug = Self.normalized(article.slug) {
            let values = bySlug[slug] ?? []; candidateChecks += values.count
            if let value = preferred(values) { return value }
        }
        guard let title = Self.normalized(article.name) else { return nil }
        let exact = byTitle[title] ?? []; candidateChecks += exact.count
        if let value = preferred(exact) { return value }
        var values: [PodcastEpisode] = []
        for (candidate, episode) in loose {
            candidateChecks += 1
            if title.contains(candidate) || candidate.contains(title) { values.append(episode) }
        }
        return preferred(values)
    }
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }; let result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return result.isEmpty ? nil : result
    }
    static func resumeIdentity(_ value: String?, trimming: Bool = true) -> String? {
        guard let value else { return nil }
        let raw = trimming ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value
        guard !raw.isEmpty else { return nil }
        return raw.folding(options: .caseInsensitive, locale: nil)
    }
    static func enriched(_ episode: PodcastEpisode, with article: Article) -> PodcastEpisode {
        PodcastEpisode(id: episode.id, articleId: article.id, articleSlug: episode.articleSlug, title: episode.title,
            subtitle: episode.subtitle, audioURL: episode.audioURL, productionSourceURL: episode.productionSourceURL,
            duration: episode.duration, artworkURL: episode.artworkURL ?? article.mobileImageURL ?? article.thumbURL ?? article.coverURL,
            hosts: episode.hosts, publishedDate: episode.publishedDate, isAINarration: episode.isAINarration,
            sourceContentRevision: episode.sourceContentRevision)
    }
}
