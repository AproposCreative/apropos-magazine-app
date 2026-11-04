import Foundation

/// Independent accepted input revisions. Raw account identifiers never need to
/// enter this presentation key, worker diagnostics or benchmark output.
struct HomeFeedAuthority: Equatable, Sendable {
    let content: UUID
    let metadata: UUID
    let recommendations: UUID
    let episodes: UUID
    let availability: UUID
    let owner: UUID
    init(content: UUID = UUID(), metadata: UUID = UUID(), recommendations: UUID = UUID(),
         episodes: UUID = UUID(), availability: UUID = UUID(), owner: UUID = UUID()) {
        self.content = content; self.metadata = metadata; self.recommendations = recommendations
        self.episodes = episodes; self.availability = availability; self.owner = owner
    }
}

struct HomeRecommendation: Equatable, Sendable {
    let articleID: String
    let reason: String
    init(articleID: String, reason: String) { self.articleID = articleID; self.reason = reason }
}

struct HomeFeedInput: Sendable {
    let authority: HomeFeedAuthority
    let articles: [Article]
    let topics: [Topic]
    let sections: [WebflowSection]
    let authors: [Author]
    let episodes: [PodcastEpisode]
    let recommendations: [HomeRecommendation]
    let now: Date
    init(authority: HomeFeedAuthority, articles: [Article], topics: [Topic], sections: [WebflowSection],
         authors: [Author], episodes: [PodcastEpisode], recommendations: [HomeRecommendation] = [], now: Date) {
        self.authority = authority; self.articles = articles; self.topics = topics; self.sections = sections
        self.authors = authors; self.episodes = episodes; self.recommendations = recommendations; self.now = now
    }
    func replacingNow(_ date: Date) -> Self {
        Self(authority: authority, articles: articles, topics: topics, sections: sections, authors: authors,
             episodes: episodes, recommendations: recommendations, now: date)
    }
}

struct HomeRail: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case recommended, reviews, popular, music, culture, seriesFilm
        var title: String {
            switch self {
            case .recommended: return "Anbefalet til dig"
            case .reviews: return "Anmeldelser"
            case .popular: return "Populært"
            case .music: return "Musik"
            case .culture: return "Kultur"
            case .seriesFilm: return "Serier & Film"
            }
        }
        var isTopic: Bool { self == .music || self == .culture || self == .seriesFilm }
    }
    let kind: Kind
    let visible: [Article]
    let all: [Article]
    let reasonsByID: [String: String]
    var id: Kind { kind }
    var title: String { kind.title }
    var isTopic: Bool { kind.isTopic }
    init(kind: Kind, visible: [Article], all: [Article], reasonsByID: [String: String] = [:]) {
        self.kind = kind; self.visible = visible; self.all = all; self.reasonsByID = reasonsByID
    }
}

struct HomeArticleMetadata: Equatable, Sendable {
    let categories: [String]
    let sectionName: String?
    let heroTag: String
    let authorName: String?
    let podcastByline: String
    let heroImageCandidates: [URL]
    let cardImageURL: URL?
    let listImageURL: URL?
}

struct HomePreparationMetrics: Equatable, Sendable {
    var builds = 0
    var archiveSorts = 0
    var metadataBuilds = 0
    var podcastCandidateChecks = 0
    var dateParses = 0
}

/// ALL accepted raw episodes, including lower-ranked historical choices. A
/// duplicate playable ID remains ambiguous instead of being silently deduped.
struct HomeResumeIndex: Equatable, Sendable {
    let playableEpisodesByID: [String: [PodcastEpisode]]
    let articlesByID: [String: Article]
    let fallbackArticleByEpisode: [PodcastEpisode: Article]
    init(playableEpisodesByID: [String: [PodcastEpisode]] = [:], articlesByID: [String: Article] = [:],
         fallbackArticleByEpisode: [PodcastEpisode: Article] = [:]) {
        self.playableEpisodesByID = playableEpisodesByID; self.articlesByID = articlesByID
        self.fallbackArticleByEpisode = fallbackArticleByEpisode
    }
    func pair(episodeID: String?, articleID: String?, hasResumableProgress: Bool) -> PodcastArticlePair? {
        guard hasResumableProgress, let episodeID, let matches = playableEpisodesByID[episodeID],
              matches.count == 1, let episode = matches.first else { return nil }
        let article = articleID.flatMap { articlesByID[$0] } ?? (articleID == nil ? fallbackArticleByEpisode[episode] : nil)
        guard let article, article.hasValidContentIdentity,
              article.contentLanguage != .english || episode.articleId == article.id,
              PodcastAvailabilityModel.hasConsistentIdentity(episode, articleID: article.id) else { return nil }
        return PodcastArticlePair(article: article, episode: HomePodcastIndex.enriched(episode, with: article))
    }
}

struct HomeFeedSnapshot: Equatable, Sendable {
    let authority: HomeFeedAuthority
    let hero: [Article]
    let rails: [HomeRail]
    let metadataByID: [String: HomeArticleMetadata]
    let podcastPairs: [PodcastArticlePair]
    let resumeIndex: HomeResumeIndex
    let nextBoundary: Date?
    let metrics: HomePreparationMetrics
    func rail(_ kind: HomeRail.Kind) -> HomeRail {
        rails.first(where: { $0.kind == kind }) ?? HomeRail(kind: kind, visible: [], all: [])
    }
    func podcastByline(for pair: PodcastArticlePair) -> String {
        pair.episode.playerSubtitleLine(matchingArticle: pair.article, authorLookup: { article in
            metadataByID[article.id]?.authorName.map {
                Author(id: article.authorID ?? "", name: $0, bio: nil, imageURL: nil, position: "", photoURL: "")
            }
        })
    }
}
